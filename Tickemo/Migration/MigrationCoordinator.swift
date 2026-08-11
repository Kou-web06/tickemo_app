import CoreData
import Foundation

/// Decides whether the legacy import should run on this launch, runs it,
/// and keeps duplicate sweeps scheduled afterwards.
///
/// The ordering below is the whole safety argument, so it's worth stating
/// plainly. Ranked by how bad the outcome is, the failure modes are:
///
/// 1. **Losing data** — the user updates and their tickets are gone. Worst
///    case by far, and the only one that isn't self-correcting.
/// 2. **Duplicating data** — annoying and visible, but recoverable, because
///    everything imported keeps its legacy id and `DuplicateRecordSweeper`
///    can collapse it.
/// 3. **Showing nothing for a few seconds** — merely a delay.
///
/// So this waits (3) to avoid (2), and accepts (2) rather than risk (1):
/// if a claim says another device already migrated but no data actually
/// arrives, it imports anyway rather than leave the user staring at an
/// empty app with their records sitting in the ubiquity container.
@MainActor
@Observable
final class MigrationCoordinator {
  static let shared = MigrationCoordinator()

  enum Phase: Equatable {
    case idle
    /// Cheap local checks; too fast to be worth showing the user.
    case preparing
    /// Giving CloudKit a chance to deliver data another device already
    /// migrated, so we don't import a second copy.
    case waitingForCloud
    case importing
    case done
  }

  /// How long to wait for CloudKit before importing. The longer wait is
  /// used when a claim says another device already migrated — in that case
  /// the data really is expected to arrive, so it's worth being patient.
  private static let unclaimedCloudWait: TimeInterval = 8
  private static let claimedCloudWait: TimeInterval = 30

  /// How long after the claim to keep checking the legacy store for
  /// tickets added on a device that hasn't updated yet. Comfortably longer
  /// than a phased App Store rollout; after this the legacy blob is stale
  /// enough that the manual re-import in Settings is the right tool.
  private static let lateArrivalWindow: TimeInterval = 60 * 24 * 60 * 60

  private(set) var phase: Phase = .idle
  private(set) var lastSummary: DataMigrationSummary?
  private(set) var lastSweep: DuplicateSweepSummary?

  /// Whether to show migration UI. Only true for the phases that can
  /// actually take a noticeable amount of time, so a normal launch never
  /// flashes an overlay.
  var isBusy: Bool {
    phase == .waitingForCloud || phase == .importing
  }

  private let container: NSPersistentCloudKitContainer
  private let importer: DataMigrationImporter
  private let claim: LegacyMigrationClaim
  private let sweeper: DuplicateRecordSweeper
  private let userDefaults: UserDefaults
  private let cloudKitAvailable: () -> Bool

  private var hasRun = false
  private var sweepScheduler: DuplicateSweepScheduler?

  init(
    container: NSPersistentCloudKitContainer = PersistenceController.shared.container,
    importer: DataMigrationImporter = DataMigrationImporter(),
    claim: LegacyMigrationClaim = LegacyMigrationClaim(),
    sweeper: DuplicateRecordSweeper = DuplicateRecordSweeper(),
    userDefaults: UserDefaults = .standard,
    cloudKitAvailable: @escaping () -> Bool = { FileManager.default.ubiquityIdentityToken != nil }
  ) {
    self.container = container
    self.importer = importer
    self.claim = claim
    self.sweeper = sweeper
    self.userDefaults = userDefaults
    self.cloudKitAvailable = cloudKitAvailable
  }

  // MARK: - Launch entry point

  func runIfNeeded() async {
    guard !hasRun else { return }
    hasRun = true

    phase = .preparing
    defer {
      phase = .done
      startSweepScheduler()
    }

    // A previous launch already finished. `hasMigratedFromRNStore` is
    // honoured too so users who migrated on a build that predates the
    // iCloud claim aren't put through it again.
    let alreadyMigratedLocally =
      claim.localClaim != nil || userDefaults.bool(forKey: DataMigrationImporter.hasMigratedKey)
    if alreadyMigratedLocally {
      scheduleLateArrivalReconcile()
      return
    }

    // Nothing on this device even hints at a legacy install. Deliberately
    // does not write a claim: the ubiquity file may simply not have been
    // listed yet, and a later launch should be free to find it.
    guard await runOffMain({ [importer] in importer.hasAnyLegacySignal() }) else {
      return
    }

    // Data is already here — either the user has been using the native app
    // or CloudKit got there first. Importing over it is unnecessary, and
    // the legacy blob is the older copy.
    if await storeHasData() {
      claimMigrated(source: "existing store", recordCount: 0)
      return
    }

    let existingClaim = await runOffMain({ [claim] in claim.currentClaim() })

    phase = .waitingForCloud
    let waited = existingClaim == nil ? Self.unclaimedCloudWait : Self.claimedCloudWait
    if await waitForCloudData(timeout: waited) {
      claimMigrated(source: "CloudKit", recordCount: 0)
      // The import was skipped because CloudKit already had the data —
      // but the legacy store on *this* device may hold tickets added
      // after the other device migrated, which nothing else would pick up.
      if let claimedAt = existingClaim?.claimedAt {
        await reconcileLateArrivals(since: claimedAt)
      }
      return
    }

    phase = .importing
    let summary = await importer.run()
    lastSummary = summary

    // Claim only on a real import. "Nothing found" stays unclaimed so a
    // later launch can retry once the ubiquity file has downloaded, and an
    // error stays unclaimed so the next launch retries too — safe, because
    // the import is an upsert.
    if summary.error == nil, summary.source != "none" {
      claimMigrated(source: summary.source, recordCount: summary.recordCount)
    }

    lastSweep = try? await sweeper.sweep()
  }

