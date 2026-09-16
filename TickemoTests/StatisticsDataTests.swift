import XCTest
import CoreData
@testable import Tickemo

final class StatisticsDataTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  @discardableResult
  private func makeRecord(
    artist: String? = nil,
    artistImageUrl: String? = nil,
    date: String,
    startTime: String? = nil,
    venue: String? = nil,
    ticketPrice: Double = 0,
    withCoverImage: Bool = false
  ) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.artist = artist
    record.artistImageUrl = artistImageUrl
    record.date = date
    record.startTime = startTime
    record.venue = venue
    record.ticketPrice = ticketPrice
    record.liveName = "Test Live"

    if withCoverImage {
      let image = CD_LiveImage(context: context)
      image.id = UUID()
      image.orderIndex = 0
      image.data = Data([0x00])
      image.record = record
    }

    return record
  }

  @discardableResult
  private func makeSetlistItem(
    kind: String = "song",
    songId: String? = nil,
    songName: String? = nil,
    artworkUrl: String? = nil,
    artistName: String? = nil,
    orderIndex: Int32 = 0,
    for record: CD_ChekiRecord
  ) -> CD_SetlistItem {
    let item = CD_SetlistItem(context: context)
    item.id = UUID()
    item.kind = kind
    item.songId = songId
    item.songName = songName
    item.artworkUrl = artworkUrl
    item.artistName = artistName
    item.orderIndex = orderIndex
    item.record = record
    return item
  }

  private func makeRecords(artist: String, count: Int, date: String) -> [CD_ChekiRecord] {
    (0..<count).map { _ in makeRecord(artist: artist, date: date) }
  }

  // MARK: - Top artists tie-expansion

  func testTieExpansionKeepsArtistsTiedAtThirdDistinctCount() {
    var records: [CD_ChekiRecord] = []
    records += makeRecords(artist: "A", count: 5, date: "2020-01-01")
    records += makeRecords(artist: "B", count: 5, date: "2020-01-02")
    records += makeRecords(artist: "C", count: 4, date: "2020-01-03")
    records += makeRecords(artist: "D", count: 3, date: "2020-01-04")
    records += makeRecords(artist: "E", count: 3, date: "2020-01-05")
    records += makeRecords(artist: "F", count: 3, date: "2020-01-06")
    records += makeRecords(artist: "G", count: 1, date: "2020-01-07")
    try? context.save()

    // Distinct counts desc: [5, 4, 3, 1] — the 3rd distinct value is 3, so
    // everyone with count >= 3 survives (A, B, C, D, E, F) and G (count 1)
    // is dropped, even though it's not literally "top 3 artists".
    let ranked = StatisticsData.topArtists(records)

    XCTAssertEqual(ranked.count, 6)
    XCTAssertFalse(ranked.contains { $0.name == "G" })
    let tiedAtThree = ranked.filter { $0.count == 3 }
    XCTAssertEqual(tiedAtThree.count, 3)
    XCTAssertTrue(tiedAtThree.allSatisfy { $0.rank == 3 })
    XCTAssertTrue(ranked.filter { $0.count == 5 }.allSatisfy { $0.rank == 1 })
    XCTAssertTrue(ranked.filter { $0.count == 4 }.allSatisfy { $0.rank == 2 })
  }

  func testTopArtistsKeepsAllWhenFewerThanThreeDistinctCounts() {
    var records: [CD_ChekiRecord] = []
    records += makeRecords(artist: "A", count: 4, date: "2020-01-01")
    records += makeRecords(artist: "B", count: 1, date: "2020-01-02")
    try? context.save()

    let ranked = StatisticsData.topArtists(records)

    XCTAssertEqual(ranked.count, 2)
  }

  // MARK: - Top venues hard truncation

  func testTopVenuesTruncatesToThreeAndDropsTiesAtCutoff() {
    var records: [CD_ChekiRecord] = []
    records += (0..<5).map { _ in makeRecord(date: "2020-01-01", venue: "Venue A") }
    records += (0..<4).map { _ in makeRecord(date: "2020-01-01", venue: "Venue B") }
    records += (0..<2).map { _ in makeRecord(date: "2020-01-01", venue: "Venue C") }
    records += (0..<2).map { _ in makeRecord(date: "2020-01-01", venue: "Venue D") }
    try? context.save()

    let ranked = StatisticsData.topVenues(records)

    XCTAssertEqual(ranked.count, 3, "only top 3 survive even though C and D tie at position 3")
    XCTAssertEqual(Set(ranked.map(\.name)), ["Venue A", "Venue B", "Venue C"], "tie broken by venue name ascending")
  }

  // MARK: - Monthly buckets

  func testMonthlyBucketsSumAcrossYearsIntoSameCalendarMonth() {
    let records = [
      makeRecord(date: "2019-03-10"),
      makeRecord(date: "2021-03-20"),
      makeRecord(date: "2022-07-01"),
    ]
    try? context.save()

    let buckets = StatisticsData.monthlyBuckets(records)

    XCTAssertEqual(buckets.count, 12)
    XCTAssertEqual(buckets[2].label, "Mar")
    XCTAssertEqual(buckets[2].count, 2)
    XCTAssertEqual(buckets[6].count, 1)
    XCTAssertEqual(buckets[0].count, 0, "months without any record still appear, at count 0")
  }

  // MARK: - Top songs grouping

  func testTopSongsGroupsBySongIdWhenPresentElseTrimmedLowercasedNameAndExcludesNonSongs() {
    let recordA = makeRecord(date: "2020-01-01")
    makeSetlistItem(songId: "id-1", songName: "Song One", for: recordA)
    makeSetlistItem(kind: "mc", songName: "MC Talk", for: recordA)

    let recordB = makeRecord(date: "2020-02-01")
    makeSetlistItem(songId: "id-1", songName: "Song One (Live)", for: recordB)
    makeSetlistItem(songName: " Song Two ", for: recordB)

    let recordC = makeRecord(date: "2020-03-01")
    makeSetlistItem(songName: "song two", for: recordC)
    try? context.save()

    let ranked = StatisticsData.topSongs([recordA, recordB, recordC])

    XCTAssertEqual(ranked.count, 2)
    let songOne = ranked.first { $0.id == "id-1" }
    XCTAssertEqual(songOne?.count, 2)
    let songTwo = ranked.first { $0.name.lowercased() == "song two" }
    XCTAssertEqual(songTwo?.count, 2, "grouped case-insensitively via trimmed/lowercased songName fallback")
    XCTAssertFalse(ranked.contains { $0.name == "MC Talk" })
  }

  func testTopSongsArtistNameKeepsFirstNonEmptyValueAndTrimsEmptyToNil() {
    let recordA = makeRecord(date: "2020-01-01")
    makeSetlistItem(songId: "id-1", songName: "Song One", artistName: "  ", for: recordA)

    let recordB = makeRecord(date: "2020-02-01")
    makeSetlistItem(songId: "id-1", songName: "Song One (Live)", artistName: "Artist A", for: recordB)

    let recordC = makeRecord(date: "2020-03-01")
    makeSetlistItem(songId: "id-1", songName: "Song One (Acoustic)", artistName: "Artist B", for: recordC)
    try? context.save()

    let ranked = StatisticsData.topSongs([recordA, recordB, recordC])

    let songOne = ranked.first { $0.id == "id-1" }
    XCTAssertEqual(songOne?.artistName, "Artist A", "first non-empty artistName wins; later rows never overwrite it")
  }

  func testTopSongsArtistNameNilWhenNeverProvided() {
    let record = makeRecord(date: "2020-01-01")
    makeSetlistItem(songId: "id-1", songName: "Song One", for: record)
    try? context.save()

    let ranked = StatisticsData.topSongs([record])

    XCTAssertNil(ranked.first { $0.id == "id-1" }?.artistName)
  }

  // MARK: - Total spending

  func testTotalSpendingViaYearFilterExcludesOtherYears() {
    let inYear = makeRecord(date: "2021-05-01", ticketPrice: 5000)
    let outOfYear = makeRecord(date: "2022-05-01", ticketPrice: 9000)
    try? context.save()

    let attended = StatisticsData.attendedRecords([inYear, outOfYear], now: DateFormatting.date(from: "2099-01-01")!)
    let filtered = StatisticsData.yearFiltered(attended, year: 2021)

    XCTAssertEqual(StatisticsData.totalSpending(filtered), 5000)
  }

  // MARK: - Summary case sensitivity asymmetry

  func testSummaryArtistsCaseInsensitiveVenuesCaseSensitive() {
    let records = [
      makeRecord(artist: "Yoasobi", date: "2020-01-01", venue: "Zepp Tokyo"),
      makeRecord(artist: "YOASOBI", date: "2020-02-01", venue: "zepp tokyo"),
    ]
    try? context.save()

    let summary = StatisticsData.summary(records)

    XCTAssertEqual(summary.totalArtists, 1)
    XCTAssertEqual(summary.totalVenues, 2)
  }

  // MARK: - All artists ordering and image selection

  func testAllArtistsSortsByLastLiveDescendingAndImageFollowsLatestRecord() {
    let oldest = makeRecord(artist: "Artist", artistImageUrl: "oldest-url", date: "2020-01-01")
    let middle = makeRecord(artist: "Artist", date: "2020-06-01")
    let newest = makeRecord(artist: "Artist", date: "2020-12-01")
    let other = makeRecord(artist: "Other Artist", date: "2020-03-01")
    try? context.save()

    let entries = StatisticsData.allArtists([oldest, middle, newest, other])

    XCTAssertEqual(entries.map(\.name), ["Artist", "Other Artist"])
    XCTAssertEqual(entries.first?.artistImageUrl, "oldest-url", "no image on the newest record falls back to the oldest record's artist photo")
  }

  /// `recordInstant` は日付と開演時刻を UTC の壁時計として組み立てるので、
  /// 整形側のタイムゾーンを固定し忘れると、UTC より進んだ地域（JST など）
  /// では夕方開演のチケットが翌日として表示される。実際 4/26 15:00 の
  /// チケットが "Apr 27, 2026" と出ていた。
  func testAllArtistsLastLiveDateIsNotShiftedByTheDeviceTimeZone() {
    let record = makeRecord(artist: "Artist", date: "2026-04-26", startTime: "15:00")
    try? context.save()

    let entries = StatisticsData.allArtists([record])

    XCTAssertEqual(entries.first?.lastLiveDateText, "Apr 26, 2026")
  }

  func testAllArtistsLastLiveDateIsNotLocalized() {
    let record = makeRecord(artist: "Artist", date: "2026-04-26")
    try? context.save()

    let entries = StatisticsData.allArtists([record])

    XCTAssertEqual(entries.first?.lastLiveDateText, "Apr 26, 2026")
  }

  // MARK: - Top artists image selection

  func testTopArtistsArtistImageUrlPicksFirstNonNilAcrossRecords() {
    var records: [CD_ChekiRecord] = []
    records.append(makeRecord(artist: "Artist", date: "2020-01-01"))
    records.append(makeRecord(artist: "Artist", artistImageUrl: "official-url", date: "2020-06-01"))
    try? context.save()

    let ranked = StatisticsData.topArtists(records)

    XCTAssertEqual(ranked.first?.artistImageUrl, "official-url")
  }

  // MARK: - Rank helper

  func testRankHelperSharesRankAcrossTiesAndSkipsGaps() {
    let counts = [10, 10, 7, 7, 7, 2]

    XCTAssertEqual(StatisticsData.rank(for: 10, among: counts), 1)
    XCTAssertEqual(StatisticsData.rank(for: 7, among: counts), 2)
    XCTAssertEqual(StatisticsData.rank(for: 2, among: counts), 3)
  }

  // MARK: - Filter pipeline

  func testAttendedRecordsExcludesFutureRecords() {
    let past = makeRecord(date: "2020-01-01")
    let future = makeRecord(date: "2999-01-01")
    try? context.save()

    let attended = StatisticsData.attendedRecords([past, future], now: DateFormatting.date(from: "2021-01-01")!)

    XCTAssertEqual(attended.map(\.objectID), [past.objectID])
  }

  func testYearFilteredNilReturnsAllRecords() {
    let a = makeRecord(date: "2020-01-01")
    let b = makeRecord(date: "2021-01-01")
    try? context.save()

    XCTAssertEqual(StatisticsData.yearFiltered([a, b], year: nil).count, 2)
    XCTAssertEqual(StatisticsData.yearFiltered([a, b], year: 2020).map(\.objectID), [a.objectID])
  }
}
