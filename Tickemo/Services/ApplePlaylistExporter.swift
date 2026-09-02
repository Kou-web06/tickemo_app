import Foundation
import MusicKit
import OSLog

enum ApplePlaylistExportError: LocalizedError {
  case notAuthorized(MusicAuthorization.Status)
  case noSubscription
  case noExportableSongs
  case catalogLookupFailed(requested: Int, detail: String)
  case playlistCreationFailed(String)
  case timedOut

  var errorDescription: String? {
    switch self {
    case .notAuthorized(let status):
      "Apple Musicへのアクセスが許可されていません（状態: \(status)）。設定アプリの「Tickemo」から許可してください。"
    case .noSubscription:
      "Apple Musicのプレイリスト作成には、Apple Musicのサブスクリプションが必要です。曲リストのコピー／共有はサブスクリプションなしでも使えます。"
    case .noExportableSongs:
      "Apple Musicに登録されている曲がありません。曲名検索から追加した曲だけがプレイリストに入れられます。"
    case .catalogLookupFailed(let requested, let detail):
      "Apple Musicで曲を見つけられませんでした（\(requested)曲を照会）。\(detail)"
    case .playlistCreationFailed(let detail):
      "プレイリストを作成できませんでした。\(detail)"
    case .timedOut:
      "Apple Musicが応答しませんでした。通信状況を確認するか、Apple Musicアプリを一度開いてから再度お試しください。"
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
///
/// 失敗の切り分けが要るので、各段階を `PlaylistExport` カテゴリの
/// Logger に出す。Console.app / Xcode の Devices で
/// `subsystem:com.anonymous.Tickemo category:PlaylistExport` を絞れば
/// 実機でも追える。エラーの本文も画面のアラートに出しているので、
/// Mac を繋がずに原因を読み取れる。
enum ApplePlaylistExporter {
  private static let log = Logger(subsystem: "com.anonymous.Tickemo", category: "PlaylistExport")

  /// `MusicCatalogResourceRequest` の 1 リクエストあたりの ID 数上限に
  /// 余裕を持たせた分割単位。長いセトリでも取りこぼさないよう分割して
  /// 引き、結果は元の曲順に並べ直す（レスポンスの順序は保証されない）。
  private static let lookupChunkSize = 25

  /// Apple Music 側が応答を返さないまま固まったときに打ち切るまでの秒数。
  private static let createPlaylistTimeout: TimeInterval = 30

  /// 作成したプレイリストに入った曲数を返す。
  @discardableResult
  static func createPlaylist(named name: String, songIds: [String]) async throws -> Int {
    let ids = songIds
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    log.info("開始: name=\(name, privacy: .public) songIds=\(ids.count, privacy: .public)")
    log.debug("songIds=\(ids.joined(separator: ","), privacy: .public)")

    guard !ids.isEmpty else {
      log.error("中断: 書き出せる songId が 0 件")
      throw ApplePlaylistExportError.noExportableSongs
    }

    try await requireAuthorization()
    await logStorefront()
    try await requireSubscription()

    let songs = try await catalogSongs(for: ids)

    do {
      let playlist = try await withTimeout(seconds: createPlaylistTimeout) {
        try await MusicLibrary.shared.createPlaylist(name: name, items: songs)
      }
      log.info("成功: playlistId=\(playlist.id.rawValue, privacy: .public) 曲数=\(songs.count, privacy: .public)")
      return songs.count
    } catch is TimeoutError {
      log.error("createPlaylist タイムアウト（\(Int(createPlaylistTimeout), privacy: .public)秒）")
      throw ApplePlaylistExportError.timedOut
    } catch {
      log.error("createPlaylist 失敗: \(describe(error), privacy: .public)")
      throw ApplePlaylistExportError.playlistCreationFailed(describe(error))
    }
  }

  // MARK: - タイムアウト

  struct TimeoutError: Error {}

  /// `MusicLibrary.createPlaylist` は応答を返さないまま固まることがある。
  /// シミュレータで実際に確認したケースでは、iTunesCloud との XPC 接続が
  /// 切れた（ICMusicSubscriptionStatusController の
  /// _handleSeveredRemoteClientConnection）あと continuation が二度と
  /// 再開されず、どのスレッドも動いていないのにタスクだけが永久に
  /// 止まったままになる。放置するとボタンのスピナーが回り続けるだけで、
  /// ログにも画面にも何の手掛かりも残らない。
  ///
  /// ここで `withThrowingTaskGroup` を使ってはいけない。グループは
  /// スコープを抜ける前に全ての子タスクの完了を待つ仕様なので、片方が
  /// 固まっていると、もう片方がタイムアウトを投げても脱出できず、
  /// タイムアウト機構ごと道連れに固まる（実測でも30秒どころか55秒
  /// 待っても何も起きなかった）。キャンセルも効かない — MusicKit 側は
  /// 再開されない continuation を握ったままなので、待つのをやめるしか
  /// 手がない。
  ///
  /// そのため、処理を非構造化タスクとして起動し、先に決着した方だけが
  /// continuation を再開する形にする。タイムアウト時、固まったタスクは
  /// 回収されずに残る（リークする）が、アプリは応答を保ち、利用者には
  /// 「応答がなかった」と伝わる。ここは意図的な割り切り。
  /// 勝った側だけが continuation を再開できるようにする番人。
  /// continuation の二重再開はクラッシュするので、必ずここを通す。
  private final class TimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !claimed else { return false }
      claimed = true
      return true
    }
  }

  static func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let gate = TimeoutGate()
    return try await withCheckedThrowingContinuation { continuation in
      let work = Task {
        do {
          let value = try await operation()
          if gate.claim() { continuation.resume(returning: value) }
        } catch {
          if gate.claim() { continuation.resume(throwing: error) }
        }
      }
      Task {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard gate.claim() else { return }
        // 効かない可能性が高いが、応じてくれる相手なら止まるので一応投げる。
        work.cancel()
        continuation.resume(throwing: TimeoutError())
      }
    }
  }

