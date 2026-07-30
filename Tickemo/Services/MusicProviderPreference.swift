import Foundation

/// Ports the `@music_provider` AsyncStorage preference
/// (`screens/SettingsScreen.tsx`). Purely a persisted Settings-row
/// preference — `RecordDetailView`'s own tap-to-play fallback keeps its
/// existing "always ask which provider" dialog (an intentional, documented
/// improvement over RN's persisted-single-choice behavior), so nothing
/// else in the app currently reads this value.
enum MusicProviderPreference: String, Equatable {
  case spotify
  case apple
}

enum MusicProviderPreferenceStore {
  private static let defaultsKey = "musicProviderPreference"

  static func load() -> MusicProviderPreference {
    guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
          let value = MusicProviderPreference(rawValue: raw)
    else {
      return .spotify
    }
    return value
  }

  static func save(_ value: MusicProviderPreference) {
    UserDefaults.standard.set(value.rawValue, forKey: defaultsKey)
  }
}
