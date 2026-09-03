import Foundation
import MediaPlayer
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
      "Apple Musicから応答がありませんでした。Apple Musicアプリを一度開いて利用規約に同意し、設定の「ライブラリを同期」がオンになっているか確認してから、再度お試しください。"
    }
  }
}

/// 書き出し1回分の足取り。os_log に出すのと同じ内容を文字列としても貯める。
///
/// 実機の不具合報告で Console.app のログを求めても、目的の行にたどり着け
/// ないことがある（無関係な RevenueCat の出力が送られてきた）。画面の
/// アラートからそのままコピーできる形で持っておけば、Mac を繋がなくても
/// 送ってもらえる。
final class ApplePlaylistExportDiagnostics: @unchecked Sendable {
  private static let log = Logger(subsystem: "com.anonymous.Tickemo", category: "PlaylistExport")

  private let lock = NSLock()
  private var lines: [String] = []
  private let startedAt = Date()

  func record(_ line: String, isFailure: Bool = false) {
    if isFailure {
      Self.log.error("\(line, privacy: .public)")
    } else {
      Self.log.info("\(line, privacy: .public)")
    }
    let elapsed = String(format: "%6.2fs", Date().timeIntervalSince(startedAt))
    lock.lock()
    defer { lock.unlock() }
    lines.append("[\(elapsed)] \(line)")
  }

