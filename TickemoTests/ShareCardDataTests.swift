import XCTest
import CoreData
@testable import Tickemo

final class ShareCardDataTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  @discardableResult
  private func makeRecord(artist: String? = nil, date: String = "2024-01-01") -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.artist = artist
    record.date = date
    record.liveName = "Test Live"
    return record
  }

  @discardableResult
  private func makeSetlistItem(
    kind: String = "song",
    songName: String? = nil,
    artistName: String? = nil,
    performerName: String? = nil,
    title: String? = nil,
    orderIndex: Int32 = 0,
    for record: CD_ChekiRecord
  ) -> CD_SetlistItem {
    let item = CD_SetlistItem(context: context)
    item.id = UUID()
    item.kind = kind
    item.songName = songName
    item.artistName = artistName
    item.performerName = performerName
    item.title = title
    item.orderIndex = orderIndex
    item.record = record
    return item
  }

  // MARK: - digitsPaddedOrTruncated

  func testDigitsPaddedOrTruncatedHandlesEmptyString() {
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated("", length: 8), "00000000")
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated(nil, length: 4), "0000")
  }

  func testDigitsPaddedOrTruncatedStripsNonDigits() {
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated("2024-05-10", length: 8), "20240510")
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated("18:00", length: 4), "1800")
  }

  func testDigitsPaddedOrTruncatedTruncatesWhenTooLong() {
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated("202405101230", length: 8), "20240510")
  }

  func testDigitsPaddedOrTruncatedPadsWhenTooShort() {
    XCTAssertEqual(ShareCardData.digitsPaddedOrTruncated("5", length: 4), "5000")
  }

  // MARK: - cdBusinessCode

  func testCdBusinessCodeExactFormat() {
    let code = ShareCardData.cdBusinessCode(date: "2024-05-10", startTime: "18:00", songCount: 7)
    XCTAssertEqual(code, "No. 20240510-1800-07")
  }

  // MARK: - cdSetlistLines

  func testCdSetlistLinesNumbersSongsSequentially() {
    let record = makeRecord()
    makeSetlistItem(songName: "Song A", orderIndex: 0, for: record)
    makeSetlistItem(songName: "Song B", orderIndex: 1, for: record)
    makeSetlistItem(songName: "Song C", orderIndex: 2, for: record)
    try? context.save()

    let lines = ShareCardData.cdSetlistLines(items: record.sortedSetlistItems)

    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0].kind, .song(index: 1, name: "Song A"))
    XCTAssertEqual(lines[1].kind, .song(index: 2, name: "Song B"))
    XCTAssertEqual(lines[2].kind, .song(index: 3, name: "Song C"))
  }

  func testCdSetlistLinesInsertsEncoreSpacerAndLabelWithoutAffectingSongIndex() {
    let record = makeRecord()
    makeSetlistItem(songName: "Song A", orderIndex: 0, for: record)
    makeSetlistItem(kind: "encore", orderIndex: 1, for: record)
    makeSetlistItem(songName: "Song B", orderIndex: 2, for: record)
    try? context.save()

    let lines = ShareCardData.cdSetlistLines(items: record.sortedSetlistItems)

    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(lines[0].kind, .song(index: 1, name: "Song A"))
    XCTAssertEqual(lines[1].kind, .encoreSpacer)
    XCTAssertEqual(lines[2].kind, .encoreLabel)
    XCTAssertEqual(lines[3].kind, .song(index: 2, name: "Song B"))
  }

  func testCdSetlistLinesExcludesMcItems() {
    let record = makeRecord()
    makeSetlistItem(kind: "mc", title: "MC Talk", orderIndex: 0, for: record)
    try? context.save()

    XCTAssertTrue(ShareCardData.cdSetlistLines(items: record.sortedSetlistItems).isEmpty)
  }

  // MARK: - isEncoreMarkerText

  func testIsEncoreMarkerTextRecognizesVariants() {
    XCTAssertTrue(ShareCardData.isEncoreMarkerText("Encore"))
    XCTAssertTrue(ShareCardData.isEncoreMarkerText("[ENCORE]"))
    XCTAssertTrue(ShareCardData.isEncoreMarkerText("-- encore --"))
    XCTAssertTrue(ShareCardData.isEncoreMarkerText("アンコール"))
    XCTAssertTrue(ShareCardData.isEncoreMarkerText("　アンコール　"))
  }

  func testIsEncoreMarkerTextRejectsNonMarkers() {
    XCTAssertFalse(ShareCardData.isEncoreMarkerText("MC Talk"))
    XCTAssertFalse(ShareCardData.isEncoreMarkerText(""))
    XCTAssertFalse(ShareCardData.isEncoreMarkerText(nil))
  }

  // MARK: - receiptRows compression

  private func makeSongs(count: Int, in record: CD_ChekiRecord) {
    for i in 0..<count {
      makeSetlistItem(songName: "Song \(i + 1)", orderIndex: Int32(i), for: record)
    }
  }

  func testReceiptRowsExactlyTwentySongsShowsNoEllipsis() {
    let record = makeRecord()
    makeSongs(count: 20, in: record)
    try? context.save()

    let rows = ShareCardData.receiptRows(setlistItems: record.sortedSetlistItems)

    XCTAssertEqual(rows.count, 20)
    XCTAssertFalse(rows.contains { if case .ellipsis = $0 { true } else { false } })
  }

  func testReceiptRowsTwentyOneSongsCompressesWithEllipsis() {
    let record = makeRecord()
    makeSongs(count: 21, in: record)
    try? context.save()

    let rows = ShareCardData.receiptRows(setlistItems: record.sortedSetlistItems)

    // 10 head songs + 1 ellipsis + 10 tail songs = 21 rows, dropping exactly 1 song.
    XCTAssertEqual(rows.count, 21)
    guard case .song(_, let firstName, _) = rows[0] else { return XCTFail("expected a song row") }
    XCTAssertEqual(firstName, "Song 1")
    guard case .ellipsis = rows[10] else { return XCTFail("expected the ellipsis at index 10") }
    guard case .song(_, let lastName, _) = rows[20] else { return XCTFail("expected a song row") }
    XCTAssertEqual(lastName, "Song 21")
  }

  func testReceiptRowsEncoreAtBoundaryIsDroppedWithMiddleSongs() {
    let record = makeRecord()
    for i in 0..<10 {
      makeSetlistItem(songName: "Song \(i + 1)", orderIndex: Int32(i), for: record)
    }
    makeSetlistItem(kind: "encore", orderIndex: 10, for: record)
    for i in 10..<21 {
      makeSetlistItem(songName: "Song \(i + 1)", orderIndex: Int32(i + 1), for: record)
    }
    try? context.save()

    let rows = ShareCardData.receiptRows(setlistItems: record.sortedSetlistItems)

    // The encore marker sits right after the 10th song, i.e. exactly where
    // the head slice stops (head stops as soon as 10 songs are consumed,
    // BEFORE appending anything further) — so it must be dropped, not kept.
    XCTAssertFalse(rows.contains { if case .encoreMarker = $0 { true } else { false } })
  }

  // MARK: - receiptArtistLabel / hasMultipleDistinctSongArtists

  func testReceiptArtistLabelJoinsDistinctSongArtists() {
    let record = makeRecord(artist: "Fallback Artist")
    makeSetlistItem(songName: "Song A", artistName: "Artist One", orderIndex: 0, for: record)
    makeSetlistItem(songName: "Song B", artistName: "Artist Two", orderIndex: 1, for: record)
    makeSetlistItem(songName: "Song C", artistName: "Artist One", orderIndex: 2, for: record)
    try? context.save()

    let label = ShareCardData.receiptArtistLabel(setlistItems: record.sortedSetlistItems, fallbackArtist: record.artist)

    XCTAssertEqual(label, "Artist One / Artist Two")
    XCTAssertTrue(ShareCardData.hasMultipleDistinctSongArtists(setlistItems: record.sortedSetlistItems))
  }

  func testReceiptArtistLabelFallsBackToRecordArtistWhenNoSongArtists() {
    let record = makeRecord(artist: "Fallback Artist")
    makeSetlistItem(songName: "Song A", artistName: nil, orderIndex: 0, for: record)
    try? context.save()

    let label = ShareCardData.receiptArtistLabel(setlistItems: record.sortedSetlistItems, fallbackArtist: record.artist)

    XCTAssertEqual(label, "Fallback Artist")
    XCTAssertFalse(ShareCardData.hasMultipleDistinctSongArtists(setlistItems: record.sortedSetlistItems))
  }

  func testReceiptArtistLabelUsesPerformerOverSourceArtistForCovers() {
    let record = makeRecord(artist: "Fallback Artist")
    // カバー曲: 音源のアーティストは原曲側、実際に歌ったのは出演者側。
    makeSetlistItem(songName: "Cover Song", artistName: "Original Band", performerName: "Cover Idol", orderIndex: 0, for: record)
    makeSetlistItem(songName: "Own Song", artistName: "Cover Idol", orderIndex: 1, for: record)
    try? context.save()

    let label = ShareCardData.receiptArtistLabel(setlistItems: record.sortedSetlistItems, fallbackArtist: record.artist)

    XCTAssertEqual(label, "Cover Idol")
    XCTAssertFalse(ShareCardData.hasMultipleDistinctSongArtists(setlistItems: record.sortedSetlistItems))
  }

  func testReceiptRowsCreditCoverSongToPerformerNotOriginalArtist() {
    let record = makeRecord(artist: "Fallback Artist")
    makeSetlistItem(songName: "Song A", artistName: "Band A", performerName: "Band A", orderIndex: 0, for: record)
    makeSetlistItem(songName: "Cover Of X", artistName: "Original X", performerName: "Band B", orderIndex: 1, for: record)
    try? context.save()

    let rows = ShareCardData.receiptRows(setlistItems: record.sortedSetlistItems)

    guard case .song(_, let firstName, _) = rows[0] else { return XCTFail("expected a song row") }
    guard case .song(_, let secondName, _) = rows[1] else { return XCTFail("expected a song row") }
    XCTAssertEqual(firstName, "Song A - Band A")
    XCTAssertEqual(secondName, "Cover Of X - Band B")
  }

  func testReceiptArtistLabelExcludesWhitespaceOnlyValues() {
    let record = makeRecord(artist: "Fallback Artist")
    makeSetlistItem(songName: "Song A", artistName: "   ", orderIndex: 0, for: record)
    try? context.save()

    XCTAssertEqual(
      ShareCardData.receiptArtistLabel(setlistItems: record.sortedSetlistItems, fallbackArtist: record.artist),
      "Fallback Artist"
    )
  }

  // MARK: - shareCreditHandle

  func testShareCreditHandleDefaultsWhenNil() {
    XCTAssertEqual(ShareCardData.shareCreditHandle(username: nil), "@tickemo_user")
  }

  func testShareCreditHandlePrependsAt() {
    XCTAssertEqual(ShareCardData.shareCreditHandle(username: "foo"), "@foo")
  }

  func testShareCreditHandleAvoidsDoubleAt() {
    XCTAssertEqual(ShareCardData.shareCreditHandle(username: "@foo"), "@foo")
  }

  func testShareCreditHandleTrimsWhitespace() {
    XCTAssertEqual(ShareCardData.shareCreditHandle(username: "  foo  "), "@foo")
  }

  // MARK: - cdBarcodeBars

  func testCdBarcodeBarsGeometrySanity() {
    XCTAssertEqual(ShareCardData.cdBarcodeBars.count, 30)
    for bar in ShareCardData.cdBarcodeBars {
      XCTAssertGreaterThanOrEqual(bar.rightEdgeX - bar.thickness, 0)
    }
  }

  // MARK: - systemShareCaptionText

  func testSystemShareCaptionTextUsesSingularArtistField() {
    let text = ShareCardData.systemShareCaptionText(date: "2024-05-10", artist: "Solo Artist", liveName: "Big Show")
    XCTAssertEqual(text, "2024-05-10 Solo Artist - Big Show \n #Tickemo")
  }
}
