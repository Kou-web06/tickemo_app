import CloudKit
import CoreData
import Foundation

struct CloudKitInventory {
  var accountStatus: String
  var zoneExists: Bool
  var recordCountsByType: [String: Int] = [:]
  var localRecordCount: Int = 0
  var error: String?

  var serverChekiRecordCount: Int { recordCountsByType["CD_ChekiRecord"] ?? 0 }
}

/// Reads the CloudKit private database directly, so "did that save actually
/// reach the server?" can be answered with evidence instead of inference.
///
/// `NSPersistentCloudKitContainer` deliberately hides its transport, and
/// `CloudSyncStatusService` can only report on the events it happens to
/// emit — neither tells you what is actually *stored*. Comparing the server
/// count against the local count is the one check that distinguishes
/// "syncing works" from "saves succeed locally and quietly go nowhere",
/// which is exactly the failure mode an undeployed Production schema
/// produces.
struct CloudKitInspector {
  /// The zone `NSPersistentCloudKitContainer` mirrors into. Fixed by Core
  /// Data, not by us.
  static let coreDataZoneName = "com.apple.coredata.cloudkit.zone"

  /// `CKAccountStatus` has no useful `description` — it prints as
  /// `CKAccountStatus(rawValue: 3)`, which is unreadable in a diagnostic
  /// whose whole job is to be read.
  static func describe(_ status: CKAccountStatus) -> String {
    switch status {
    case .available: "available"
    case .noAccount: "noAccount (not signed in to iCloud)"
    case .restricted: "restricted"
    case .couldNotDetermine: "couldNotDetermine"
    case .temporarilyUnavailable: "temporarilyUnavailable"
    @unknown default: "unknown(\(status.rawValue))"
    }
  }

  private let containerIdentifier: String
  private let persistentContainer: NSPersistentContainer

  init(
    containerIdentifier: String = PersistenceController.cloudKitContainerIdentifier,
    persistentContainer: NSPersistentContainer = PersistenceController.shared.container
  ) {
    self.containerIdentifier = containerIdentifier
    self.persistentContainer = persistentContainer
  }

  func inventory() async -> CloudKitInventory {
    let container = CKContainer(identifier: containerIdentifier)
    var result = CloudKitInventory(accountStatus: "unknown", zoneExists: false)

    result.localRecordCount = await localRecordCount()

    do {
      result.accountStatus = Self.describe(try await container.accountStatus())
    } catch {
      result.accountStatus = "error: \(error.localizedDescription)"
      result.error = "\(error)"
      return result
    }

    let database = container.privateCloudDatabase
    let zoneID = CKRecordZone.ID(zoneName: Self.coreDataZoneName, ownerName: CKCurrentUserDefaultName)

    do {
      _ = try await database.recordZone(for: zoneID)
      result.zoneExists = true
    } catch {
      // No zone means nothing has ever been exported — the single most
      // useful signal here, so it's reported rather than treated as a
      // failure to inspect.
      result.error = "zone not found: \(error.localizedDescription)"
      return result
    }

    do {
      result.recordCountsByType = try await countRecords(in: database, zoneID: zoneID)
    } catch {
      result.error = "\(error)"
    }

    return result
  }

  /// Enumerates the zone rather than running a `CKQuery`: a query needs
  /// queryable indexes, which Core Data's generated schema doesn't
  /// necessarily provide, whereas zone-change enumeration always works.
  /// `desiredKeys: []` keeps it to metadata so this never downloads the
  /// user's photos just to count them.
  private func countRecords(
    in database: CKDatabase,
    zoneID: CKRecordZone.ID
  ) async throws -> [String: Int] {
    try await withCheckedThrowingContinuation { continuation in
      var counts: [String: Int] = [:]
      var didResume = false

      let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
      configuration.previousServerChangeToken = nil
      configuration.desiredKeys = []

      let operation = CKFetchRecordZoneChangesOperation(
        recordZoneIDs: [zoneID],
        configurationsByRecordZoneID: [zoneID: configuration]
      )
      operation.fetchAllChanges = true

      operation.recordWasChangedBlock = { _, result in
        guard case .success(let record) = result else { return }
        counts[record.recordType, default: 0] += 1
      }

      operation.fetchRecordZoneChangesResultBlock = { result in
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success:
          continuation.resume(returning: counts)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }

      database.add(operation)
    }
  }

  private func localRecordCount() async -> Int {
    let context = persistentContainer.newBackgroundContext()
    return await context.perform {
      (try? context.count(for: CD_ChekiRecord.fetchRequest())) ?? 0
    }
  }
}
