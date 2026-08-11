import CoreData

struct DataMigrationSummary {
  var recordCount: Int = 0
  var recordsAlreadyPresent: Int = 0
  var setlistItemCount: Int = 0
  var imageCount: Int = 0
  var profileImported: Bool = false
  var source: String = "none"
  var backupURL: URL?
  var error: String?

  var importedAnything: Bool {
    recordCount > 0 || setlistItemCount > 0 || imageCount > 0 || profileImported
  }
}

/// Imports the RN app's persisted store (AsyncStorage first, the ubiquity
/// container's sync JSON as a reinstall fallback) into Core Data + CloudKit.
///
/// The single most important property here is that **running it twice is
/// harmless**. Every write is an upsert keyed on something stable and
/// derived from the legacy data itself — `StableLegacyID` for records and
/// setlist items, the legacy relative path for images — and scalar fields
/// are written only when a row is first created. That means:
///
/// - a crash or a kill mid-import resumes cleanly instead of doubling rows;
/// - a second device that imports before CloudKit reaches it produces rows
///   that `DuplicateRecordSweeper` can recognise and collapse;
/// - a re-import can never revert an edit the user made in the native app,
///   because existing rows are left alone.
///
/// Deciding *whether* to run at all is `MigrationCoordinator`'s job — this
/// type imports when asked and reports what it did.
///
/// `@unchecked Sendable`: every stored property is a `let` holding either a
/// value type or a stateless helper, so instances carry no mutable state to
/// race over. The Core Data work is confined to `context.perform`.
final class DataMigrationImporter: @unchecked Sendable {
  /// Kept for backwards compatibility: builds before the iCloud key-value
  /// claim shipped recorded completion here, and `MigrationCoordinator`
  /// still honours it so those users don't re-run.
  static let hasMigratedKey = "hasMigratedFromRNStore"

  /// Records are imported in chunks so that image `Data` for at most this
  /// many tickets is resident at once, and so an interrupted import leaves
  /// durably saved progress behind rather than nothing.
  private static let batchSize = 20

  private let container: NSPersistentCloudKitContainer
  private let legacyStoreLoader: LegacyStoreLoading
  private let iCloudFallbackLoader: ICloudFallbackLoader
  private let imageMigrator: ImageMigrator
  private let backup: LegacyDataBackup

  init(
    container: NSPersistentCloudKitContainer = PersistenceController.shared.container,
    legacyStoreLoader: LegacyStoreLoading = AsyncStorageLoader(),
    iCloudFallbackLoader: ICloudFallbackLoader = ICloudFallbackLoader(),
    imageMigrator: ImageMigrator = ImageMigrator(),
    backup: LegacyDataBackup = LegacyDataBackup()
  ) {
    self.container = container
    self.legacyStoreLoader = legacyStoreLoader
    self.iCloudFallbackLoader = iCloudFallbackLoader
    self.imageMigrator = imageMigrator
    self.backup = backup
  }

  // MARK: - Entry points

  /// Cheap, synchronous "is there any point doing migration work at all?".
  /// Deliberately avoids the ubiquity download wait that a full load can
  /// incur, so a brand new user isn't held behind a migration UI on their
  /// very first launch.
  func hasAnyLegacySignal() -> Bool {
    if legacyStoreLoader.loadRawStoreJSON() != nil { return true }
    return iCloudFallbackLoader.hasCandidateFile()
  }

  enum Scope {
    case everything
    /// Only legacy records created after `cutoff`, and no profile.
    ///
    /// Covers the phased-rollout window: once one device has migrated, a
    /// second device still running the RN build keeps writing new tickets
    /// into `tickemo_data.json`. When that device finally updates it sees a
    /// claim, waits for CloudKit, finds data and skips the import — so
    /// without this those tickets would be dropped silently. Anchoring on
    /// the claim timestamp is what keeps this from also resurrecting
    /// records deleted in the native app, which are all older than it.
    case createdAfter(Date)
  }

