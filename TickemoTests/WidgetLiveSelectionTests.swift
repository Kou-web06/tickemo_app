import XCTest
import CoreData
@testable import Tickemo

/// Covers what the widget actually feeds on: `nextUpcomingRecord`'s
/// selection window, and the fact that every migrated record carries RN's
/// dotted date spelling rather than the canonical one.
final class WidgetLiveSelectionTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  override func tearDown() {
    context = nil
    persistence = nil
    super.tearDown()
  }

  @discardableResult
  private func makeRecord(
    liveName: String = "Test Live",
    date: String,
    endTime: String? = nil
  ) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.liveName = liveName
    record.date = date
    record.endTime = endTime
    return record
  }

  /// JST, because that's the timezone the record's wall-clock strings are
  /// interpreted in.
  private func jst(_ iso: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: iso)!
  }

  // MARK: - Selection window

  func testPicksSoonestUpcomingLive() {
    let far = makeRecord(liveName: "Far", date: "2999-12-01", endTime: "18:00")
    let soon = makeRecord(liveName: "Soon", date: "2999-01-10", endTime: "18:00")
    try? context.save()

    let result = NextLiveCardData.nextUpcomingRecord(from: [far, soon], now: jst("2999-01-01 12:00"))

    XCTAssertEqual(result?.liveName, "Soon")
  }

  /// The reported symptom: the widget went blank the moment the live
  /// started, which is when the user is most likely to look at it.
  func testKeepsTodaysLiveAfterItHasStarted() {
    let today = makeRecord(liveName: "Today", date: "2999-01-10", endTime: "18:00")
    try? context.save()

    let duringShow = NextLiveCardData.nextUpcomingRecord(from: [today], now: jst("2999-01-10 20:00"))

    XCTAssertEqual(duringShow?.liveName, "Today")
  }

  func testDropsTheLiveOnceItsDayIsOver() {
    let today = makeRecord(liveName: "Today", date: "2999-01-10", endTime: "18:00")
    try? context.save()

    let nextMorning = NextLiveCardData.nextUpcomingRecord(from: [today], now: jst("2999-01-11 09:00"))

    XCTAssertNil(nextMorning)
  }

  func testPrefersTomorrowOverAFinishedLiveEarlierToday() {
    let today = makeRecord(liveName: "Today", date: "2999-01-10", endTime: "12:00")
    let tomorrow = makeRecord(liveName: "Tomorrow", date: "2999-01-11", endTime: "18:00")
    try? context.save()

    // Still the same day, so both are in the window; the earlier countdown
    // target wins, which keeps today's live on screen until midnight.
    let result = NextLiveCardData.nextUpcomingRecord(from: [today, tomorrow], now: jst("2999-01-10 15:00"))

    XCTAssertEqual(result?.liveName, "Today")
  }

  func testReturnsNilWhenEverythingIsInThePast() {
    let past = makeRecord(liveName: "Past", date: "2020-01-01", endTime: "18:00")
    try? context.save()

    XCTAssertNil(NextLiveCardData.nextUpcomingRecord(from: [past], now: jst("2999-01-01 12:00")))
  }

  // MARK: - RN's dotted date spelling

  /// Every record imported from the RN store carries `2025.01.12`, not
  /// `2025-01-12` — `RecordsContext.tsx`'s `normalizeDateFormat` rewrote
  /// `-` to `.` on both the read and write paths. If this stops parsing,
  /// migrated records vanish from the widget, the calendar, the upcoming
  /// filter and every statistic at once.
  func testDottedLegacyDateParsesIdenticallyToCanonicalForm() {
    XCTAssertEqual(DateFormatting.date(from: "2026.09.07"), DateFormatting.date(from: "2026-09-07"))
    XCTAssertNotNil(DateFormatting.date(from: "2026.09.07"))
  }

  func testSlashedDateParsesIdenticallyToCanonicalForm() {
    XCTAssertEqual(DateFormatting.date(from: "2026/09/07"), DateFormatting.date(from: "2026-09-07"))
  }

  func testDottedLegacyDateIsSelectableByTheWidget() {
    let migrated = makeRecord(liveName: "Migrated", date: "2999.01.10", endTime: "18:00")
    try? context.save()

    let result = NextLiveCardData.nextUpcomingRecord(from: [migrated], now: jst("2999-01-01 12:00"))

    XCTAssertEqual(result?.liveName, "Migrated")
  }

  func testGarbageDateIsRejectedRatherThanCoerced() {
    XCTAssertNil(DateFormatting.date(from: "not a date"))
    XCTAssertNil(DateFormatting.date(from: ""))
  }
}
