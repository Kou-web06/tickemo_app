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

  static func isWithinEarlyWindow() -> Bool {
    let defaults = UserDefaults.standard
    let firstLaunch: Date
    if let existing = defaults.object(forKey: firstLaunchKey) as? Date {
      firstLaunch = existing
    } else {
      firstLaunch = Date()
      defaults.set(firstLaunch, forKey: firstLaunchKey)
    }
    return Date().timeIntervalSince(firstLaunch) < windowSeconds
  }
}
