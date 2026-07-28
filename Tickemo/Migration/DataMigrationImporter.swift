import CoreData

struct DataMigrationSummary {
  var recordCount: Int = 0
  var setlistItemCount: Int = 0
  var imageCount: Int = 0
  var profileImported: Bool = false
  var source: String = "none"
  var error: String?
}

/// One-shot importer that reads the RN app's legacy persisted data
/// (AsyncStorage first, iCloud Documents as a reinstall fallback) and
/// imports it into the new Core Data + CloudKit store. Gated on
/// `hasMigratedFromRNStore` in UserDefaults; per the migration plan, the
/// import itself never re-runs once data exists locally — only a pending
/// initial CloudKit push is retried on a subsequent launch.
@MainActor
final class DataMigrationImporter {
  static let hasMigratedKey = "hasMigratedFromRNStore"

  private let container: NSPersistentCloudKitContainer
  private let context: NSManagedObjectContext
  private let legacyStoreLoader: LegacyStoreLoading
  private let iCloudFallbackLoader: ICloudFallbackLoader
  private let imageMigrator: ImageMigrator
  private let userDefaults: UserDefaults

  init(
    container: NSPersistentCloudKitContainer = PersistenceController.shared.container,
    legacyStoreLoader: LegacyStoreLoading = AsyncStorageLoader(),
    iCloudFallbackLoader: ICloudFallbackLoader = ICloudFallbackLoader(),
    imageMigrator: ImageMigrator = ImageMigrator(),
    userDefaults: UserDefaults = .standard
  ) {
    self.container = container
    self.context = container.viewContext
    self.legacyStoreLoader = legacyStoreLoader
    self.iCloudFallbackLoader = iCloudFallbackLoader
    self.imageMigrator = imageMigrator
    self.userDefaults = userDefaults
  }

  var hasMigrated: Bool {
    userDefaults.bool(forKey: Self.hasMigratedKey)
  }

  func resetMigrationFlag() {
    userDefaults.set(false, forKey: Self.hasMigratedKey)
  }

  @discardableResult
  func runIfNeeded() async -> DataMigrationSummary {
    guard !hasMigrated else {
      return DataMigrationSummary(source: "already migrated")
    }
    return await run()
  }

  @discardableResult
  func run() async -> DataMigrationSummary {
    var summary = DataMigrationSummary()

    if hasExistingChekiRecords() {
      summary.source = "data already imported; retrying CloudKit push confirmation"
    } else {
      guard let state = await loadLegacyState(into: &summary) else {
        summary.error = "No legacy data found (AsyncStorage empty and no iCloud fallback file)"
        return summary
      }
      do {
        try await importState(state, summary: &summary)
        try context.save()
      } catch {
        summary.error = "\(error)"
        return summary
      }
    }

    if await waitForInitialCloudKitExport() {
      userDefaults.set(true, forKey: Self.hasMigratedKey)
    } else {
      let pendingNote = "CloudKit export not yet confirmed; will retry on next launch."
      summary.error = summary.error.map { "\($0); \(pendingNote)" } ?? pendingNote
    }

    return summary
  }

  private func hasExistingChekiRecords() -> Bool {
    let request = CD_ChekiRecord.fetchRequest()
    request.fetchLimit = 1
    return ((try? context.count(for: request)) ?? 0) > 0
  }

  // MARK: - Loading

  private struct LegacyState {
    let lives: [LegacyChekiRecord]
    let setlists: [String: [LegacySetlistItem]]
    let userProfile: LegacyUserProfile?
  }

  private func loadLegacyState(into summary: inout DataMigrationSummary) async -> LegacyState? {
    if let raw = legacyStoreLoader.loadRawStoreJSON(), let data = raw.data(using: .utf8),
       let envelope = try? JSONDecoder().decode(ZustandEnvelope.self, from: data) {
      summary.source = "AsyncStorage"
      return LegacyState(lives: envelope.state.lives, setlists: envelope.state.setlists, userProfile: envelope.state.userProfile)
    }

    if let raw = await iCloudFallbackLoader.loadRawStoreJSON(), let data = raw.data(using: .utf8) {
      if let dataJSON = try? JSONDecoder().decode(ICloudDataJSON.self, from: data) {
        summary.source = "iCloud (tickemo_data.json)"
        return LegacyState(lives: dataJSON.lives, setlists: dataJSON.setlists, userProfile: dataJSON.userProfile)
      }
      if let kvsJSON = try? JSONDecoder().decode(ICloudKvsJSON.self, from: data) {
        summary.source = "iCloud (tickemo_kvs.json)"
        return LegacyState(lives: kvsJSON.lives, setlists: kvsJSON.setlists, userProfile: kvsJSON.userProfile)
      }
    }

    return nil
  }