  // MARK: - 前提条件

  private static func requireAuthorization() async throws {
    let before = MusicAuthorization.currentStatus
    let status = before == .authorized ? before : await MusicAuthorization.request()
    log.info("認可: 事前=\(String(describing: before), privacy: .public) 確定=\(String(describing: status), privacy: .public)")
    guard status == .authorized else {
      throw ApplePlaylistExportError.notAuthorized(status)
    }
  }

  /// 曲の `songId` は AppleMusicService が「jp」ストアフロント固定で検索
  /// した結果（catalogSearchURL 参照）なのに対し、ここで使う
  /// `MusicCatalogResourceRequest` は端末のストアフロントで引く。両者が
  /// 食い違うと ID が解決できず 0 件になるので、実際の国コードを必ず残す。
  private static func logStorefront() async {
    do {
      let code = try await MusicDataRequest.currentCountryCode
      log.info("ストアフロント: 端末=\(code, privacy: .public) / songId の取得元=jp")
      if code != "jp" {
        log.warning("ストアフロント不一致。jp のカタログ ID が解決できない可能性がある")
      }
    } catch {
      log.error("ストアフロント取得失敗: \(describe(error), privacy: .public)")
    }
  }

  /// サブスクリプションの取得自体が失敗した場合は止めない。ここで
  /// 打ち切ると「サブスクリプションが必要です」という誤った案内になり、
  /// 本当の失敗理由（createPlaylist 側のエラー）が見えなくなるため、
  /// はっきり「加入していない」と分かったときだけ弾く。
  private static func requireSubscription() async throws {
    do {
      let subscription = try await MusicSubscription.current
      log.info("""
        サブスクリプション: canPlayCatalogContent=\(subscription.canPlayCatalogContent, privacy: .public) \
        canBecomeSubscriber=\(subscription.canBecomeSubscriber, privacy: .public) \
        hasCloudLibraryEnabled=\(subscription.hasCloudLibraryEnabled, privacy: .public)
        """)
      guard subscription.canPlayCatalogContent else {
        throw ApplePlaylistExportError.noSubscription
      }
    } catch let error as ApplePlaylistExportError {
      throw error
    } catch {
      log.error("サブスクリプション取得失敗（続行する）: \(describe(error), privacy: .public)")
    }
  }

  // MARK: - カタログ照会

  private static func catalogSongs(for ids: [String]) async throws -> [Song] {
    var byID: [String: Song] = [:]
    var lastFailure: String?

    for chunk in stride(from: 0, to: ids.count, by: lookupChunkSize).map({ start in
      Array(ids[start..<min(start + lookupChunkSize, ids.count)])
    }) {
      do {
        var request = MusicCatalogResourceRequest<Song>(
          matching: \.id,
          memberOf: chunk.map { MusicItemID($0) }
        )
        request.limit = lookupChunkSize
        let response = try await request.response()
        log.info("カタログ照会: 要求=\(chunk.count, privacy: .public) 取得=\(response.items.count, privacy: .public)")
        for song in response.items {
          byID[song.id.rawValue] = song
        }
      } catch {
        lastFailure = describe(error)
        log.error("カタログ照会失敗: \(describe(error), privacy: .public)")
      }
    }

    let missing = ids.filter { byID[$0] == nil }
    if !missing.isEmpty {
      log.warning("解決できなかった songId (\(missing.count, privacy: .public)件): \(missing.joined(separator: ","), privacy: .public)")
    }

    // 重複する曲（同じ曲を2回演奏した等）も、その回数だけ入れる。
    let ordered = ids.compactMap { byID[$0] }
    guard !ordered.isEmpty else {
      throw ApplePlaylistExportError.catalogLookupFailed(
        requested: ids.count,
        detail: lastFailure ?? "該当する曲が1件も返りませんでした。"
      )
    }
    return ordered
  }

  // MARK: - エラー整形

  /// `localizedDescription` だけだと MusicKit のエラーは中身がほぼ
  /// 分からないので、ドメイン／コードと生の記述も併せて残す。
  private static func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)] \(String(describing: error))"
  }
}