  var text: String {
    lock.lock()
    defer { lock.unlock() }
    return lines.joined(separator: "\n")
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
/// 作成の実体は2経路ある。MusicKit の `MusicLibrary.createPlaylist` が
/// 応答を返さないまま固まる事例を確認しているため、打ち切ったあとに
/// MediaPlayer の `MPMediaLibrary` へ切り替えて再試行する。後者は
/// MusicKit 以前からある API で iTunesCloud への経路が別なので、片方が
/// 駄目でももう片方で通ることがある。
enum ApplePlaylistExporter {
  /// `MusicCatalogResourceRequest` の 1 リクエストあたりの ID 数上限に
  /// 余裕を持たせた分割単位。長いセトリでも取りこぼさないよう分割して
  /// 引き、結果は元の曲順に並べ直す（レスポンスの順序は保証されない）。
  private static let lookupChunkSize = 25

  /// Apple Music 側が応答を返さないまま固まったときに打ち切るまでの秒数。
  /// 2経路とも試すので、最悪の待ち時間はこの倍以上になる。1曲ずつ足す
  /// MediaPlayer 経路のことも考えて、1回あたりは短めに取る。
  private static let stepTimeout: TimeInterval = 20

  /// 作成したプレイリストに入った曲数を返す。
  @discardableResult
  static func createPlaylist(
    named name: String,
    songIds: [String],
    diagnostics: ApplePlaylistExportDiagnostics
  ) async throws -> Int {
    let ids = songIds
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    diagnostics.record("開始: name=\(name) songIds=\(ids.count)")

    guard !ids.isEmpty else {
      diagnostics.record("中断: 書き出せる songId が 0 件", isFailure: true)
      throw ApplePlaylistExportError.noExportableSongs
    }

    try await requireAuthorization(diagnostics)
    await recordStorefront(diagnostics)
    try await requireSubscription(diagnostics)

    let songs = try await catalogSongs(for: ids, diagnostics: diagnostics)

    do {
      try await createViaMusicKit(named: name, songs: songs, diagnostics: diagnostics)
      return songs.count
    } catch {
      diagnostics.record("MusicKit 経路が失敗。MediaPlayer 経路に切り替える", isFailure: true)
      return try await createViaMediaPlayer(
        named: name,
        songIds: songs.map(\.id.rawValue),
        diagnostics: diagnostics
      )
    }
  }

  // MARK: - 作成（経路1: MusicKit）

  private static func createViaMusicKit(
    named name: String,
    songs: [Song],
    diagnostics: ApplePlaylistExportDiagnostics
  ) async throws {
    do {
      let playlist = try await withTimeout(seconds: stepTimeout) {
        try await MusicLibrary.shared.createPlaylist(name: name, items: songs)
      }
      diagnostics.record("MusicKit 成功: playlistId=\(playlist.id.rawValue) 曲数=\(songs.count)")
    } catch is TimeoutError {
      diagnostics.record("MusicKit タイムアウト（\(Int(stepTimeout))秒）", isFailure: true)
      throw ApplePlaylistExportError.timedOut
    } catch {
      diagnostics.record("MusicKit 失敗: \(describe(error))", isFailure: true)
      throw ApplePlaylistExportError.playlistCreationFailed(describe(error))
    }
  }

  // MARK: - 作成（経路2: MediaPlayer）

  /// `MPMediaLibrary` 版。空のプレイリストを作ってからストア ID を1曲ずつ
  /// 足す。1曲単位なので、途中で失敗してもそこまでは残る（何曲入ったかを
  /// 記録して、1曲も入らなかったときだけ失敗として扱う）。
  private static func createViaMediaPlayer(
    named name: String,
    songIds: [String],
    diagnostics: ApplePlaylistExportDiagnostics
  ) async throws -> Int {
    let status = await MPMediaLibrary.requestAuthorization()
    diagnostics.record("MediaPlayer 認可: \(status.rawValue)")
    guard status == .authorized else {
      throw ApplePlaylistExportError.playlistCreationFailed("メディアライブラリへのアクセスが許可されていません。")
    }

    let playlist: MPMediaPlaylist
    do {
      playlist = try await withTimeout(seconds: stepTimeout) {
        try await MPMediaLibrary.default().getPlaylist(
          with: UUID(),
          creationMetadata: MPMediaPlaylistCreationMetadata(name: name)
        )
      }
      diagnostics.record("MediaPlayer プレイリスト作成完了。曲の追加を開始")
    } catch is TimeoutError {
      diagnostics.record("MediaPlayer タイムアウト（\(Int(stepTimeout))秒）", isFailure: true)
      throw ApplePlaylistExportError.timedOut
    } catch {
      diagnostics.record("MediaPlayer 失敗: \(describe(error))", isFailure: true)
      throw ApplePlaylistExportError.playlistCreationFailed(describe(error))
    }

    var added = 0
    for songId in songIds {
      do {
        try await withTimeout(seconds: stepTimeout) {
          try await playlist.addItem(withProductID: songId)
        }
        added += 1
      } catch {
        diagnostics.record("追加失敗 songId=\(songId): \(describe(error))", isFailure: true)
      }
    }

    diagnostics.record("MediaPlayer 結果: 追加=\(added)/\(songIds.count)")
    guard added > 0 else {
      throw ApplePlaylistExportError.playlistCreationFailed("プレイリストは作成できましたが、1曲も追加できませんでした。")
    }
    return added
  }

  // MARK: - タイムアウト

  struct TimeoutError: Error {}

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

  /// Apple Music 側の処理は応答を返さないまま固まることがある。
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
  /// タイムアウト機構ごと道連れに固まる（実測でも55秒待って何も
  /// 起きなかった）。キャンセルも効かない — 相手は再開されない
  /// continuation を握ったままなので、待つのをやめるしか手がない。
  ///
  /// そのため、処理を非構造化タスクとして起動し、先に決着した方だけが
  /// continuation を再開する形にする。タイムアウト時、固まったタスクは
  /// 回収されずに残る（リークする）が、アプリは応答を保ち、利用者には
  /// 「応答がなかった」と伝わる。ここは意図的な割り切り。
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

  private static func requireAuthorization(_ diagnostics: ApplePlaylistExportDiagnostics) async throws {
    let before = MusicAuthorization.currentStatus
    let status = before == .authorized ? before : await MusicAuthorization.request()
    diagnostics.record("認可: 事前=\(before) 確定=\(status)")
    guard status == .authorized else {
      throw ApplePlaylistExportError.notAuthorized(status)
    }
  }

  /// 曲の `songId` は AppleMusicService が「jp」ストアフロント固定で検索
  /// した結果（catalogSearchURL 参照）なのに対し、ここで使う
  /// `MusicCatalogResourceRequest` は端末のストアフロントで引く。両者が
  /// 食い違うと ID が解決できず 0 件になるので、実際の国コードを必ず残す。
  private static func recordStorefront(_ diagnostics: ApplePlaylistExportDiagnostics) async {
    do {
      let code = try await MusicDataRequest.currentCountryCode
      diagnostics.record("ストアフロント: 端末=\(code) / songId の取得元=jp")
      if code != "jp" {
        diagnostics.record("警告: ストアフロント不一致。jp のカタログ ID が解決できない可能性がある", isFailure: true)
      }
    } catch {
      diagnostics.record("ストアフロント取得失敗: \(describe(error))", isFailure: true)
    }
  }

  /// サブスクリプションの取得自体が失敗した場合は止めない。ここで
  /// 打ち切ると「サブスクリプションが必要です」という誤った案内になり、
  /// 本当の失敗理由（作成側のエラー）が見えなくなるため、はっきり
  /// 「加入していない」と分かったときだけ弾く。
  private static func requireSubscription(_ diagnostics: ApplePlaylistExportDiagnostics) async throws {
    do {
      let subscription = try await MusicSubscription.current
      diagnostics.record("""
        サブスクリプション: canPlayCatalogContent=\(subscription.canPlayCatalogContent) \
        canBecomeSubscriber=\(subscription.canBecomeSubscriber) \
        hasCloudLibraryEnabled=\(subscription.hasCloudLibraryEnabled)
        """)
      if !subscription.hasCloudLibraryEnabled {
        diagnostics.record("警告: ライブラリの同期がオフ。プレイリストを保存できない可能性がある", isFailure: true)
      }
      guard subscription.canPlayCatalogContent else {
        throw ApplePlaylistExportError.noSubscription
      }
    } catch let error as ApplePlaylistExportError {
      throw error
    } catch {
      diagnostics.record("サブスクリプション取得失敗（続行する）: \(describe(error))", isFailure: true)
    }
  }

  // MARK: - カタログ照会

  private static func catalogSongs(
    for ids: [String],
    diagnostics: ApplePlaylistExportDiagnostics
  ) async throws -> [Song] {
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
        diagnostics.record("カタログ照会: 要求=\(chunk.count) 取得=\(response.items.count)")
        for song in response.items {
          byID[song.id.rawValue] = song
        }
      } catch {
        lastFailure = describe(error)
        diagnostics.record("カタログ照会失敗: \(describe(error))", isFailure: true)
      }
    }

    let missing = ids.filter { byID[$0] == nil }
    if !missing.isEmpty {
      diagnostics.record("解決できなかった songId (\(missing.count)件): \(missing.joined(separator: ","))", isFailure: true)
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
