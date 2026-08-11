import CloudKit
import CoreData

struct DuplicateSweepSummary: Equatable {
  var mergedRecordGroups = 0
  var deletedRecords = 0
  var deletedSetlistItems = 0
  var deletedImages = 0
  var deletedProfiles = 0
  /// Groups left alone this pass because not every member had a CloudKit
  /// identity yet. They'll be picked up by a later sweep.
  var deferredGroups = 0

  var didChangeAnything: Bool {
    deletedRecords > 0 || deletedSetlistItems > 0 || deletedImages > 0 || deletedProfiles > 0
  }
}

/// Collapses duplicate rows that survive the claim gate in
/// `MigrationCoordinator`.
///
/// The claim makes a double import unlikely; it cannot make it impossible,
/// because `NSUbiquitousKeyValueStore` is eventually consistent and two
/// devices launching within the same propagation window can both see "not
/// claimed". `NSPersistentCloudKitContainer` won't collapse the result on
/// its own — it names `CKRecord`s from its own internal identifiers, not
/// from our `id` attribute, and CloudKit-backed models can't declare
/// uniqueness constraints. So the duplicates have to be found and merged
/// after the fact, which is what this does.
///
/// The delicate part is that every device must reach the *same* answer,
/// or one device deletes the row another device kept and the merge never
/// converges. So the winner of each group is chosen by CloudKit record
/// name — a value CloudKit itself replicates, therefore identical
/// everywhere — and a group is skipped entirely until every member has one.
/// Children are re-parented onto the winner before any delete, so the
/// `Cascade` rule on `images`/`setlistItems` can never take a photo or a
/// setlist with it.
///
/// `@unchecked Sendable`: both stored properties are immutable `let`s and
/// all Core Data work is confined to `context.perform`.
final class DuplicateRecordSweeper: @unchecked Sendable {
  private let container: NSPersistentCloudKitContainer
  private let cloudKitAvailable: Bool

  init(
    container: NSPersistentCloudKitContainer = PersistenceController.shared.container,
    cloudKitAvailable: Bool = FileManager.default.ubiquityIdentityToken != nil
  ) {
    self.container = container
    self.cloudKitAvailable = cloudKitAvailable
  }

  @discardableResult
  func sweep() async throws -> DuplicateSweepSummary {
    let context = container.newBackgroundContext()
    context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    context.automaticallyMergesChangesFromParent = true
    context.name = "duplicate-sweep"

    return try await context.perform { [self] in
      var summary = DuplicateSweepSummary()

      try mergeDuplicateRecords(in: context, summary: &summary)
      try deduplicateChildren(in: context, summary: &summary)
      try mergeDuplicateProfiles(in: context, summary: &summary)

      if context.hasChanges {
        try context.save()
      }
      return summary
    }
  }

  // MARK: - Records

  private func mergeDuplicateRecords(
    in context: NSManagedObjectContext,
    summary: inout DuplicateSweepSummary
  ) throws {
    let request = CD_ChekiRecord.fetchRequest()
    request.relationshipKeyPathsForPrefetching = ["setlistItems", "images"]
    let records = try context.fetch(request)

    var groups: [UUID: [CD_ChekiRecord]] = [:]
    for record in records {
      guard let id = record.id else {
        // A row with no id is invisible to every dedup and ordering path in
        // the app. Give it one rather than leaving it unreachable.
        record.id = UUID()
        continue
      }
      groups[id, default: []].append(record)
    }

    for (_, members) in groups where members.count > 1 {
      let identified = members.map { (record: $0, identity: syncIdentity(for: $0)) }

      guard let ranked = rank(identified) else {
        summary.deferredGroups += 1
        continue
      }

      let winner = ranked[0]
      for loser in ranked.dropFirst() {
        // Re-parent first: `images`/`setlistItems` both cascade on delete,
        // so detaching them is what keeps the loser's photos alive.
        for item in loser.setlistItems as? Set<CD_SetlistItem> ?? [] {
          item.record = winner
        }
        for image in loser.images as? Set<CD_LiveImage> ?? [] {
          image.record = winner
        }
        context.delete(loser)
        summary.deletedRecords += 1
      }
      summary.mergedRecordGroups += 1
    }
  }

  // MARK: - Children