  /// Imports whatever legacy data can be found. A summary whose `source` is
  /// still `"none"` and whose `error` is nil means there was simply nothing
  /// to import (a genuinely new user) — that is success, not failure.
  func run(scope: Scope = .everything) async -> DataMigrationSummary {
    var summary = DataMigrationSummary()

    guard let loaded = await loadLegacyState() else {
      return summary
    }
    summary.source = loaded.source

    let state = narrow(loaded.state, to: scope)
    if case .createdAfter = scope, state.lives.isEmpty {
      // Nothing new on the legacy side. Bail before touching Core Data or
      // writing a backup — this path runs on every launch during the
      // rollout window.
      summary.source = "none"
      return summary
    }

    if case .everything = scope {
      summary.backupURL = backup.store(rawJSON: loaded.rawJSON, source: loaded.source)
    }

    let context = container.newBackgroundContext()
    // The importer only ever inserts; property-level trumping is the right
    // resolution for the case where CloudKit delivers the same row while a
    // batch is in flight.
    context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    context.automaticallyMergesChangesFromParent = true
    context.name = "legacy-migration-import"

    do {
      let recordCounts = try await importRecords(state, into: context)
      summary.recordCount = recordCounts.created
      summary.recordsAlreadyPresent = recordCounts.alreadyPresent
      summary.setlistItemCount = recordCounts.setlistItems
      summary.imageCount = recordCounts.images
      summary.profileImported = try await importProfile(state, into: context)
    } catch {
      summary.error = "\(error)"
    }

    return summary
  }

  private func narrow(_ state: LegacyState, to scope: Scope) -> LegacyState {
    switch scope {
    case .everything:
      return state
    case .createdAfter(let cutoff):
      let lives = state.lives.filter { legacy in
        // An unparseable timestamp counts as recent on purpose. Being
        // wrong that way produces a visible extra ticket the user can
        // delete; being wrong the other way drops one silently.
        guard let createdAt = DateFormatting.isoDate(from: legacy.createdAt) else { return true }
        return createdAt > cutoff
      }
      return LegacyState(lives: lives, setlists: state.setlists, userProfile: nil)
    }
  }

  // MARK: - Loading

  struct LegacyState {
    let lives: [LegacyChekiRecord]
    let setlists: [String: [LegacySetlistItem]]
    let userProfile: LegacyUserProfile?
  }

  private struct LoadedLegacyData {
    let state: LegacyState
    let source: String
    let rawJSON: String
  }

  private func loadLegacyState() async -> LoadedLegacyData? {
    if let raw = legacyStoreLoader.loadRawStoreJSON(), let data = raw.data(using: .utf8),
       let envelope = try? JSONDecoder().decode(ZustandEnvelope.self, from: data) {
      return LoadedLegacyData(
        state: LegacyState(
          lives: envelope.state.lives,
          setlists: envelope.state.setlists,
          userProfile: envelope.state.userProfile
        ),
        source: "AsyncStorage",
        rawJSON: raw
      )
    }

    if let raw = await iCloudFallbackLoader.loadRawStoreJSON(), let data = raw.data(using: .utf8) {
      if let dataJSON = try? JSONDecoder().decode(ICloudDataJSON.self, from: data) {
        return LoadedLegacyData(
          state: LegacyState(lives: dataJSON.lives, setlists: dataJSON.setlists, userProfile: dataJSON.userProfile),
          source: "iCloud (tickemo_data.json)",
          rawJSON: raw
        )
      }
      if let kvsJSON = try? JSONDecoder().decode(ICloudKvsJSON.self, from: data) {
        return LoadedLegacyData(
          state: LegacyState(lives: kvsJSON.lives, setlists: kvsJSON.setlists, userProfile: kvsJSON.userProfile),
          source: "iCloud (tickemo_kvs.json)",
          rawJSON: raw
        )
      }
    }

    return nil
  }

  // MARK: - Records

  private struct RecordCounts {
    var created = 0
    var alreadyPresent = 0
    var setlistItems = 0
    var images = 0
  }

