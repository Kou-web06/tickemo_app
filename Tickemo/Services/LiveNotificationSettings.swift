import Foundation

/// Persisted toggles for `LiveNotificationService`'s local live-reminder
/// notifications — ports the `beforeLive`/`onDay`/`nextDayReview` fields of
/// RN's `NotificationSettingsState` (`utils/liveNotifications.ts`). RN's
/// fourth field, `campaigns`, is not ported: RN's own `getScheduleTargets`
/// never emits a target for it, so the toggle is dead in RN too.
final class LiveNotificationSettings {
  static let shared = LiveNotificationSettings()

  enum Kind: String {
    case beforeLive, onDay, nextDayReview
    // チケットの予定（TicketSchedule）の通知。Plus 限定
    case seatAnnounce, ticketApply, paymentDue

    init(_ scheduleKind: TicketScheduleKind) {
      switch scheduleKind {
      case .seatAnnounce: self = .seatAnnounce
      case .ticketApply: self = .ticketApply
      case .paymentDue: self = .paymentDue
      }
    }

    var isPlusOnly: Bool {
      switch self {
      case .beforeLive, .onDay, .nextDayReview: return false
      case .seatAnnounce, .ticketApply, .paymentDue: return true
      }
    }
  }

  private static let beforeLiveKey = "notif_beforeLive"
  private static let onDayKey = "notif_onDay"
  private static let nextDayReviewKey = "notif_nextDayReview"

  private static func key(for kind: Kind) -> String {
    "notif_\(kind.rawValue)"
  }

  private init() {}

  func isEnabled(_ kind: Kind) -> Bool {
    let defaults = UserDefaults.standard
    switch kind {
    case .beforeLive:
      return defaults.object(forKey: Self.beforeLiveKey) as? Bool ?? true
    case .onDay:
      return defaults.object(forKey: Self.onDayKey) as? Bool ?? true
    case .nextDayReview:
      return defaults.object(forKey: Self.nextDayReviewKey) as? Bool ?? false
    case .seatAnnounce, .ticketApply, .paymentDue:
      // 自分で日時を入力した予定なので、既定で通知する
      return defaults.object(forKey: Self.key(for: kind)) as? Bool ?? true
    }
  }

  func setEnabled(_ value: Bool, for kind: Kind) {
    let defaults = UserDefaults.standard
    switch kind {
    case .beforeLive: defaults.set(value, forKey: Self.beforeLiveKey)
    case .onDay: defaults.set(value, forKey: Self.onDayKey)
    case .nextDayReview: defaults.set(value, forKey: Self.nextDayReviewKey)
    case .seatAnnounce, .ticketApply, .paymentDue: defaults.set(value, forKey: Self.key(for: kind))
    }
    LiveNotificationService.syncFromStore()
  }
}
