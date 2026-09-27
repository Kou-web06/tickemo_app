import XCTest
import CoreData
@testable import Tickemo

final class TicketScheduleTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  private func makeRecord(
    liveName: String = "Test Live",
    seat: String? = nil,
    apply: String? = nil,
    payment: String? = nil
  ) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.liveName = liveName
    record.date = "2026-12-24"
    record.seatAnnounceAt = seat
    record.ticketApplyAt = apply
    record.paymentDueAt = payment
    return record
  }

  private func jst(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
  }

  // MARK: - entry / entries

  func testEntryInterpretsStoredValueAsJapanWallClock() {
    let entry = TicketSchedule.entry(.paymentDue, raw: "2026-10-01 23:59")
    XCTAssertEqual(entry?.dateString, "2026-10-01")
    XCTAssertEqual(entry?.timeString, "23:59")
    XCTAssertEqual(entry?.instant, jst("2026-10-01 23:59"))
  }

  func testEntryIgnoresEmptyOrBrokenValues() {
    XCTAssertNil(TicketSchedule.entry(.seatAnnounce, raw: nil))
    XCTAssertNil(TicketSchedule.entry(.seatAnnounce, raw: ""))
    XCTAssertNil(TicketSchedule.entry(.seatAnnounce, raw: "2026-10-01"))
  }

  func testEntriesAreSortedByTimeAndSkipMissingKinds() {
    let record = makeRecord(seat: "2026-12-20 12:00", apply: "2026-10-01 10:00")
    XCTAssertEqual(TicketSchedule.entries(for: record).map(\.kind), [.ticketApply, .seatAnnounce])
  }

  func testRawValueRoundTrip() {
    let record = makeRecord()
    TicketSchedule.setRawValue("2026-11-01 18:00", .paymentDue, of: record)
    XCTAssertEqual(record.paymentDueAt, "2026-11-01 18:00")
    XCTAssertEqual(TicketSchedule.rawValue(.paymentDue, of: record), "2026-11-01 18:00")
    TicketSchedule.setRawValue(nil, .paymentDue, of: record)
    XCTAssertNil(record.paymentDueAt)
  }

  func testDateTimeFormattingRoundTripIsTimezoneIndependent() {
    let date = DateFormatting.dateTime(from: "2026-01-02 03:04")!
    XCTAssertEqual(DateFormatting.dateTimeString(from: date), "2026-01-02 03:04")
  }

  // MARK: - Calendar

  func testItemsByDateGroupsSchedulesOnTheirOwnDays() {
    let a = makeRecord(liveName: "A", apply: "2026-10-01 10:00", payment: "2026-10-05 23:59")
    let b = makeRecord(liveName: "B", seat: "2026-10-01 09:00")

    let map = TicketSchedule.itemsByDate(records: [a, b])
    XCTAssertEqual(Set(map.keys), ["2026-10-01", "2026-10-05"])
    XCTAssertEqual(map["2026-10-01"]?.map(\.record.liveName), ["B", "A"])
    XCTAssertEqual(map["2026-10-01"]?.map(\.entry.kind), [.seatAnnounce, .ticketApply])
    XCTAssertEqual(map["2026-10-05"]?.first?.entry.kind, .paymentDue)
  }

  // MARK: - Reminders

  func testSeatAnnounceFiresAtTheTime() {
    let entry = TicketSchedule.entry(.seatAnnounce, raw: "2026-12-20 12:00")!
    let reminders = TicketSchedule.reminders(for: entry, liveName: "X")
    XCTAssertEqual(reminders.map(\.fireDate), [jst("2026-12-20 12:00")])
  }

  func testTicketApplyFiresThirtyMinutesBefore() {
    let entry = TicketSchedule.entry(.ticketApply, raw: "2026-10-01 10:00")!
    let reminders = TicketSchedule.reminders(for: entry, liveName: "X")
    XCTAssertEqual(reminders.map(\.fireDate), [jst("2026-10-01 09:30")])
  }

  func testPaymentDueFiresDayBeforeAtSevenPMAndThreeHoursBefore() {
    let entry = TicketSchedule.entry(.paymentDue, raw: "2026-10-05 23:59")!
    let reminders = TicketSchedule.reminders(for: entry, liveName: "X")
    XCTAssertEqual(reminders.map(\.fireDate), [jst("2026-10-04 19:00"), jst("2026-10-05 20:59")])
    // 同じ公演・同じ種類でも通知の識別子が衝突しないこと
    XCTAssertEqual(Set(reminders.map(\.suffix)).count, 2)
  }

  // MARK: - Notification settings

  func testTicketScheduleKindsArePlusOnly() {
    for kind in TicketScheduleKind.allCases {
      XCTAssertTrue(LiveNotificationSettings.Kind(kind).isPlusOnly)
    }
    XCTAssertFalse(LiveNotificationSettings.Kind.beforeLive.isPlusOnly)
  }
}
