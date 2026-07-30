import XCTest
@testable import Tickemo

final class TodaySongCacheTests: XCTestCase {
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

  // MARK: - seededRandom

  func testSeededRandomIsDeterministicAndWithinUnitRange() {
    let a = TodaySongCache.seededRandom(20240510)
    let b = TodaySongCache.seededRandom(20240510)

    XCTAssertEqual(a, b, "same seed must always produce the same value")
    XCTAssertGreaterThanOrEqual(a, 0)
    XCTAssertLessThan(a, 1)
  }

  // MARK: - pickSong

  func testPickSongPrefersArtistNameMatchesOverUnrelatedResults() {
    let songs = [
      song(id: "unrelated", artistName: "Someone Else"),
      song(id: "matched", artistName: "YOASOBI"),
    ]

    let picked = TodaySongCache.pickSong(from: songs, matching: "YOASOBI", excluding: [], dateKey: "2024-05-10")

    XCTAssertEqual(picked?.id, "matched")
  }

  func testPickSongFallsBackToUnfilteredListWhenNoArtistMatches() {
    let songs = [song(id: "a", artistName: "Someone Else")]

    let picked = TodaySongCache.pickSong(from: songs, matching: "YOASOBI", excluding: [], dateKey: "2024-05-10")

    XCTAssertEqual(picked?.id, "a")
  }

  func testPickSongExcludesRecentHistoryWhenFreshCandidatesExist() {
    let songs = [
      song(id: "shown-yesterday", artistName: "Ado"),
      song(id: "not-shown-yet", artistName: "Ado"),
    ]

    let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", excluding: ["shown-yesterday"], dateKey: "2024-05-10")

    XCTAssertEqual(picked?.id, "not-shown-yet")
  }

  func testPickSongFallsBackToFullHistoryWhenEverySongWasAlreadyShown() {
    let songs = [song(id: "only-one", artistName: "Ado")]

    let picked = TodaySongCache.pickSong(from: songs, matching: "Ado", excluding: ["only-one"], dateKey: "2024-05-10")

    XCTAssertEqual(picked?.id, "only-one", "with no fresh candidates left, the previously-shown song is picked again rather than returning nil")
  }

  func testPickSongReturnsNilForEmptyInput() {
    XCTAssertNil(TodaySongCache.pickSong(from: [], matching: "Ado", excluding: [], dateKey: "2024-05-10"))
  }
}