  // MARK: - Importing

  private func importState(_ state: LegacyState, summary: inout DataMigrationSummary) async throws {
    for legacyRecord in state.lives {
      let record = fetchOrCreateChekiRecord(id: legacyRecord.id)
      apply(legacyRecord, to: record)
      await migrateImages(for: legacyRecord, into: record, summary: &summary)

      if let items = state.setlists[legacyRecord.id] {
        for legacyItem in items {
          let item = CD_SetlistItem(context: context)
          apply(legacyItem, to: item)
          item.record = record
          summary.setlistItemCount += 1
        }
      }
      summary.recordCount += 1
    }

    if let legacyProfile = state.userProfile {
      let profile = fetchOrCreateUserProfile()
      apply(legacyProfile, to: profile)
      await migrateAvatar(for: legacyProfile, into: profile)
      summary.profileImported = true
    }
  }

  private func fetchOrCreateChekiRecord(id: String) -> CD_ChekiRecord {
    guard let uuid = UUID(uuidString: id) else {
      let record = CD_ChekiRecord(context: context)
      record.id = UUID()
      return record
    }
    let request = CD_ChekiRecord.fetchRequest()
    request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
    request.fetchLimit = 1
    if let existing = try? context.fetch(request).first {
      return existing
    }
    let record = CD_ChekiRecord(context: context)
    record.id = uuid
    return record
  }

  private func fetchOrCreateUserProfile() -> CD_UserProfile {
    let request = CD_UserProfile.fetchRequest()
    request.fetchLimit = 1
    if let existing = try? context.fetch(request).first {
      return existing
    }
    let profile = CD_UserProfile(context: context)
    profile.id = UUID()
    return profile
  }

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
    item.id = UUID(uuidString: legacy.id) ?? UUID()
    item.orderIndex = Int32(legacy.orderIndex)

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

  private func apply(_ legacy: LegacyUserProfile, to profile: CD_UserProfile) {
    profile.name = legacy.name
    profile.username = legacy.username
    profile.joinedAt = legacy.joinedAt
    profile.plusStartedAt = legacy.plusStartedAt
  }

  // MARK: - Images

  private func migrateImages(for legacy: LegacyChekiRecord, into record: CD_ChekiRecord, summary: inout DataMigrationSummary) async {
    guard let imageUrls = legacy.imageUrls else { return }
    let assetIds = legacy.imageAssetIds ?? []

    for (index, path) in imageUrls.enumerated() {
      guard let data = await imageMigrator.resolveImageData(forRelativePath: path) else { continue }
      let image = CD_LiveImage(context: context)
      image.id = UUID()
      image.orderIndex = Int16(index)
      image.data = data
      image.legacyRelativePath = path
      image.assetIdentifier = index < assetIds.count ? assetIds[index] : nil
      image.record = record
      summary.imageCount += 1
    }
  }

  private func migrateAvatar(for legacy: LegacyUserProfile, into profile: CD_UserProfile) async {
    guard let avatarUri = legacy.avatarUri else { return }
    profile.avatarImageData = await imageMigrator.resolveImageData(forRelativePath: avatarUri)
  }

  // MARK: - CloudKit push confirmation

  /// Waits for `NSPersistentCloudKitContainer`'s initial export event to
  /// succeed, up to `timeout` seconds. Returns `false` on timeout (e.g. no
  /// iCloud account signed in) rather than blocking indefinitely; the
  /// `hasMigratedFromRNStore` flag is left unset in that case so the export
  /// is retried on the next launch without re-running the import.
  private func waitForInitialCloudKitExport(timeout: TimeInterval = 30) async -> Bool {
    await withCheckedContinuation { continuation in
      var didResume = false
      var observer: NSObjectProtocol?

      let finish: (Bool) -> Void = { success in
        guard !didResume else { return }
        didResume = true
        if let observer {
          NotificationCenter.default.removeObserver(observer)
        }
        continuation.resume(returning: success)
      }

      observer = NotificationCenter.default.addObserver(
        forName: NSPersistentCloudKitContainer.eventChangedNotification,
        object: container,
        queue: .main
      ) { notification in
        guard
          let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event,
          event.type == .export,
          event.endDate != nil
        else { return }
        finish(event.succeeded)
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        finish(false)
      }
    }
  }
}