  private func importRecords(
    _ state: LegacyState,
    into context: NSManagedObjectContext
  ) async throws -> RecordCounts {
    var counts = RecordCounts()

    for batch in state.lives.chunked(into: Self.batchSize) {
      // Phase 1 (Core Data): create the rows that don't exist yet, and work
      // out which images still need their bytes read off disk.
      let phase1 = try await context.perform { [self] () -> (ImageResolutionPlan, RecordCounts) in
        var batchCounts = RecordCounts()
        var plan = ImageResolutionPlan()

        for legacy in batch {
          let uuid = StableLegacyID.uuid(for: legacy.id)
          let record: CD_ChekiRecord

          if let existing = try fetchChekiRecord(id: uuid, in: context) {
            // Never overwrite: this row is either fully imported already or
            // is the user's own current data arrived via CloudKit. Either
            // way the legacy scalars are the stale copy.
            record = existing
            batchCounts.alreadyPresent += 1
          } else {
            record = CD_ChekiRecord(context: context)
            record.id = uuid
            apply(legacy, to: record)
            batchCounts.created += 1
          }

          batchCounts.setlistItems += upsertSetlistItems(
            state.setlists[legacy.id] ?? [],
            on: record,
            in: context
          )

          plan.add(missingImagesFor: legacy, on: record)
        }

        try saveIfNeeded(context)
        return (plan, batchCounts)
      }

      counts.created += phase1.1.created
      counts.alreadyPresent += phase1.1.alreadyPresent
      counts.setlistItems += phase1.1.setlistItems

      // Phase 2 (off the context): the slow part — reading local files and,
      // for a reinstall, pulling and base64-decoding the iCloud copies.
      let plan = phase1.0
      var resolved: [ImageResolutionPlan.Key: Data] = [:]
      for request in plan.requests where resolved[request.key] == nil {
        if let data = await imageMigrator.resolveImageData(forRelativePath: request.key.relativePath) {
          resolved[request.key] = data
        }
      }

      guard !resolved.isEmpty else { continue }

      // Phase 3 (Core Data): attach the bytes. Records are re-looked-up by
      // their stable UUID rather than by an `NSManagedObjectID` captured in
      // phase 1 — those are temporary IDs for freshly inserted rows and are
      // replaced by the save at the end of phase 1.
      counts.images += try await context.perform { [self] () -> Int in
        let recordIDs = Set(plan.requests.map(\.key.recordID))
        let recordsByID = try fetchChekiRecords(ids: recordIDs, in: context)
        var attached = 0

        for request in plan.requests {
          guard let data = resolved[request.key] else { continue }
          guard let record = recordsByID[request.key.recordID] else { continue }
          guard !hasImage(withLegacyPath: request.key.relativePath, on: record) else { continue }

          let image = CD_LiveImage(context: context)
          image.id = UUID()
          image.orderIndex = Int16(clamping: request.orderIndex)
          image.data = data
          image.legacyRelativePath = request.key.relativePath
          image.assetIdentifier = request.assetIdentifier
          image.record = record
          attached += 1
        }

        try saveIfNeeded(context)
        return attached
      }
    }

    return counts
  }

  private func fetchChekiRecord(id: UUID, in context: NSManagedObjectContext) throws -> CD_ChekiRecord? {
    let request = CD_ChekiRecord.fetchRequest()
    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
    request.fetchLimit = 1
    return try context.fetch(request).first
  }

  private func fetchChekiRecords(
    ids: Set<UUID>,
    in context: NSManagedObjectContext
  ) throws -> [UUID: CD_ChekiRecord] {
    guard !ids.isEmpty else { return [:] }
    let request = CD_ChekiRecord.fetchRequest()
    request.predicate = NSPredicate(format: "id IN %@", ids)
    return try context.fetch(request).reduce(into: [:]) { result, record in
      guard let id = record.id else { return }
      result[id] = record
    }
  }

  /// Adds only the setlist items this record doesn't already have, keyed on
  /// the legacy item id. Items the user added natively are never touched,
  /// and a re-run adds nothing.
  private func upsertSetlistItems(
    _ legacyItems: [LegacySetlistItem],
    on record: CD_ChekiRecord,
    in context: NSManagedObjectContext
  ) -> Int {
    guard !legacyItems.isEmpty else { return 0 }

    var knownIDs = Set((record.setlistItems as? Set<CD_SetlistItem> ?? []).compactMap(\.id))
    var added = 0

    for legacy in legacyItems {
      let uuid = StableLegacyID.uuid(for: legacy.id)
      guard !knownIDs.contains(uuid) else { continue }
      knownIDs.insert(uuid)

      let item = CD_SetlistItem(context: context)
      item.id = uuid
      apply(legacy, to: item)
      item.record = record
      added += 1
    }

    return added
  }

  private func hasImage(withLegacyPath path: String, on record: CD_ChekiRecord) -> Bool {
    let images = record.images as? Set<CD_LiveImage> ?? []
    return images.contains { $0.legacyRelativePath == path }
  }

  // MARK: - Profile

