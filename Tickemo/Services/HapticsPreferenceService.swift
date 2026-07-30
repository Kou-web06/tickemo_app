import Foundation

/// Ports the `@haptics_enabled` AsyncStorage preference. Gates the
/// selection-success haptics fired by MusicProviderPickerView/
/// LanguagePickerView — the only two call sites in this codebase that
/// currently trigger any haptic feedback at all.
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
}
