import Foundation

/// Ports lib/earlyOffer.ts's 24-hour post-first-launch discount window, but
/// deliberately does NOT read the RN app's AsyncStorage `@has_launched`
/// value — every real migrated user's original first launch was long ago,
/// so that value would already read as expired in effectively every real
/// case, and this is a display-only pricing promo, not billing state worth
/// the extra AsyncStorage-reading complexity. A fresh, native-only
/// UserDefaults timestamp gives genuinely new native installs their own
/// correct 24h window, and is behaviorally indistinguishable from reading
/// an already-expired legacy value for everyone else.
enum EarlyOfferService {
  private static let firstLaunchKey = "nativeFirstLaunchDate"
  private static let windowSeconds: TimeInterval = 24 * 60 * 60

  private static func firstLaunchDate() -> Date {
    let defaults = UserDefaults.standard
    if let existing = defaults.object(forKey: firstLaunchKey) as? Date {
      return existing
    }
    let firstLaunch = Date()
    defaults.set(firstLaunch, forKey: firstLaunchKey)
    return firstLaunch
  }

  static func isWithinEarlyWindow() -> Bool {
    Date().timeIntervalSince(firstLaunchDate()) < windowSeconds
  }

  /// Time left in the window, clamped to 0 once expired — drives
  /// PaywallBannerView's countdown, ports `getEarlyWindowRemainingMs`.
  static func remainingSeconds() -> TimeInterval {
    let elapsed = Date().timeIntervalSince(firstLaunchDate())
    return max(windowSeconds - elapsed, 0)
  }

  /// "HH:MM:SS", zero-padded — ports `formatMsToHms`. Pure given the
  /// input, so it's the unit-testable half of the countdown.
  static func format(remaining: TimeInterval) -> String {
    let total = max(0, Int(remaining.rounded(.down)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
  }
}
