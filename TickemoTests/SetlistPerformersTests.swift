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

  // MARK: - defaultForNewSong

  /// 元のバグ: カバー曲の次に別アーティスト本来の曲を足しても、出演者欄が
  /// カバー曲の演者のまま引き継がれてしまっていた。曲の音源アーティストが
  /// 出演者候補に一致するなら、直前の曲より優先してそちらを使う。
  func testDefaultForNewSongPrefersTheSongsOwnArtistOverThePreviousPerformer() {
    let result = SetlistPerformers.defaultForNewSong(
      songArtist: "MyGO!!!!!",
      priorPerformers: ["sumimi"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(result, "MyGO!!!!!")
  }

  func testDefaultForNewSongMatchesCaseInsensitivelyAndAdoptsTheRegisteredSpelling() {
    let result = SetlistPerformers.defaultForNewSong(
      songArtist: " mygo!!!!! ",
      priorPerformers: [],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(result, "MyGO!!!!!")
  }

  /// カバー曲（音源のアーティストが出演者候補のどれとも一致しない）は
  /// 直前の曲の出演者を引き継ぐ — 交互演奏で切り替わる行だけピッカーを
  /// 触ればいいようにするため。
  func testDefaultForNewSongFallsBackToThePreviousPerformerForCovers() {
    let result = SetlistPerformers.defaultForNewSong(
      songArtist: "Roselia",
      priorPerformers: ["sumimi", "MyGO!!!!!"],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(result, "MyGO!!!!!")
  }

  func testDefaultForNewSongFallsBackToTheFirstCandidateWhenNothingElseMatches() {
    let result = SetlistPerformers.defaultForNewSong(
      songArtist: "Roselia",
      priorPerformers: [],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(result, "sumimi")
  }

  func testDefaultForNewSongIsNilWhenNoPerformersAreRegistered() {
    XCTAssertNil(SetlistPerformers.defaultForNewSong(songArtist: "sumimi", priorPerformers: [], artistNames: []))
  }

  // MARK: - canonical / soleArtist

  func testCanonicalMatchesRegisteredArtistsCaseInsensitivelyAndAdoptsTheirSpelling() {
    XCTAssertEqual(
      SetlistPerformers.canonical(" mygo!!!!! ", artistNames: ["sumimi", "MyGO!!!!!"]),
      "MyGO!!!!!"
    )
  }

  func testCanonicalDropsNamesThatAreNoLongerRegistered() {
    XCTAssertNil(SetlistPerformers.canonical("Roselia", artistNames: ["sumimi", "MyGO!!!!!"]))
    XCTAssertNil(SetlistPerformers.canonical("sumimi", artistNames: []))
    XCTAssertNil(SetlistPerformers.canonical(nil, artistNames: ["sumimi"]))
  }

  func testSoleArtistOnlyResolvesWhenExactlyOneArtistIsNamed() {
    XCTAssertEqual(SetlistPerformers.soleArtist(in: [" sumimi ", "  "]), "sumimi")
    XCTAssertNil(SetlistPerformers.soleArtist(in: ["sumimi", "MyGO!!!!!"]))
    XCTAssertNil(SetlistPerformers.soleArtist(in: []))
  }

  // MARK: - displayName

  /// 曲カードに出す名前は「実際に演奏した人」を優先する。カバー曲だと
  /// 音源のアーティストと食い違うので、ここでどちらを採るかが効く。
  func testDisplayNamePrefersThePerformerOverTheSongArtist() {
    XCTAssertEqual(
      SetlistPerformers.displayName(performer: "sumimi", songArtist: "MyGO!!!!!"),
      "sumimi"
    )
  }

  func testDisplayNameFallsBackToTheSongArtistWhenNoPerformerIsAssigned() {
    XCTAssertEqual(
      SetlistPerformers.displayName(performer: nil, songArtist: "MyGO!!!!!"),
      "MyGO!!!!!"
    )
  }

  func testDisplayNameTreatsBlanksAsAbsent() {
    XCTAssertEqual(
      SetlistPerformers.displayName(performer: "  ", songArtist: " MyGO!!!!! "),
      "MyGO!!!!!"
    )
    XCTAssertNil(SetlistPerformers.displayName(performer: nil, songArtist: "   "))
  }

  func testDisplayNameIsNilWhenNeitherIsKnown() {
    XCTAssertNil(SetlistPerformers.displayName(performer: nil, songArtist: nil))
  }
}
