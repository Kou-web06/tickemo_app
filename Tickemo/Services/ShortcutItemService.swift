import UIKit

/// Tracks home-screen "Quick Action" (long-press the app icon) taps and
/// routes them into the SwiftUI layer, which has no direct hook for
/// `UIApplicationShortcutItem` — only the UIKit scene delegate (see
/// `TickemoSceneDelegate` in `AppDelegate.swift`) receives it, for both cold
/// launch and warm/background taps.
@Observable
final class ShortcutItemService {
  static let shared = ShortcutItemService()

  static let feedbackShortcutType = "com.anonymous.Tickemo.feedback"

  private(set) var pendingFeedbackRequest = false

  private init() {}

  func handle(_ shortcutItem: UIApplicationShortcutItem) {
    guard shortcutItem.type == Self.feedbackShortcutType else { return }
    pendingFeedbackRequest = true
  }

  func clearPendingFeedbackRequest() {
    pendingFeedbackRequest = false
  }
}
