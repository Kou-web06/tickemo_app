import CoreData
import UserNotifications
import Foundation
import os

/// Ports `utils/liveNotifications.ts`'s local live-reminder scheduling
/// (day-before / day-of / next-day-review notifications derived from each
/// record's date). RN's `expoPushToken` remote-push registration
/// (`hooks/usePushNotifications.ts`) is not ported: the token is fetched
/// but never sent to any backend, so nothing observable is lost by staying
/// purely local. Tapping a notification currently just opens the app —
/// deep-linking to the specific record would need app-wide navigation
/// state that doesn't exist yet (`ContentView`'s `TabView` has no
/// programmatic navigation path).
///
/// Follows `WidgetReloaderService`'s observer pattern: watches every
/// `NSManagedObjectContextDidSave` (not just the RecordFormView save path)
/// so a record added by CloudKit sync or the legacy migration importer also
/// gets scheduled, matching RN's `useEffect([records])` reschedule-on-any-
/// change behavior.
enum LiveNotificationService {
  private static let log = Logger(subsystem: "com.anonymous.Tickemo", category: "LiveNotifications")

  // iOS hard-caps pending local notification requests at 64 system-wide;
  // this isn't an arbitrary choice mirroring RN, it's the same ceiling RN's
  // own `MAX_SCHEDULED` was working around.
  private static let maxScheduled = 64

  private static let jstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return cal
  }()

  // MARK: - Authorization

  /// Safe to call repeatedly (at launch, and again whenever a settings
  /// toggle is switched on) — `UNUserNotificationCenter` only prompts once
  /// per install; subsequent calls with an already-decided status are
  /// no-ops.
  static func requestAuthorizationIfNeeded() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        if let error {
          log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }
        guard granted else { return }
        syncFromStore()
      }
    }
  }

  // MARK: - Store-driven scheduling

  @MainActor
  static func startObserving(
    container: NSPersistentContainer = PersistenceController.shared.container
  ) {
    guard observers.isEmpty else { return }

    observers.append(
      NotificationCenter.default.addObserver(
        forName: .NSManagedObjectContextDidSave,
        object: nil,
        queue: .main
      ) { [container] _ in
        MainActor.assumeIsolated { scheduleSync(container: container) }
      }
    )

    syncFromStore(container: container)
  }

  private static var observers: [NSObjectProtocol] = []
  private static var pendingSync: DispatchWorkItem?

  @MainActor
  private static func scheduleSync(container: NSPersistentContainer) {
    pendingSync?.cancel()
    let work = DispatchWorkItem { syncFromStore(container: container) }
    pendingSync = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  static func syncFromStore(
    container: NSPersistentContainer = PersistenceController.shared.container
  ) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        log.info("syncFromStore: notifications not authorized, skipping")
        return
      }
      let context = container.newBackgroundContext()
      context.perform {
        let request = CD_ChekiRecord.fetchRequest()
        do {
          let records = try context.fetch(request)
          schedule(for: records)
        } catch {
          log.error("syncFromStore: fetch failed — \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  // MARK: - Scheduling core

  private struct Target {
    let kind: LiveNotificationSettings.Kind
    let title: String
    let body: String
    let date: Date
  }

  /// Mirrors RN's `getScheduleTargets`: day-before at 19:00 JST, day-of 15
  /// minutes before showtime (`NextLiveCardData.instant`'s same
  /// endTime-then-startTime-then-18:00 fallback), next-day at 10:00 JST.
  private static func targets(for record: CD_ChekiRecord) -> [Target] {
    guard let day = DateFormatting.date(from: record.date) else { return [] }
    let liveName = (record.liveName?.isEmpty == false) ? record.liveName! : "ライブ"
    let onDayInstant = NextLiveCardData.instant(for: record) ?? day

    var result: [Target] = []

    if let dayBeforeBase = jstCalendar.date(byAdding: .day, value: -1, to: day),
       let dayBefore = jstCalendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayBeforeBase) {
      result.append(Target(
        kind: .beforeLive,
        title: "チケットとタオル、持った？",
        body: "いよいよ明日は\(liveName)！忘れ物ない？もう一回チェックしてね！",
        date: dayBefore
      ))
    }

    result.append(Target(
      kind: .onDay,
      title: "そろそろスマホしまっておいて🤫",
      body: "\(liveName)まもなく始まります！行ってらっしゃい！",
      date: onDayInstant.addingTimeInterval(-15 * 60)
    ))

    if let nextDayBase = jstCalendar.date(byAdding: .day, value: 1, to: day),
       let nextDay = jstCalendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDayBase) {
      result.append(Target(
        kind: .nextDayReview,
        title: "あのライブどうだった？",
        body: "\(liveName)の思い出、チケットに保存しましたか？",
        date: nextDay
      ))
    }

    return result
  }

  /// Cancels and fully re-derives the pending set from scratch every time.
  /// RN has to filter its cancel-and-reschedule by notification type
  /// because it shares the local-notification namespace with legacy
  /// timecapsule/yearly-report types; this app has no other local
  /// notification use, so `removeAllPendingNotificationRequests` is safe
  /// and much simpler than diffing.
  private static func schedule(for records: [CD_ChekiRecord]) {
    let center = UNUserNotificationCenter.current()
    let settings = LiveNotificationSettings.shared
    let now = Date()

    let allTargets = records
      .flatMap { record in targets(for: record).map { (record, $0) } }
      .filter { $0.1.date > now }
      .filter { settings.isEnabled($0.1.kind) }
      .sorted { $0.1.date < $1.1.date }
      .prefix(maxScheduled)

    center.removeAllPendingNotificationRequests()

    for (record, target) in allTargets {
      let content = UNMutableNotificationContent()
      content.title = target.title
      content.body = target.body
      content.sound = .default

      // `dateComponents(_:from:)` on a JST-configured `Calendar` bakes that
      // calendar/timezone into the returned components, so the trigger
      // fires at the intended JST wall-clock time regardless of the
      // device's own timezone.
      let components = jstCalendar.dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: target.date
      )
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let identifier = "\(record.id?.uuidString ?? UUID().uuidString)_\(target.kind.rawValue)"
      center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    log.info("schedule: \(allTargets.count) notifications scheduled")
  }
}
