import Foundation

/// Ports screens/CollectionScreen.tsx's `fetchTodaySongForArtist` — a
/// "song of the day" for the Next Live card's back face, searched via
/// MusicKit and cached per artist+calendar-day in `UserDefaults` (RN's
/// AsyncStorage equivalent).
///
/// RN から意図して変えた点（「固定周期で回っている気がする」という指摘を
/// 受けて）:
/// - 選曲は RN の `seededRandom`（日付を種にした sin の小数部）をやめて
///   普通の乱数にした。RN の式は点数が `sin(日付 + 曲番号×13)` なので、
///   13日後には「今日のリストで1つ前の曲」がほぼ必ず選ばれるという周期が
///   あった。その日の結果は日付キーでキャッシュするので、日付から同じ結果を
///   再現できる必要はもう無い。
/// - 履歴は「一巡するまで同じ曲を出さない」方式にした。RN は直近20件を
///   除外していたが、候補も最大20曲なので2週間ほどで全曲が履歴に入り
///   っぱなしになり、以降は除外が効かず2日連続で同じ曲が出ていた。
/// - 候補を検索上位20件から30件に増やした。
struct TodaySongResult: Codable, Equatable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let genre: String
  let durationSeconds: Double?
  let releaseDate: Date?
  let artworkUrl: String?
  let appleMusicUrl: String?
}

enum TodaySongCache {
  /// 候補にする検索結果の件数。Apple Music の検索は1回25件までなので
  /// 25件＋続きの5件の2回に分けて取る。
  static let candidateLimit = 30
  private static let firstPageLimit = 25

  /// 履歴は一巡ごとにリセットされるので候補数を超えることはないが、検索
  /// 結果の入れ替わりで古い ID が残り続けないよう上限を置いておく。
  private static let maxHistory = candidateLimit

  static func normalizeArtistName(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "[\\s・･·•]", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
  }

  private static func historyKey(for artistName: String) -> String {
    "todaySongHistory:\(normalizeArtistName(artistName))"
  }

  private static func dailyPickKey(for artistName: String, dateKey: String) -> String {
    "todaySongPick:\(normalizeArtistName(artistName)):\(dateKey)"
  }