  // MARK: - Late arrivals

  /// Fired off without blocking the UI: by this point the store already has
  /// the user's data, so anything found here is an addition, not the
  /// difference between a usable app and an empty one.
  private func scheduleLateArrivalReconcile() {
    guard let claimedAt = claim.localClaim?.claimedAt else {
      // Migrated on a build that predates the claim, so there's no
      // trustworthy cutoff. Settings' manual re-import covers this user.
      return
    }
    guard Date() < claimedAt.addingTimeInterval(Self.lateArrivalWindow) else { return }

    Task { [weak self] in
      await self?.reconcileLateArrivals(since: claimedAt)
    }
  }

  private func reconcileLateArrivals(since cutoff: Date) async {
    guard await runOffMain({ [importer] in importer.hasAnyLegacySignal() }) else { return }

    let summary = await importer.run(scope: .createdAfter(cutoff))
    guard summary.importedAnything else { return }

    lastSummary = summary
    lastSweep = try? await sweeper.sweep()
  }

  // MARK: - Manual re-run

  /// Support/debug affordance. Safe to invoke at any time: the import is an
  /// upsert that never overwrites existing rows, so the worst case is that
  /// it finds nothing new to do.
  @discardableResult
  func runManualImport() async -> DataMigrationSummary {
    phase = .importing
    defer { phase = .done }

    let summary = await importer.run()
    lastSummary = summary
    if summary.error == nil, summary.source != "none" {
      claimMigrated(source: summary.source, recordCount: summary.recordCount)
    }
    lastSweep = try? await sweeper.sweep()
    return summary
  }

  @discardableResult
  func runManualSweep() async -> DuplicateSweepSummary? {
    let result = try? await sweeper.sweep()
    lastSweep = result
    return result
  }

  // MARK: - Helpers

  private func claimMigrated(source: String, recordCount: Int) {
    claim.claim(source: source, recordCount: recordCount)
    userDefaults.set(true, forKey: DataMigrationImporter.hasMigratedKey)
  }

  private func storeHasData() async -> Bool {
    let context = container.newBackgroundContext()
    return await context.perform {
      let recordRequest = CD_ChekiRecord.fetchRequest()
      recordRequest.fetchLimit = 1
      if ((try? context.count(for: recordRequest)) ?? 0) > 0 { return true }

      // A user who only ever completed onboarding has a profile and no
      // tickets; that still counts as "already has data".
      let profileRequest = CD_UserProfile.fetchRequest()
      profileRequest.fetchLimit = 1
      return ((try? context.count(for: profileRequest)) ?? 0) > 0
    }
  }

  /// Resolves as soon as records appear locally, or when the timeout
  /// elapses. Returns immediately when there's no iCloud account, since
  /// nothing can arrive in that case and making the user wait would be
  /// pure delay.
  private func waitForCloudData(timeout: TimeInterval) async -> Bool {
    guard cloudKitAvailable() else { return false }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await storeHasData() { return true }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    return await storeHasData()
  }

  private func startSweepScheduler() {
    guard sweepScheduler == nil else { return }
    sweepScheduler = DuplicateSweepScheduler(container: container) { [weak self] in
      guard let self else { return nil }
      let result = try? await self.sweeper.sweep()
      self.lastSweep = result
      return result
    }
  }

  /// `hasAnyLegacySignal` and the claim's iCloud read both touch the
  /// ubiquity container, which can block; keep them off the main actor.
  private func runOffMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .userInitiated) { work() }.value
  }
}

/// Re-runs the duplicate sweep when CloudKit finishes importing, which is
/// the only moment a duplicate from another device can become visible.
///
/// Bounded on purpose: sweeping walks every record, so it backs off after a
/// few consecutive clean passes rather than running for the life of the
/// process. A relaunch re-arms it, which is enough — duplicates are a
/// transient migration-window artifact, not an ongoing condition.
@MainActor
final class DuplicateSweepScheduler {
  private static let minimumInterval: TimeInterval = 30
  private static let cleanSweepsBeforeStopping = 3

  private let onSweep: () async -> DuplicateSweepSummary?
  private var observer: NSObjectProtocol?
  private var lastSweepAt: Date?
  private var cleanSweeps = 0
  private var isSweeping = false

  init(container: NSPersistentCloudKitContainer, onSweep: @escaping () async -> DuplicateSweepSummary?) {
    self.onSweep = onSweep
    observer = NotificationCenter.default.addObserver(
      forName: NSPersistentCloudKitContainer.eventChangedNotification,
      object: container,
      queue: .main
    ) { [weak self] notification in
      guard
        let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
          as? NSPersistentCloudKitContainer.Event,
        event.type == .import,
        event.endDate != nil,
        event.succeeded
      else { return }
      Task { @MainActor [weak self] in await self?.sweepIfDue() }
    }
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func sweepIfDue() async {
    guard !isSweeping, cleanSweeps < Self.cleanSweepsBeforeStopping else { return }
    if let lastSweepAt, Date().timeIntervalSince(lastSweepAt) < Self.minimumInterval { return }

    isSweeping = true
    defer { isSweeping = false }

    let startedAt = Date()
    let result = await onSweep()
    lastSweepAt = startedAt

    // Only a genuinely quiet pass counts towards backing off — while
    // duplicates are still being collapsed, keep watching.
    if result?.didChangeAnything == true {
      cleanSweeps = 0
    } else {
      cleanSweeps += 1
    }
  }
}
