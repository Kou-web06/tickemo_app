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
  }

  private static let beforeLiveKey = "notif_beforeLive"
  private static let onDayKey = "notif_onDay"
  private static let nextDayReviewKey = "notif_nextDayReview"

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
    }
  }

  func setEnabled(_ value: Bool, for kind: Kind) {
    let defaults = UserDefaults.standard
    switch kind {
    case .beforeLive: defaults.set(value, forKey: Self.beforeLiveKey)
    case .onDay: defaults.set(value, forKey: Self.onDayKey)
    case .nextDayReview: defaults.set(value, forKey: Self.nextDayReviewKey)
    }
    LiveNotificationService.syncFromStore()
  }
}
