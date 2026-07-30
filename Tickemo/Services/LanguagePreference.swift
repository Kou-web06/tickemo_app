import Foundation

/// Ports the `@language_preference` AsyncStorage preference
/// (`screens/SettingsScreen.tsx`). Settings-row-only per the approved
/// scope: this persists a choice but no other native screen reads it —
/// there's no app-wide i18n infrastructure yet, so selecting 日本語/English
/// here has no visible effect elsewhere in the app.
enum LanguagePreference: String, Equatable {
  case system
  case ja
  case en
}

enum LanguagePreferenceStore {
  private static let defaultsKey = "languagePreference"

  static func load() -> LanguagePreference {
    guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
          let value = LanguagePreference(rawValue: raw)
    else {
      return .system
    }
    return value
  }

  static func save(_ value: LanguagePreference) {
    UserDefaults.standard.set(value.rawValue, forKey: defaultsKey)
  }
}
