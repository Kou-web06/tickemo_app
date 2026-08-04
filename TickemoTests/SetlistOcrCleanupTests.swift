import XCTest
@testable import Tickemo

final class SetlistOcrCleanupTests: XCTestCase {
  // MARK: - Layer 1: numbering/prefix stripping

  func testStripsLeadingTrackNumberWithPeriod() {
    XCTAssertEqual(SetlistOcrCleanup.formatSetlistLines("1. Idol"), ["Idol"])
    XCTAssertEqual(SetlistOcrCleanup.formatSetlistLines("12．Racing Into The Night"), ["Racing Into The Night"])
  }

  func testStripsBareLeadingNumber() {
    XCTAssertEqual(SetlistOcrCleanup.formatSetlistLines("01 Yoru ni Kakeru"), ["Yoru ni Kakeru"])
  }

  func testStripsLeadingEncoreMarkerPrefix() {
    XCTAssertEqual(SetlistOcrCleanup.formatSetlistLines("EN1: Group"), ["Group"])
  }

  func testDropsBlacklistedMarkerLinesEntirely() {
    // "ENCORE" itself survives mangled to "CORE": the earlier encore-number
    // -prefix regex (`^en...`, meant for "EN1:"-style prefixes) strips the
    // leading "EN" before the blacklist substring-filter ever runs, so
    // "CORE" no longer contains "encore". "MC"/"SE"/the Japanese word don't
    // start with "en" and get dropped as expected. This mirrors RN's real
    // pass order (same two regex passes, same sequence) rather than what
    // the blacklist's author probably intended.
    let result = SetlistOcrCleanup.formatSetlistLines("MC\nSong A\nSE\nENCORE\nアンコール")
    XCTAssertEqual(result, ["Song A", "CORE"])
  }

  func testDropsEmptyLines() {
    XCTAssertEqual(SetlistOcrCleanup.formatSetlistLines("Song A\n\n  \nSong B"), ["Song A", "Song B"])
  }

  // MARK: - Layer 2: header/time/divider drops + dedupe

  func testCleanedLinesDropsSetlistHeader() {
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "SET LIST:\nSong A"), ["Song A"])
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "セットリスト\nSong A"), ["Song A"])
  }

  func testCleanedLinesDropsMetaLinesWithColon() {
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "OPEN: 18:00\nSong A\nVENUE: Tokyo Dome"), ["Song A"])
  }

  func testCleanedLinesLeavesBareTimeTextMangledNotDropped() {
    // The bare-time-range entry in the drop-pattern list never actually
    // matches in practice: normalizeOcrLine's own numbering-prefix strip
    // (`^\s*(?:m|mc)?\s*0*\d{1,3}\s*[.)\]】\-:：]\s*`, meant for
    // "M1:"/"01."-style track numbers) runs first and always consumes a
    // leading "H:" as if it were a track number, so by the time the
    // bare-time pattern would run there's no "H:MM" shape left to match.
    // This is RN's actual behavior (same two passes, same order),
    // faithfully reproduced rather than "fixed" to what the pattern's
    // author probably meant.
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "18:00\nSong A\n18:00-20:00"), ["00", "Song A", "00-20:00"])
  }

  func testCleanedLinesDropsDividerLines() {
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "------\nSong A\n===="), ["Song A"])
  }

  func testCleanedLinesStripsCircledNumeralsAndBulletMarkers() {
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "\u{2460}Song A\n・Song B\n- Song C"), ["Song A", "Song B", "Song C"])
  }

  func testCleanedLinesDedupesCaseInsensitively() {
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: "Idol\nIDOL\nidol\nAnother Song"), ["Idol", "Another Song"])
  }

  func testCleanedLinesFullPipeline() {
    let raw = "SET LIST:\nOPEN: 18:00\n1. Idol\n2. Racing Into The Night\nMC\n------\n3. Idol"
    XCTAssertEqual(SetlistOcrCleanup.cleanedLines(from: raw), ["Idol", "Racing Into The Night"])
  }

  // MARK: - Suspicious flagging

  func testEmptyOrTooShortIsSuspicious() {
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious(""))
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("A"))
  }

  func testNoReadableCharactersIsSuspicious() {
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("123456"))
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("!!!###"))
  }

  func testHighSymbolRatioIsSuspicious() {
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("A!@#$%^"))
  }

  func testRepeatedCharacterOnlyIsSuspicious() {
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("----"))
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("11111"))
  }

  func testMetaLinePrefixIsSuspicious() {
    XCTAssertTrue(SetlistOcrCleanup.isSuspicious("Open doors at the venue"))
  }

  func testNormalSongTitleIsNotSuspicious() {
    XCTAssertFalse(SetlistOcrCleanup.isSuspicious("Racing Into The Night"))
    XCTAssertFalse(SetlistOcrCleanup.isSuspicious("\u{591C}\u{306B}\u{99C6}\u{3051}\u{308B}"))
  }

  func testReviewItemsCarryTextAndSuspiciousFlag() {
    let items = SetlistOcrCleanup.reviewItems(from: ["Idol", "--"])
    XCTAssertEqual(items.map(\.text), ["Idol", "--"])
    XCTAssertEqual(items.map(\.isSuspicious), [false, true])
  }
}