  private func importProfile(
    _ state: LegacyState,
    into context: NSManagedObjectContext
  ) async throws -> Bool {
    guard let legacyProfile = state.userProfile else { return false }

    let outcome = try await context.perform { [self] () -> (created: Bool, needsAvatar: NSManagedObjectID?) in
      let request = CD_UserProfile.fetchRequest()
      request.fetchLimit = 1
      let existing = try context.fetch(request).first

      let profile: CD_UserProfile
      var created = false
      if let existing {
        profile = existing
      } else {
        profile = CD_UserProfile(context: context)
        profile.id = UUID()
        created = true
      }

      // Gap-filling rather than overwriting: a profile arriving from
      // CloudKit is newer than the legacy blob, but a partially populated
      // one should still pick up whatever the legacy blob can supply.
      if profile.name?.isEmpty ?? true { profile.name = legacyProfile.name }
      if profile.username?.isEmpty ?? true { profile.username = legacyProfile.username }
      if profile.joinedAt?.isEmpty ?? true { profile.joinedAt = legacyProfile.joinedAt }
      if profile.plusStartedAt?.isEmpty ?? true { profile.plusStartedAt = legacyProfile.plusStartedAt }

      let needsAvatar = profile.avatarImageData == nil
      try saveIfNeeded(context)
      // Read after the save so the id is permanent.
      return (created, needsAvatar ? profile.objectID : nil)
    }

    guard let profileObjectID = outcome.needsAvatar,
          let avatarURI = legacyProfile.avatarUri,
          let avatarData = await imageMigrator.resolveImageData(forRelativePath: avatarURI)
    else { return outcome.created }

    try await context.perform { [self] in
      guard let profile = try context.existingObject(with: profileObjectID) as? CD_UserProfile,
            profile.avatarImageData == nil
      else { return }
      profile.avatarImageData = avatarData
      try saveIfNeeded(context)
    }

    return outcome.created
  }

  // MARK: - Field mapping

  private func apply(_ legacy: LegacyChekiRecord, to record: CD_ChekiRecord) {
    record.liveName = legacy.liveName
    record.liveType = legacy.liveType
    record.date = legacy.date
    record.venue = legacy.venue
    record.seat = legacy.seat
    record.ticketPrice = legacy.ticketPrice ?? 0
    record.startTime = legacy.startTime
    record.endTime = legacy.endTime
    record.imagePath = legacy.imagePath
    record.artist = legacy.artist
    record.artistImageUrl = legacy.artistImageUrl
    record.artists = legacy.artists.map { NSArray(array: $0) }
    record.artistImageUrls = legacy.artistImageUrls.map { NSArray(array: $0) }
    record.memo = legacy.memo
    record.detail = legacy.detail
    record.qrCode = legacy.qrCode
    record.createdAt = legacy.createdAt
  }

  private func apply(_ legacy: LegacySetlistItem, to item: CD_SetlistItem) {
    item.orderIndex = Int32(clamping: legacy.orderIndex)

    switch legacy {
    case .song(_, let songId, let songName, let artistName, let albumName, let artworkUrl, _):
      item.kind = "song"
      item.songId = songId
      item.songName = songName
      item.artistName = artistName
      item.albumName = albumName
      item.artworkUrl = artworkUrl
    case .encore(_, let title, _):
      item.kind = "encore"
      item.title = title
    case .mc(_, let title, let note, _):
      item.kind = "mc"
      item.title = title
      item.note = note
    }
  }

  private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
    guard context.hasChanges else { return }
    try context.save()
  }
}

// MARK: - Image resolution planning

/// Collects "this record is missing the image at this legacy path" across a
/// batch, so file/iCloud reads happen outside `context.perform` and are
/// skipped entirely for images a previous run already imported.
private struct ImageResolutionPlan {
  struct Key: Hashable {
    let recordID: UUID
    let relativePath: String
  }

  struct Request {
    let key: Key
    let orderIndex: Int
    let assetIdentifier: String?
  }

  private(set) var requests: [Request] = []

  mutating func add(missingImagesFor legacy: LegacyChekiRecord, on record: CD_ChekiRecord) {
    guard let imageUrls = legacy.imageUrls, let recordID = record.id else { return }
    let assetIds = legacy.imageAssetIds ?? []
    var seen = Set((record.images as? Set<CD_LiveImage> ?? []).compactMap(\.legacyRelativePath))

    for (index, path) in imageUrls.enumerated() {
      // A legacy record can list the same path twice; only import it once.
      guard !seen.contains(path) else { continue }
      seen.insert(path)

      requests.append(
        Request(
          key: Key(recordID: recordID, relativePath: path),
          orderIndex: index,
          assetIdentifier: index < assetIds.count ? assetIds[index] : nil
        )
      )
    }
  }
}

extension Array {
  fileprivate func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}
