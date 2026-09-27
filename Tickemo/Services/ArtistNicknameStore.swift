import Foundation
import Observation

/// あだ名の対応表の保存先。テストで実際の iCloud を触らずに済むよう分離。
protocol ArtistNicknameBackingStore: AnyObject {
  func loadNicknames() -> [String: String]
  func saveNicknames(_ nicknames: [String: String])
}

/// Core Data のスキーマ（= CloudKit のスキーマ）を変えずに端末間で同期
/// させるため、`LegacyMigrationClaim` と同じ `NSUbiquitousKeyValueStore`
/// に保存する。iCloud にサインインしていない端末でも確実に残るよう
/// `UserDefaults` にもミラーし、読み込みは iCloud 側を優先する。
final class ICloudArtistNicknameBackingStore: ArtistNicknameBackingStore {
  static let storageKey = "artistNicknames"

  private let ubiquitousStore: NSUbiquitousKeyValueStore
  private let defaults: UserDefaults

  init(ubiquitousStore: NSUbiquitousKeyValueStore = .default, defaults: UserDefaults = .standard) {
    self.ubiquitousStore = ubiquitousStore
    self.defaults = defaults
  }

  func loadNicknames() -> [String: String] {
    if let synced = ubiquitousStore.dictionary(forKey: Self.storageKey) as? [String: String] {
      return synced
    }
    return defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
  }

  func saveNicknames(_ nicknames: [String: String]) {
    ubiquitousStore.set(nicknames, forKey: Self.storageKey)
    ubiquitousStore.synchronize()
    defaults.set(nicknames, forKey: Self.storageKey)
  }
}

/// `ArtistNicknameStoreTests` 用のインメモリ実装。
final class InMemoryArtistNicknameBackingStore: ArtistNicknameBackingStore {
  private(set) var stored: [String: String]

  init(initial: [String: String] = [:]) {
    stored = initial
  }

  func loadNicknames() -> [String: String] { stored }

  func saveNicknames(_ nicknames: [String: String]) {
    stored = nicknames
  }
}

/// アーティストのあだ名（表示名）。ロジックは `ArtistNicknames`、ここは
/// 保存と画面への変更通知だけを受け持つ。`@Observable` なので、body の中で
/// `displayName(for:)` を呼んだ View はあだ名の変更で自動的に再描画される。
@Observable
final class ArtistNicknameStore {
  static let shared = ArtistNicknameStore()

  private(set) var nicknames: [String: String]

  @ObservationIgnored private let backing: ArtistNicknameBackingStore
  @ObservationIgnored private var externalChangeObserver: NSObjectProtocol?

  init(backing: ArtistNicknameBackingStore = ICloudArtistNicknameBackingStore()) {
    self.backing = backing
    nicknames = backing.loadNicknames()
    // 他の端末で付けたあだ名を反映する
    externalChangeObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reload()
    }
  }

  deinit {
    if let externalChangeObserver {
      NotificationCenter.default.removeObserver(externalChangeObserver)
    }
  }

  func reload() {
    nicknames = backing.loadNicknames()
  }

  func nickname(for artistName: String) -> String? {
    ArtistNicknames.nickname(for: artistName, in: nicknames)
  }

  func displayName(for artistName: String) -> String {
    ArtistNicknames.displayName(for: artistName, in: nicknames)
  }

  func setNickname(_ nickname: String?, for artistName: String) {
    let updated = ArtistNicknames.updating(nicknames, artistName: artistName, nickname: nickname)
    guard updated != nicknames else { return }
    nicknames = updated
    backing.saveNicknames(updated)
  }
}
