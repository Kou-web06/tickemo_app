import XCTest
@testable import Tickemo

/// テスト用の決定的な乱数（SplitMix64）。
private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
}

final class TodaySongCacheTests: XCTestCase {
  private var rng = SeededGenerator(state: 42)
  private func song(id: String, artistName: String) -> AppleMusicService.SongResult {
    AppleMusicService.SongResult(
      id: id,
      title: "Song \(id)",
      artistName: artistName,
      albumName: "Album",
      artworkUrl: "",
      genreName: nil,
      durationSeconds: nil,
      releaseDate: nil,
      appleMusicUrl: nil
    )
  }

  // MARK: - normalizeArtistName

  func testNormalizeArtistNameStripsFullWidthAndHalfWidthSeparatorsAndLowercases() {
    XCTAssertEqual(TodaySongCache.normalizeArtistName("YOASOBI"), "yoasobi")
    XCTAssertEqual(TodaySongCache.normalizeArtistName(" Ado "), "ado")
    XCTAssertEqual(TodaySongCache.normalizeArtistName("あい・きゃん"), "あいきゃん")
  }

  // MARK: - pickSong

  func testPickSongPrefersArtistNameMatchesOverUnrelatedResults() {
    let songs = [
      song(id: "unrelated", artistName: "Someone Else"),
      song(id: "matched", artistName: "YOASOBI"),
    ]

    let picked = TodaySongCache.pickSong(from: songs, matching: "YOASOBI", history: [], using: &rng)

    XCTAssertEqual(picked?.song.id, "matched")
  }

  func testPickSongFallsBackToUnfilteredListWhenNoArtistMatches() {
    let songs = [song(id: "a", artistName: "Someone Else")]

    let picked = TodaySongCache.pickSong(from: songs, matching: "YOASOBI", history: [], using: &rng)

    XCTAssertEqual(picked?.song.id, "a")
  }

  func testPickSongExcludesRecentHistoryWhenFreshCandidatesExist() {
    let songs = [
      song(id: "shown-yesterday", artistName: "Ado"),
      song(id: "not-shown-yet", artistName: "Ado"),
    ]

    let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", history: ["shown-yesterday"], using: &rng)

    XCTAssertEqual(picked?.song.id, "not-shown-yet")
    XCTAssertEqual(picked?.nextHistory, ["not-shown-yet", "shown-yesterday"])
  }

  func testPickSongFallsBackToFullHistoryWhenEverySongWasAlreadyShown() {
    let songs = [song(id: "only-one", artistName: "Ado")]

    let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", history: ["only-one"], using: &rng)

    XCTAssertEqual(picked?.song.id, "only-one", "with no fresh candidates left, the previously-shown song is picked again rather than returning nil")
  }

  func testPickSongReturnsNilForEmptyInput() {
    XCTAssertNil(TodaySongCache.pickSong(from: [], matching: "Ado", history: [], using: &rng))
  }

  func testNewRoundResetsHistoryAndSkipsTheSongShownLast() {
    let songs = [song(id: "a", artistName: "Ado"), song(id: "b", artistName: "Ado")]

    for _ in 0..<20 {
      let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", history: ["a", "b"], using: &rng)
      XCTAssertEqual(picked?.song.id, "b", "a was shown last, so the new round must not start with it")
      XCTAssertEqual(picked?.nextHistory, ["b"])
    }
  }

  /// 日ごとの選曲を実際の保存と同じ手順で回し、一巡の中で重複が無いことと、
  /// 2日連続で同じ曲にならないことを確かめる（RN の式ではどちらも崩れていた）。
  func testEverySongAppearsOncePerRoundAndNeverTwoDaysInARow() {
    let songs = (0..<15).map { song(id: "s\($0)", artistName: "Ado") }
    var history: [String] = []
    var shown: [String] = []

    for _ in 0..<(15 * 8) {
      let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", history: history, using: &rng)!
      shown.append(picked.song.id)
      history = picked.nextHistory
    }

    for round in 0..<8 {
      let slice = shown[(round * 15)..<((round + 1) * 15)]
      XCTAssertEqual(Set(slice).count, 15, "round \(round) must show every song exactly once")
    }
    for day in 1..<shown.count {
      XCTAssertNotEqual(shown[day], shown[day - 1], "day \(day) repeated yesterday's song")
    }
  }

  func testPickIsNotDeterminedByTheDate() {
    // 同じ入力でも乱数が違えば別の曲が選ばれうる（日付に縛られた周期が無い）
    let songs = (0..<10).map { song(id: "s\($0)", artistName: "Ado") }
    var picks = Set<String>()
    for seed in 0..<50 {
      var generator = SeededGenerator(state: UInt64(seed))
      picks.insert(TodaySongCache.pickSong(from: songs, matching: "Ado", history: [], using: &generator)!.song.id)
    }
    XCTAssertGreaterThan(picks.count, 5)
  }

  /// 同じアーティスト・同じ日の取得が並行しても、後から来た方は先に保存された
  /// 曲を返し、キャッシュも履歴も上書きしない（Codex レビューの指摘）
  func testCommitDailyPickKeepsTheFirstPickWhenTwoFetchesOverlap() {
    let suiteName = "TodaySongCacheTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let songs = (0..<30).map { song(id: "s\($0)", artistName: "Ado") }

    var first = SeededGenerator(state: 1)
    var second = SeededGenerator(state: 999)
    let a = TodaySongCache.commitDailyPick(from: songs, artistName: "Ado", pickKey: "pick", defaults: defaults, using: &first)
    let b = TodaySongCache.commitDailyPick(from: songs, artistName: "Ado", pickKey: "pick", defaults: defaults, using: &second)

    XCTAssertNotNil(a)
    XCTAssertEqual(a, b)
    XCTAssertEqual(defaults.stringArray(forKey: "todaySongHistory:ado"), [a!.id])
  }
}
