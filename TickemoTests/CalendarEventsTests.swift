import XCTest
import CoreData
@testable import Tickemo

final class CalendarEventsTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  private func makeRecord(date: String, withCoverImage: Bool = false) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.date = date
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

  private var today: Date {
    DateFormatting.date(from: "2026-06-15")!
  }

  func testPastAndFutureBoundary() {
    let pastRecord = makeRecord(date: "2026-06-14")
    let futureRecord = makeRecord(date: "2026-06-15") // same day as "today" counts as future/upcoming
    try? context.save()

    let events = CalendarEvents.eventsByDate(records: [pastRecord, futureRecord], today: today)

    XCTAssertEqual(events["2026-06-14"]?.type, .past)
    XCTAssertEqual(events["2026-06-15"]?.type, .future)
  }

  func testKeysAreRawDateStrings() {
    let record = makeRecord(date: "2026-06-14")
    try? context.save()

    let events = CalendarEvents.eventsByDate(records: [record], today: today)
    let recordsByDate = CalendarEvents.recordsByDate(records: [record])

    XCTAssertNotNil(events["2026-06-14"])
    XCTAssertNotNil(recordsByDate["2026-06-14"])
  }

  func testRecordsByDateGroupsMultipleRecordsOnSameDay() {
    let first = makeRecord(date: "2026-06-14")
    let second = makeRecord(date: "2026-06-14")
    try? context.save()

    let recordsByDate = CalendarEvents.recordsByDate(records: [first, second])

    XCTAssertEqual(recordsByDate["2026-06-14"]?.count, 2)
  }

  func testEventsByDatePicksFirstAvailableCoverImage() {
    let withoutImage = makeRecord(date: "2026-06-14", withCoverImage: false)
    let withImage = makeRecord(date: "2026-06-14", withCoverImage: true)
    try? context.save()

    let events = CalendarEvents.eventsByDate(records: [withoutImage, withImage], today: today)

    XCTAssertNotNil(events["2026-06-14"]?.coverImageData)
  }

  func testRecordsWithoutADateAreIgnored() {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.liveName = "No Date"
    try? context.save()

    let events = CalendarEvents.eventsByDate(records: [record], today: today)
    let recordsByDate = CalendarEvents.recordsByDate(records: [record])

    XCTAssertTrue(events.isEmpty)
    XCTAssertTrue(recordsByDate.isEmpty)
  }
}
