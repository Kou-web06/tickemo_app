import XCTest
import CoreData
@testable import Tickemo

final class NextLiveCardDataTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  @discardableResult
  private func makeRecord(liveName: String = "Test Live", artist: String? = nil, date: String, startTime: String? = nil) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.liveName = liveName
    record.artist = artist
    record.date = date
    record.startTime = startTime
    return record
  }

  // MARK: - nextLiveRecord selection

  func testNextLiveRecordPicksSoonestUpcomingByDateOnly() {
    let farFuture = makeRecord(liveName: "Far", date: "2999-12-01")
    let soonest = makeRecord(liveName: "Soonest", date: "2999-01-10")
    let past = makeRecord(liveName: "Past", date: "2020-01-01")
    try? context.save()

    let now = DateFormatting.date(from: "2999-01-01")!
    let result = NextLiveCardData.nextLiveRecord(from: [farFuture, soonest, past], now: now)

    XCTAssertEqual(result?.liveName, "Soonest")
  }

  func testNextLiveRecordFallsBackToMostRecentPastWhenNoneUpcoming() {
    let older = makeRecord(liveName: "Older", date: "2020-01-01")
    let mostRecent = makeRecord(liveName: "MostRecent", date: "2021-06-01")
    try? context.save()

    let now = DateFormatting.date(from: "2099-01-01")!
    let result = NextLiveCardData.nextLiveRecord(from: [older, mostRecent], now: now)

    XCTAssertEqual(result?.liveName, "MostRecent")
  }

  func testNextLiveRecordSelectionIsDateOnlyIgnoringStartTime() {
    // "Today" at a startTime that has already technically passed should
    // still count as upcoming for selection purposes — RN's own `toTime`
    // ignores startTime entirely, unlike `instant(for:)` below.
    let today = makeRecord(liveName: "TodayEarly", date: "2500-05-10", startTime: "09:00")
    try? context.save()

    let now = DateFormatting.utcCalendar.date(bySettingHour: 20, minute: 0, second: 0, of: DateFormatting.date(from: "2500-05-10")!)!
    let result = NextLiveCardData.nextLiveRecord(from: [today], now: now)

    XCTAssertEqual(result?.liveName, "TodayEarly")
  }

  // MARK: - instant(for:) / isPast — 18:00 default startTime

  func testInstantDefaultsToEighteenHundredWhenStartTimeAbsent() {
    let record = makeRecord(date: "2500-05-10", startTime: nil)
    try? context.save()

    let instant = NextLiveCardData.instant(for: record)
    let expected = DateFormatting.utcCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: DateFormatting.date(from: "2500-05-10")!)

    XCTAssertEqual(instant, expected)
  }

  func testIsPastUsesFullInstantNotDateOnly() {
    let record = makeRecord(date: "2500-05-10", startTime: "18:00")
    try? context.save()

    let beforeStartTime = DateFormatting.utcCalendar.date(bySettingHour: 10, minute: 0, second: 0, of: DateFormatting.date(from: "2500-05-10")!)!
    let afterStartTime = DateFormatting.utcCalendar.date(bySettingHour: 19, minute: 0, second: 0, of: DateFormatting.date(from: "2500-05-10")!)!

    XCTAssertFalse(NextLiveCardData.isPast(record, now: beforeStartTime))
    XCTAssertTrue(NextLiveCardData.isPast(record, now: afterStartTime))
  }

  // MARK: - countdownText formatting

  func testCountdownTextFormatsDaysHoursMinutesSecondsWithZeroPadding() {
    let record = makeRecord(date: "2500-05-10", startTime: "18:00")
    try? context.save()

    let target = NextLiveCardData.instant(for: record)!
    let now = target.addingTimeInterval(-(2 * 86400 + 5 * 3600 + 9 * 60 + 3))

    let (text, isMessage) = NextLiveCardData.countdownText(for: record, now: now)

    XCTAssertEqual(text, "2 : 05 : 09 : 03")
    XCTAssertFalse(isMessage)
  }

  func testCountdownTextShowsMessageOnceTargetHasPassed() {
    let record = makeRecord(date: "2020-01-01", startTime: "18:00")
    try? context.save()

    let now = DateFormatting.date(from: "2099-01-01")!
    let (text, isMessage) = NextLiveCardData.countdownText(for: record, now: now)

    XCTAssertEqual(text, "see you next live !!")
    XCTAssertTrue(isMessage)
  }
}