  // A real local calendar day (like "today's date" shown to the user, not
  // one of CD_ChekiRecord's UTC-anchored wall-clock strings) — Calendar
  // .current is the correct choice here, matching the same
  // real-instant-vs-wall-clock-string distinction already established for
  // joinedAt/plusStartedAt elsewhere in this app.
  private static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
  }

  static func fetchTodaySong(
    for artistName: String,
    now: Date = Date(),
    service: AppleMusicService = AppleMusicService(),
    defaults: UserDefaults = .standard
  ) async -> TodaySongResult? {
    let trimmedArtist = artistName.trimmingCharacters(in: .whitespaces)
    guard !trimmedArtist.isEmpty else { return nil }

    let key = dateKey(for: now)
    let pickKey = dailyPickKey(for: trimmedArtist, dateKey: key)

    if let cached = defaults.data(forKey: pickKey),
       let decoded = try? JSONDecoder().decode(TodaySongResult.self, from: cached) {
      return decoded
    }

    guard let songs = await searchCandidates(for: trimmedArtist, service: service), !songs.isEmpty else {
      return nil
    }

    var rng = SystemRandomNumberGenerator()
    return commitDailyPick(from: songs, artistName: trimmedArtist, pickKey: pickKey, defaults: defaults, using: &rng)
  }

  /// 選曲から保存までを1つの処理として直列化する。同じアーティスト・同じ日の
  /// 取得が並行すると（一覧を素早く出入りしたときなど）、どちらも検索前に
  /// キャッシュを外し、それぞれ別の曲を乱数で選んで後勝ちで上書きしてしまう。
  /// ここで改めてキャッシュを確認し、先に保存された曲があればそれを返す。
  private static let pickLock = NSLock()

  static func commitDailyPick<R: RandomNumberGenerator>(
    from songs: [AppleMusicService.SongResult],
    artistName trimmedArtist: String,
    pickKey: String,
    defaults: UserDefaults,
    using rng: inout R
  ) -> TodaySongResult? {
    pickLock.lock()
    defer { pickLock.unlock() }

    if let cached = defaults.data(forKey: pickKey),
       let decoded = try? JSONDecoder().decode(TodaySongResult.self, from: cached) {
      return decoded
    }

    let historyForArtist = defaults.stringArray(forKey: historyKey(for: trimmedArtist)) ?? []
    guard let pick = pickSong(from: songs, matching: trimmedArtist, history: historyForArtist, using: &rng) else {
      return nil
    }
    let selectedSong = pick.song
    defaults.set(Array(pick.nextHistory.prefix(maxHistory)), forKey: historyKey(for: trimmedArtist))

    let result = TodaySongResult(
      id: selectedSong.id,
      title: selectedSong.title.isEmpty ? "Unknown song" : selectedSong.title,
      artist: selectedSong.artistName.isEmpty ? trimmedArtist : selectedSong.artistName,
      album: selectedSong.albumName.isEmpty ? "-" : selectedSong.albumName,
      genre: selectedSong.genreName ?? "-",
      durationSeconds: selectedSong.durationSeconds,
      releaseDate: selectedSong.releaseDate,
      artworkUrl: selectedSong.artworkUrl.isEmpty ? nil : selectedSong.artworkUrl,
      appleMusicUrl: selectedSong.appleMusicUrl
    )

    if let encoded = try? JSONEncoder().encode(result) {
      defaults.set(encoded, forKey: pickKey)
    }

    return result
  }

  /// 1ページ目（25件）と続き（5件）を取り、ID で重複を除いて最大30件に
  /// する。2ページ目の失敗は1ページ目だけで続行する。
  private static func searchCandidates(
    for artistName: String,
    service: AppleMusicService
  ) async -> [AppleMusicService.SongResult]? {
    guard let firstPage = try? await service.searchSongs(term: artistName, limit: firstPageLimit) else {
      return nil
    }
    guard firstPage.count == firstPageLimit else { return firstPage }
    let secondPage = (try? await service.searchSongs(
      term: artistName,
      limit: candidateLimit - firstPageLimit,
      offset: firstPageLimit
    )) ?? []
    var seen = Set<String>()
    return (firstPage + secondPage).filter { seen.insert($0.id).inserted }.prefix(candidateLimit).map { $0 }
  }

  struct Pick {
    let song: AppleMusicService.SongResult
    /// 保存し直す履歴（新しい順）
    let nextHistory: [String]
  }

  /// Pure selection logic (no I/O), split out from `fetchTodaySong` so it's
  /// unit-testable: prefer songs whose artist name matches `artistName`
  /// (falling back to the full unfiltered list if none match), then pick
  /// at random among songs not yet shown in the current round (`history`,
  /// newest first). Once every candidate has been shown, a new round
  /// starts: the history is reset, and the song shown last is skipped so
  /// the round boundary can't produce the same song two days in a row.
  static func pickSong<R: RandomNumberGenerator>(
    from songs: [AppleMusicService.SongResult],
    matching artistName: String,
    history: [String],
    using rng: inout R
  ) -> Pick? {
    guard !songs.isEmpty else { return nil }

    let normalizedTarget = normalizeArtistName(artistName)
    // Exact normalized match first — "contains" alone is too loose and can
    // match a different artist whose name overlaps (e.g. "AI" inside "AIMYON").
    let exactMatched = songs.filter { normalizeArtistName($0.artistName) == normalizedTarget }
    let looseMatched = songs.filter {
      let normalized = normalizeArtistName($0.artistName)
      return normalized.contains(normalizedTarget) || normalizedTarget.contains(normalized)
    }
    let filteredSongs = exactMatched.isEmpty ? (looseMatched.isEmpty ? songs : looseMatched) : exactMatched

    let freshCandidates = filteredSongs.filter { !history.contains($0.id) }
    let isNewRound = freshCandidates.isEmpty
    let candidates: [AppleMusicService.SongResult]
    if isNewRound {
      let withoutLastShown = filteredSongs.filter { $0.id != history.first }
      candidates = withoutLastShown.isEmpty ? filteredSongs : withoutLastShown
    } else {
      candidates = freshCandidates
    }

    guard let song = candidates.randomElement(using: &rng) else { return nil }
    let base = isNewRound ? [] : history.filter { $0 != song.id }
    return Pick(song: song, nextHistory: [song.id] + base)
  }
}
