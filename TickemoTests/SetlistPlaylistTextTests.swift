import XCTest
@testable import Tickemo

final class SetlistPlaylistTextTests: XCTestCase {
  private typealias Song = (songName: String?, performerName: String?, artistName: String?)

  // MARK: - playlistName

  func testPlaylistNameCombinesLiveNameAndDate() {
    XCTAssertEqual(
      SetlistPlaylistText.playlistName(
        liveName: "sumimi ONE-MAN LIVE",
        venue: "Kアリーナ横浜",
        date: "2026-04-26"
      ),
      "sumimi ONE-MAN LIVE（2026.04.26）"
    )
  }

  func testPlaylistNameFallsBackToTheVenueWhenTheLiveIsUnnamed() {
    XCTAssertEqual(
      SetlistPlaylistText.playlistName(liveName: "   ", venue: "Kアリーナ横浜", date: "2026-04-26"),
      "Kアリーナ横浜（2026.04.26）"
    )
  }

  func testPlaylistNameFallsBackToAGenericNameWithNeitherLiveNorVenue() {
    XCTAssertEqual(
      SetlistPlaylistText.playlistName(liveName: nil, venue: nil, date: nil),
      "セットリスト"
    )
  }

  /// 壊れた日付をプレイリスト名に混ぜない。
  func testPlaylistNameOmitsAnUnparseableDate() {
    XCTAssertEqual(
      SetlistPlaylistText.playlistName(liveName: "LIVE", venue: nil, date: "not-a-date"),
      "LIVE"
    )
  }

  // MARK: - songList

  func testSongListNumbersSongsAndPutsTheHeaderFirst() {
    let text = SetlistPlaylistText.songList(
      liveName: "sumimi ONE-MAN LIVE",
      venue: "Kアリーナ横浜",
      date: "2026-04-26",
      songs: [
        Song("ハピネス", "sumimi", "sumimi"),
        Song("Here, the world!", "sumimi", "sumimi"),
      ]
    )
    XCTAssertEqual(
      text,
      """
      sumimi ONE-MAN LIVE
      2026.04.26 / Kアリーナ横浜

      01. ハピネス - sumimi
      02. Here, the world! - sumimi
      """
    )
  }

  /// カバー曲は音源のアーティストではなく歌った人で書き出す — 曲カードや
  /// プロバイダー検索と同じ規則。
  func testSongListPrefersThePerformerOverTheSongArtist() {
    let text = SetlistPlaylistText.songList(
      liveName: nil,
      venue: nil,
      date: nil,
      songs: [Song("詩超絆", "sumimi", "MyGO!!!!!")]
    )
    XCTAssertEqual(text, "01. 詩超絆 - sumimi")
  }

  func testSongListFallsBackToTheSongArtistWhenNoPerformerIsTagged() {
    let text = SetlistPlaylistText.songList(
      liveName: nil,
      venue: nil,
      date: nil,
      songs: [Song("詩超絆", nil, "MyGO!!!!!")]
    )
    XCTAssertEqual(text, "01. 詩超絆 - MyGO!!!!!")
  }

  func testSongListOmitsTheDashWhenNoArtistIsKnown() {
    let text = SetlistPlaylistText.songList(
      liveName: nil,
      venue: nil,
      date: nil,
      songs: [Song("詩超絆", nil, nil)]
    )
    XCTAssertEqual(text, "01. 詩超絆")
  }

  /// 曲名が空の行は番号を消費しない。
  func testSongListSkipsBlankSongNamesWithoutConsumingANumber() {
    let text = SetlistPlaylistText.songList(
      liveName: nil,
      venue: nil,
      date: nil,
      songs: [
        Song("ハピネス", nil, nil),
        Song("  ", nil, nil),
        Song(nil, nil, nil),
        Song("詩超絆", nil, nil),
      ]
    )
    XCTAssertEqual(text, "01. ハピネス\n02. 詩超絆")
  }

  func testSongListHeaderUsesWhicheverOfDateAndVenueIsKnown() {
    let venueOnly = SetlistPlaylistText.songList(
      liveName: "LIVE",
      venue: "Kアリーナ横浜",
      date: nil,
      songs: [Song("ハピネス", nil, nil)]
    )
    XCTAssertEqual(venueOnly, "LIVE\nKアリーナ横浜\n\n01. ハピネス")

    let dateOnly = SetlistPlaylistText.songList(
      liveName: "LIVE",
      venue: "  ",
      date: "2026-04-26",
      songs: [Song("ハピネス", nil, nil)]
    )
    XCTAssertEqual(dateOnly, "LIVE\n2026.04.26\n\n01. ハピネス")
  }

  func testSongListWithNoHeaderStartsStraightAtTheFirstSong() {
    let text = SetlistPlaylistText.songList(
      liveName: "  ",
      venue: nil,
      date: nil,
      songs: [Song("ハピネス", nil, nil)]
    )
    XCTAssertEqual(text, "01. ハピネス")
  }

  func testSongListIsEmptyWhenThereIsNothingToWriteOut() {
    XCTAssertEqual(
      SetlistPlaylistText.songList(liveName: nil, venue: nil, date: nil, songs: []),
      ""
    )
  }
}
