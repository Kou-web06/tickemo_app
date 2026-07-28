import Foundation
import CryptoKit

/// Separates "get the raw legacy store JSON string" (real filesystem I/O)
/// from parsing, so unit tests can stub this with a fixture string and
/// exercise the Decodable models without needing a real AsyncStorage
/// manifest.json on disk.
protocol LegacyStoreLoading {
  func loadRawStoreJSON() -> String?
}

/// Reads the RN app's persisted Zustand state directly from
/// `@react-native-async-storage/async-storage`'s on-disk format (confirmed
/// by reading `RNCAsyncStorage.mm`): a flat `manifest.json` dictionary keyed
/// by the raw storage key. Values up to 1024 bytes are inlined directly in
/// the manifest; larger values are stored `null` in the manifest with the
/// real content in a sibling file named by the lowercase-hex MD5 hash of the
/// key (matching `RCTMD5Hash` in React Native's own `RCTUtils.mm`).
struct AsyncStorageLoader: LegacyStoreLoading {
  static let storageKey = "tickemo-store"

  func loadRawStoreJSON() -> String? {
    guard let bundleID = Bundle.main.bundleIdentifier,
          let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }

    let storageDir = appSupport
      .appendingPathComponent(bundleID)
      .appendingPathComponent("RCTAsyncLocalStorage_V1")
    let manifestURL = storageDir.appendingPathComponent("manifest.json")

    guard let manifestData = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
          let entry = manifest[Self.storageKey]
    else { return nil }

    if let inlineValue = entry as? String {
      return inlineValue
    }

    // Manifest held null (or a non-string value): the key's value exceeded
    // AsyncStorage's inline threshold and lives in a sibling file instead.
    let digest = Insecure.MD5.hash(data: Data(Self.storageKey.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return try? String(contentsOf: storageDir.appendingPathComponent(hex), encoding: .utf8)
  }
}
