import Foundation

/// Ports `utils/appReview.ts`'s save-count trigger only — every other save
/// (RN's `REVIEW_TRIGGER_COUNT`) calls the platform review prompt. RN's own
/// two-step star-rating screen (routing 1-2 star raters away from the App
/// Store) is deliberately not ported: the user asked for the plain
/// `requestReview()` call on the same cadence, nothing custom.
enum AppReviewTracker {
  private static let saveCountKey = "reviewPromptSaveCount"
  private static let triggerEvery = 2

  /// Call once per ticket save (create or update). Returns `true` on every
  /// `triggerEvery`th call. No independent cap beyond that — StoreKit's own
  /// `requestReview()` already throttles how often the prompt can actually
  /// appear (at most a few times per year), so there's nothing left for
  /// this app to police.
  static func shouldPromptAfterSave() -> Bool {
    let defaults = UserDefaults.standard
    let next = defaults.integer(forKey: saveCountKey) + 1
    defaults.set(next, forKey: saveCountKey)
    return next % triggerEvery == 0
  }
}
