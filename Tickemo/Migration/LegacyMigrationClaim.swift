import Foundation

/// The record of "some device has already imported the RN store into Core
/// Data + CloudKit". Stored as JSON so a future field can be added without
/// invalidating claims written by an older build.
struct MigrationClaim: Codable, Equatable {
  var deviceID: String
  var claimedAt: Date
  var source: String
  var recordCount: Int
}

/// The subset of `NSUbiquitousKeyValueStore` that `LegacyMigrationClaim`
/// needs, so tests can drive the claim logic without touching real iCloud.
protocol UbiquitousClaimStore: AnyObject {
  @discardableResult func synchronize() -> Bool
  func string(forKey key: String) -> String?
  func setString(_ value: String?, forKey key: String)
}

/// Wraps `NSUbiquitousKeyValueStore` rather than conforming it directly:
/// its `set(_:forKey:)` family is a set of overloads on `Any?`/`String?`/
/// `Data?`/… that Swift can't unambiguously match against a single protocol
/// requirement.
final class ICloudKeyValueClaimStore: UbiquitousClaimStore {
  private let store: NSUbiquitousKeyValueStore

  init(store: NSUbiquitousKeyValueStore = .default) {
    self.store = store
  }

  @discardableResult
  func synchronize() -> Bool {
    store.synchronize()
  }

  func string(forKey key: String) -> String? {
    store.string(forKey: key)
  }

  func setString(_ value: String?, forKey key: String) {
    if let value {
      store.set(value, forKey: key)
    } else {
      store.removeObject(forKey: key)
    }
    store.synchronize()
  }
}

/// In-memory stand-in used by `LegacyMigrationClaimTests`.
final class InMemoryClaimStore: UbiquitousClaimStore {
  private var values: [String: String] = [:]
  private(set) var synchronizeCallCount = 0

  init(initialValues: [String: String] = [:]) {
    values = initialValues
  }

  @discardableResult
  func synchronize() -> Bool {
    synchronizeCallCount += 1
    return true
  }

  func string(forKey key: String) -> String? {
    values[key]
  }

  func setString(_ value: String?, forKey key: String) {
    values[key] = value
  }
}

/// Gates the one-shot RN→Core Data import on a flag kept in iCloud's
/// key-value store rather than `UserDefaults`.
///
/// `UserDefaults` alone is wrong in two ways that both end in duplicated
/// tickets:
///
/// - It is wiped by a reinstall. A returning user's Core Data store starts
///   empty and CloudKit's first import is asynchronous, so a `UserDefaults`
///   gate sees "no local data" and re-imports the stale `tickemo_data.json`
///   still sitting in the ubiquity container — on top of whatever CloudKit
///   is about to deliver.
/// - It is per-device. A two-device user would import the same legacy blob
///   twice, and `NSPersistentCloudKitContainer` derives `CKRecord` names
///   from its own internal identifiers (not our `id` attribute) and doesn't
///   support unique constraints, so the two imports do not collapse.
///
/// `NSUbiquitousKeyValueStore` survives reinstalls and is shared across the
/// user's devices, which closes both. It is *eventually* consistent, not
/// atomic, so it can't rule out a genuine simultaneous race — that residual
/// case is handled after the fact by `DuplicateRecordSweeper`. Treat this
/// as the cheap first line of defence, not the only one.
///
/// `@unchecked Sendable`: both stored properties are `let`s wrapping
/// `NSUbiquitousKeyValueStore`/`UserDefaults`, which are themselves
/// thread-safe.
final class LegacyMigrationClaim: @unchecked Sendable {
  static let claimKey = "legacyStoreMigrationClaim.v1"
  /// Local mirror of the claim. Lets a warm launch skip the iCloud round
  /// trip entirely, and keeps the gate working when iCloud is unavailable.
  static let localClaimKey = "legacyStoreMigrationClaim.local.v1"
  static let deviceIDKey = "legacyStoreMigrationDeviceID"

  private let ubiquitous: UbiquitousClaimStore
  private let userDefaults: UserDefaults

  init(
    ubiquitous: UbiquitousClaimStore = ICloudKeyValueClaimStore(),
    userDefaults: UserDefaults = .standard
  ) {
    self.ubiquitous = ubiquitous
    self.userDefaults = userDefaults
  }

  /// Stable for the lifetime of this install. Deliberately not
  /// `identifierForVendor`, which is nil before first unlock and can change
  /// when the last app from a vendor is removed — this only needs to
  /// distinguish "this install" from "another install" in claim metadata.
  var deviceID: String {
    if let existing = userDefaults.string(forKey: Self.deviceIDKey) {
      return existing
    }
    let generated = UUID().uuidString
    userDefaults.set(generated, forKey: Self.deviceIDKey)
    return generated
  }

  /// The local mirror only. Cheap; no iCloud round trip.
  var localClaim: MigrationClaim? {
    decode(userDefaults.string(forKey: Self.localClaimKey))
  }

  /// Pulls the latest value from iCloud before reading. Callers should
  /// treat a `nil` result as "probably not claimed" rather than proof —
  /// key-value store propagation is not instantaneous.
  func currentClaim(refreshing: Bool = true) -> MigrationClaim? {
    if refreshing {
      ubiquitous.synchronize()
    }
    if let remote = decode(ubiquitous.string(forKey: Self.claimKey)) {
      // Keep the local mirror in step so later launches can short-circuit
      // and so the gate survives losing iCloud access.
      mirrorLocally(remote)
      return remote
    }
    return localClaim
  }

  @discardableResult
  func claim(source: String, recordCount: Int, now: Date = Date()) -> MigrationClaim {
    let claim = MigrationClaim(
      deviceID: deviceID,
      claimedAt: Self.wholeSeconds(now),
      source: source,
      recordCount: recordCount
    )
    if let encoded = encode(claim) {
      ubiquitous.setString(encoded, forKey: Self.claimKey)
      userDefaults.set(encoded, forKey: Self.localClaimKey)
    }
    return claim
  }

  /// Debug/support affordance only — clearing the claim re-arms the
  /// importer, which is safe because the import is an upsert, but it should
  /// never happen as part of normal operation.
  func clear() {
    ubiquitous.setString(nil, forKey: Self.claimKey)
    userDefaults.removeObject(forKey: Self.localClaimKey)
  }

  /// The claim is serialized as second-resolution ISO8601, so storing a
  /// sub-second timestamp would make the value that comes back out differ
  /// from the one just written. That matters beyond tidiness: the
  /// late-arrival reconcile compares legacy `createdAt` values against this
  /// timestamp, and a cutoff that shifts by a fraction of a second
  /// depending on whether it was read from memory or from iCloud is a
  /// cutoff that can't be reasoned about.
  private static func wholeSeconds(_ date: Date) -> Date {
    Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
  }

  private func mirrorLocally(_ claim: MigrationClaim) {
    guard let encoded = encode(claim) else { return }
    userDefaults.set(encoded, forKey: Self.localClaimKey)
  }

  private func encode(_ claim: MigrationClaim) -> String? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(claim) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func decode(_ raw: String?) -> MigrationClaim? {
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(MigrationClaim.self, from: data)
  }
}
