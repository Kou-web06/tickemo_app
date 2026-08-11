import Foundation
import UIKit

/// Ports the `@haptics_enabled` AsyncStorage preference and centralizes
/// every haptic trigger point behind it — ports RN's liberal
/// `expo-haptics` usage (a `Haptics.impactAsync`/`notificationAsync` call
/// at nearly every tap in `TicketDetail.tsx`, `FloatingTabBar.tsx`,
/// `LiveEditScreen.tsx`, etc.), all gated by the same persisted toggle.
@Observable
final class HapticsPreferenceService {
  static let shared = HapticsPreferenceService()

  private static let defaultsKey = "hapticsEnabled"

  private(set) var isEnabled: Bool

  private init() {
    if let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool {
      isEnabled = stored
    } else {
      isEnabled = true
    }
  }

  func setEnabled(_ value: Bool) {
    isEnabled = value
    UserDefaults.standard.set(value, forKey: Self.defaultsKey)
  }

  /// Light/medium/etc. tap feedback — ports the `Haptics.impactAsync`
  /// calls sprinkled across RN's tap handlers (close/edit/share buttons,
  /// tab-bar switches, play/pause toggles).
  func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    guard isEnabled else { return }
    UIImpactFeedbackGenerator(style: style).impactOccurred()
  }

  /// Success/warning/error feedback — ports `Haptics.notificationAsync`,
  /// used for outcomes like a completed save or a picked selection.
  func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    guard isEnabled else { return }
    UINotificationFeedbackGenerator().notificationOccurred(type)
  }
}
