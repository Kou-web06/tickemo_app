import Foundation
import MusicKit

enum ApplePlaylistExportError: LocalizedError {
  case notAuthorized
  case noSubscription
  case noExportableSongs
  case catalogLookupFailed

  var errorDescription: String? {
    switch self {
    case .notAuthorized:
      "Apple Musicへのアクセスが許可されていません。設定アプリの「Tickemo」から許可してください。"
    case .noSubscription:
      "Apple Musicのプレイリスト作成には、Apple Musicのサブスクリプションが必要です。曲リストのコピー／共有はサブスクリプションなしでも使えます。"
    case .noExportableSongs:
      "Apple Musicに登録されている曲がありません。曲名検索から追加した曲だけがプレイリストに入れられます。"
    case .catalogLookupFailed:
      "Apple Musicで曲を見つけられませんでした。時間をおいて試してください。"
    }
  }
}

/// セットリストを Apple Music のプレイリストとしてユーザーのライブラリに
/// 作成する。
///
/// 曲を検索から追加した時点で Apple Music のカタログ ID（`songId`）を
/// 持っているので、ここでの照合は ID 引きだけで済む — 曲名でのあいまい
/// 検索は挟まない。逆に言うと、OCR で読み取ったまま候補に当たらなかった
/// 曲は `songId` を持たないので、プレイリストには入れられない（呼び出し
/// 側で除外件数を伝える）。
///
/// カバー曲について: `songId` は曲追加時に選んだ音源＝原曲を指すので、
/// プレイリストに入るのは原曲の音源になる。詳細画面の再生ボタンと同じ
/// 挙動で、「歌った人」の音源に差し替える機能ではない。
enum ApplePlaylistExporter {
  /// `MusicCatalogResourceRequest` の 1 リクエストあたりの ID 数上限に
  /// 余裕を持たせた分割単位。長いセトリでも取りこぼさないよう分割して
  /// 引き、結果は元の曲順に並べ直す（レスポンスの順序は保証されない）。
  private static let lookupChunkSize = 25

  /// 作成したプレイリストに入った曲数を返す。
  @discardableResult
  static func createPlaylist(named name: String, songIds: [String]) async throws -> Int {
    let ids = songIds
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !ids.isEmpty else { throw ApplePlaylistExportError.noExportableSongs }

    guard await MusicAuthorization.request() == .authorized else {
      throw ApplePlaylistExportError.notAuthorized
    }

    let subscription = try? await MusicSubscription.current
    guard subscription?.canPlayCatalogContent == true else {
      throw ApplePlaylistExportError.noSubscription
    }

    let songs = try await catalogSongs(for: ids)
    guard !songs.isEmpty else { throw ApplePlaylistExportError.catalogLookupFailed }

    _ = try await MusicLibrary.shared.createPlaylist(name: name, items: songs)
    return songs.count
  }

  private static func catalogSongs(for ids: [String]) async throws -> [Song] {
    var byID: [String: Song] = [:]

    for chunk in stride(from: 0, to: ids.count, by: lookupChunkSize).map({ start in
      Array(ids[start..<min(start + lookupChunkSize, ids.count)])
    }) {
      var request = MusicCatalogResourceRequest<Song>(
        matching: \.id,
        memberOf: chunk.map { MusicItemID($0) }
      )
      request.limit = lookupChunkSize
      let response = try await request.response()
      for song in response.items {
        byID[song.id.rawValue] = song
      }
    }

    // 重複する曲（同じ曲を2回演奏した等）も、その回数だけ入れる。
    return ids.compactMap { byID[$0] }
  }
}
