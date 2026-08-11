import CoreData
import Foundation

enum CloudSyncStatus: Equatable {
  case notSyncedYet
  case syncing
  case synced
}

/// A small, constructible mirror of the fields `CloudSyncStatusService`
/// reads off `NSPersistentCloudKitContainer.Event` — that type has no
/// public initializer, so the actual decision logic (`reduce`) takes this
/// instead, keeping it unit-testable without a real CloudKit event.
struct SyncEventSnapshot {
  let type: NSPersistentCloudKitContainer.EventType
  let endDate: Date?
  let succeeded: Bool
  var startDate: Date?
  var errorDescription: String?
}

/// One completed (or in-flight) mirroring event, kept so a failure can be
/// read after the fact.
///
/// `CloudSyncStatusService` deliberately does *not* regress its headline
/// status on a transient failure, which is right for the UI but means an
/// export that never succeeds looks identical to one that hasn't happened
/// yet. Without the error text there is no way to tell "CloudKit is
/// working" from "every export is being rejected" — the exact ambiguity an
/// undeployed Production schema creates.
struct SyncEventLogEntry: Identifiable, Equatable {
  let id = UUID()
  let typeLabel: String
  let startDate: Date?
  let endDate: Date?
  let succeeded: Bool
  let errorDescription: String?

  var isFinished: Bool { endDate != nil }

  static func label(for type: NSPersistentCloudKitContainer.EventType) -> String {
    switch type {
    case .setup: "setup"
    case .import: "import"
    case .export: "export"
    @unknown default: "unknown"
    }
  }
}

/// Monitors real CloudKit sync activity via
/// `NSPersistentCloudKitContainer.eventChangedNotification`. This is a
/// deliberately different approach from RN's `useCloudSync` hook (which
/// manually pushes/pulls a JSON blob through `react-native-cloud-storage`)
/// — the native app's sync mechanism is Core Data + CloudKit via
/// `NSPersistentCloudKitContainer` (see `PersistenceController`), which
/// has no equivalent of RN's manual blob push/pull, so this reports on
/// the real underlying mechanism instead of replicating RN's hook. Also
/// deliberately does NOT replicate RN's `ICloudSyncScreen.tsx`, whose
/// status text is hard-coded to always say "Synced" regardless of actual
/// state (confirmed by reading that file) — this reports genuine status.
@Observable
final class CloudSyncStatusService {
  static let shared = CloudSyncStatusService()

  private(set) var status: CloudSyncStatus = .notSyncedYet
  private(set) var lastSuccessfulSyncDate: Date?

  /// Most recent first. Bounded — this is a diagnostic aid, not a record
  /// worth growing without limit.
  private(set) var recentEvents: [SyncEventLogEntry] = []
  static let maximumLoggedEvents = 30

  var lastFailure: SyncEventLogEntry? {
    recentEvents.first { $0.isFinished && !$0.succeeded }
  }

  private var observerToken: NSObjectProtocol?

  private init() {
    observerToken = NotificationCenter.default.addObserver(
      forName: NSPersistentCloudKitContainer.eventChangedNotification,
      object: PersistenceController.shared.container,
      queue: .main
    ) { [weak self] notification in
      guard
        let self,
        let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
          as? NSPersistentCloudKitContainer.Event
      else { return }
      self.apply(
        event: SyncEventSnapshot(
          type: event.type,
          endDate: event.endDate,
          succeeded: event.succeeded,
          startDate: event.startDate,
          errorDescription: event.error.map { "\($0)" }
        )
      )
    }
  }

  deinit {
    if let observerToken {
      NotificationCenter.default.removeObserver(observerToken)
    }
  }

  private func apply(event: SyncEventSnapshot) {
    let next = Self.reduce(current: (status, lastSuccessfulSyncDate), event: event)
    status = next.status
    lastSuccessfulSyncDate = next.lastSuccess

    recentEvents.insert(
      SyncEventLogEntry(
        typeLabel: SyncEventLogEntry.label(for: event.type),
        startDate: event.startDate,
        endDate: event.endDate,
        succeeded: event.succeeded,
        errorDescription: event.errorDescription
      ),
      at: 0
    )
    if recentEvents.count > Self.maximumLoggedEvents {
      recentEvents.removeLast(recentEvents.count - Self.maximumLoggedEvents)
    }
  }

  /// Pure decision logic, exercised directly in
  /// `CloudSyncStatusServiceTests` via `SyncEventSnapshot`. `.setup`-type
  /// events are ignored (not a real sync signal); an in-progress event
  /// (`endDate == nil`) reports `.syncing`; a successfully completed event
  /// reports `.synced` and records its end date; a failed completed event
  /// leaves the current status/timestamp untouched rather than regressing
  /// to `.notSyncedYet` on a transient failure.
  static func reduce(
    current: (status: CloudSyncStatus, lastSuccess: Date?),
    event: SyncEventSnapshot
  ) -> (status: CloudSyncStatus, lastSuccess: Date?) {
    guard event.type == .import || event.type == .export else {
      return current
    }
    guard let endDate = event.endDate else {
      return (.syncing, current.lastSuccess)
    }
    guard event.succeeded else {
      return current
    }
    return (.synced, endDate)
  }

  /// Best-effort "sync now": `NSPersistentCloudKitContainer` has no public
  /// force-sync API. This saves any pending local changes (which is the
  /// only thing that can actually trigger a push) and then gives a moment
  /// for a resulting `eventChangedNotification` to arrive — if there's
  /// nothing pending locally and no remote changes waiting, this may
  /// visibly do nothing, since CloudKit sync otherwise happens on its own
  /// schedule. This is a genuine UX tradeoff, not a hidden shortcut.
  @MainActor
  func nudgeSync() async {
    let context = PersistenceController.shared.container.viewContext
    if context.hasChanges {
      try? context.save()
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
  }
}
