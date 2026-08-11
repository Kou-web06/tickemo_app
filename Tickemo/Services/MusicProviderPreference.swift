import Foundation
import UIKit

/// Ports the `@music_provider` AsyncStorage preference
/// (`screens/SettingsScreen.tsx`). `RecordDetailView`'s setlist tap-to-play
/// fallback and `NextLiveCardView`'s "Listen" button both open directly via
/// `open(query:appleMusicURL:)` using this saved choice — matching RN's
/// original single-persisted-choice behavior — rather than asking which
/// provider on every tap.
enum MusicProviderPreference: String, Equatable {
  case spotify
  case apple

  /// Opens `query` as a search (or, for Apple Music when a direct URL is
  /// already known — e.g. `TodaySong.appleMusicUrl` — that URL) in this
  /// provider. No-op if the query is empty and no direct URL was given.
  func open(query: String, appleMusicURL: String? = nil) {
    switch self {
    case .spotify:
      Self.openSpotify(query: query)
    case .apple:
      Self.openAppleMusic(query: query, directURL: appleMusicURL)
    }
  }

  private static func openSpotify(query: String) {
    guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
    if let deepLink = URL(string: "spotify:search:\(encoded)"), UIApplication.shared.canOpenURL(deepLink) {
      UIApplication.shared.open(deepLink)
    } else if let webURL = URL(string: "https://open.spotify.com/search/\(encoded)") {
      UIApplication.shared.open(webURL)
    }
  }

  private static func openAppleMusic(query: String, directURL: String?) {
    if let directURL, let url = URL(string: directURL) {
      UIApplication.shared.open(url)
      return
    }
    guard !query.isEmpty,
          let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://music.apple.com/search?term=\(encoded)")
    else { return }
    UIApplication.shared.open(url)
  }
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
