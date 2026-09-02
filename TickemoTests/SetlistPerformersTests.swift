import XCTest
@testable import Tickemo

final class SetlistPerformersTests: XCTestCase {
  // MARK: - resolve

  func testResolvePrefersStoredPerformerOverSongArtist() {
    let resolved = SetlistPerformers.resolve(
      stored: ["MyGO!!!!!"],
      songArtists: ["sumimi"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(resolved, ["MyGO!!!!!"])
  }

  func testResolveFallsBackToMatchingSongArtistUsingTheRegisteredSpelling() {
    let resolved = SetlistPerformers.resolve(
      stored: [nil, nil],
      songArtists: ["mygo!!!!!", " sumimi "],
      artistNames: ["MyGO!!!!!", "sumimi"]
    )
    XCTAssertEqual(resolved, ["MyGO!!!!!", "sumimi"])
  }

  /// カバー曲（音源のアーティストが出演者と違う）と、artistName を持たない
  /// MC 行は、どちらも直前の行のブロックに残る。以前のバケット分割では
  /// この2ケースが別ブロックへ飛んでいた。
  func testResolveCarriesForwardForCoversAndMarkers() {
    let resolved = SetlistPerformers.resolve(
      stored: [nil, nil, nil, nil],
      songArtists: ["MyGO!!!!!", nil, "Roselia", "MyGO!!!!!"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(resolved, ["MyGO!!!!!", "MyGO!!!!!", "MyGO!!!!!", "MyGO!!!!!"])
  }

  func testResolveLeavesLeadingUnmatchedRowsUnassigned() {
    let resolved = SetlistPerformers.resolve(
      stored: [nil, nil],
      songArtists: [nil, "sumimi"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(resolved, [nil, "sumimi"])
  }

  func testResolveTreatsBlankStoredValuesAsUnset() {
    let resolved = SetlistPerformers.resolve(
      stored: ["   "],
      songArtists: ["sumimi"],
      artistNames: ["sumimi"]
    )
    XCTAssertEqual(resolved, ["sumimi"])
  }

  func testResolveIgnoresSongArtistsThatAreNotRegisteredPerformers() {
    let resolved = SetlistPerformers.resolve(
      stored: [nil],
      songArtists: ["Roselia"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(resolved, [nil])
  }

  // MARK: - sectionHeaders

  /// A→B→A の交互演奏。番号は通しのまま、切り替わった3か所にだけ
  /// 見出しが立つ。
  func testSectionHeadersMarkEveryPerformerSwitchIncludingAReturn() {
    let performers: [String?] = [
      "sumimi", "sumimi", "sumimi",
      "MyGO!!!!!", "MyGO!!!!!", "MyGO!!!!!",
      "sumimi", "sumimi",
    ]
    XCTAssertEqual(
      SetlistPerformers.sectionHeaders(for: performers),
      ["sumimi", nil, nil, "MyGO!!!!!", nil, nil, "sumimi", nil]
    )
  }

  func testSectionHeadersAreSuppressedForASinglePerformer() {
    let performers: [String?] = ["MyGO!!!!!", "MyGO!!!!!", nil, "MyGO!!!!!"]
    XCTAssertEqual(SetlistPerformers.sectionHeaders(for: performers), [nil, nil, nil, nil])
  }

  func testSectionHeadersAreSuppressedWhenNoPerformerIsAssigned() {
    XCTAssertEqual(SetlistPerformers.sectionHeaders(for: [nil, nil, nil]), [nil, nil, nil])
  }

  /// 未割り当ての行（MC など）はブロックを切らないし、直後の同じ出演者に
  /// 見出しを再発行させることもない。
  func testUnassignedRowsDoNotBreakABlock() {
    let performers: [String?] = ["sumimi", nil, "sumimi", "MyGO!!!!!"]
    XCTAssertEqual(
      SetlistPerformers.sectionHeaders(for: performers),
      ["sumimi", nil, nil, "MyGO!!!!!"]
    )
  }

  func testSectionHeadersCompareCaseInsensitively() {
    let performers: [String?] = ["sumimi", "SUMIMI", "MyGO!!!!!"]
    XCTAssertEqual(
      SetlistPerformers.sectionHeaders(for: performers),
      ["sumimi", nil, "MyGO!!!!!"]
    )
  }

  // MARK: - distinctNames

  func testDistinctNamesKeepsFirstSeenSpellingAndOrder() {
    let performers: [String?] = ["MyGO!!!!!", nil, "mygo!!!!!", "  ", "sumimi"]
    XCTAssertEqual(SetlistPerformers.distinctNames(in: performers), ["MyGO!!!!!", "sumimi"])
  }
}