  /// Runs over every record, not just merged ones: a device can also end up
  /// with duplicate children on a *single* record when CloudKit delivers the
  /// record before its images, and the local import then re-adds images it
  /// couldn't yet see.
  private func deduplicateChildren(
    in context: NSManagedObjectContext,
    summary: inout DuplicateSweepSummary
  ) throws {
    let request = CD_ChekiRecord.fetchRequest()
    request.relationshipKeyPathsForPrefetching = ["setlistItems", "images"]

    for record in try context.fetch(request) {
      let items = Array(record.setlistItems as? Set<CD_SetlistItem> ?? [])
      summary.deletedSetlistItems += collapse(items, in: context) { item in
        item.id?.uuidString ?? "fallback:\(item.kind ?? "")|\(item.orderIndex)|\(item.title ?? "")|\(item.songName ?? "")"
      }

      let images = Array(record.images as? Set<CD_LiveImage> ?? [])
      summary.deletedImages += collapse(images, in: context) { image in
        // Deliberately never keys on `data`: hashing the blobs would fault
        // every photo in the store into memory. Imported images always
        // carry their legacy path, and natively created ones always carry
        // an id, so one of the two is always present.
        if let path = image.legacyRelativePath, !path.isEmpty { return "path:\(path)" }
        if let id = image.id { return "id:\(id.uuidString)" }
        return "object:\(image.objectID.uriRepresentation().absoluteString)"
      }
    }
  }

  /// Keeps one member per key and deletes the rest, choosing the survivor
  /// with the same cross-device-stable rule used for records. Returns how
  /// many rows were deleted.
  private func collapse<T: NSManagedObject>(
    _ objects: [T],
    in context: NSManagedObjectContext,
    key: (T) -> String
  ) -> Int {
    var buckets: [String: [T]] = [:]
    for object in objects {
      buckets[key(object), default: []].append(object)
    }

    var deleted = 0
    for (_, members) in buckets where members.count > 1 {
      let identified = members.map { (record: $0, identity: syncIdentity(for: $0)) }
      guard let ranked = rank(identified) else { continue }
      for loser in ranked.dropFirst() {
        context.delete(loser)
        deleted += 1
      }
    }
    return deleted
  }

  // MARK: - Profile

  private func mergeDuplicateProfiles(
    in context: NSManagedObjectContext,
    summary: inout DuplicateSweepSummary
  ) throws {
    let profiles = try context.fetch(CD_UserProfile.fetchRequest())
    guard profiles.count > 1 else { return }

    let identified = profiles.map { (record: $0, identity: syncIdentity(for: $0)) }
    guard let ranked = rank(identified) else {
      summary.deferredGroups += 1
      return
    }

    let winner = ranked[0]
    for loser in ranked.dropFirst() {
      // The profile is a singleton, so a duplicate is always two devices'
      // views of the same person: fill any gap from the loser instead of
      // dropping whatever it happened to have.
      if winner.name?.isEmpty ?? true { winner.name = loser.name }
      if winner.username?.isEmpty ?? true { winner.username = loser.username }
      if winner.joinedAt?.isEmpty ?? true { winner.joinedAt = loser.joinedAt }
      if winner.plusStartedAt?.isEmpty ?? true { winner.plusStartedAt = loser.plusStartedAt }
      if winner.avatarImageData == nil { winner.avatarImageData = loser.avatarImageData }
      if winner.id == nil { winner.id = loser.id ?? UUID() }

      context.delete(loser)
      summary.deletedProfiles += 1
    }
  }

  // MARK: - Cross-device-stable ordering

  /// Sorts a group so index 0 is the survivor, or returns nil when the
  /// group must be deferred because CloudKit hasn't named every member yet
  /// (acting on a partial view risks two devices picking different
  /// survivors, which never converges).
  private func rank<T: NSManagedObject>(_ identified: [(record: T, identity: String?)]) -> [T]? {
    if cloudKitAvailable && identified.contains(where: { $0.identity == nil }) {
      return nil
    }
    return identified
      .map { ($0.record, $0.identity ?? $0.record.objectID.uriRepresentation().absoluteString) }
      .sorted { $0.1 < $1.1 }
      .map(\.0)
  }

  private func syncIdentity(for object: NSManagedObject) -> String? {
    container.recordID(for: object.objectID)?.recordName
  }
}
