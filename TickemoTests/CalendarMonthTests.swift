import XCTest
@testable import Tickemo

final class CalendarMonthTests: XCTestCase {
  func testEveryMonthHasExactly42Cells() {
    for month in 1...12 {
      let calendarMonth = CalendarMonth.make(year: 2026, month: month)
      let totalCells = calendarMonth.weeks.reduce(0) { $0 + $1.count }
      XCTAssertEqual(totalCells, 42, "month \(month) should have 42 cells")
      XCTAssertEqual(calendarMonth.weeks.count, 6)
      calendarMonth.weeks.forEach { XCTAssertEqual($0.count, 7) }
    }
  }

  func testLeadingBlanksMatchFirstWeekday() {
    // January 1, 2026 is a Thursday (UTC) -> 4 leading blanks (Sun=0...Thu=4).
    let january = CalendarMonth.make(year: 2026, month: 1)
    let flat = january.weeks.flatMap { $0 }
    let firstNonBlankIndex = flat.firstIndex { $0.date != nil }
    XCTAssertEqual(firstNonBlankIndex, 4)
    XCTAssertEqual(flat[4].dateString, "2026-01-01")
  }

  func testMonthWithSundayFirstHasNoLeadingBlanks() {
    // March 1, 2026 is a Sunday (UTC).
    let march = CalendarMonth.make(year: 2026, month: 3)
    let flat = march.weeks.flatMap { $0 }
    XCTAssertEqual(flat[0].dateString, "2026-03-01")
  }

  func testNonLeapFebruaryHas28Days() {
    let february = CalendarMonth.make(year: 2026, month: 2)
    let realDays = february.weeks.flatMap { $0 }.filter { $0.date != nil }
    XCTAssertEqual(realDays.count, 28)
  }

  func testAddingMonthsCrossesYearBoundary() {
    let december = CalendarMonth.make(year: 2025, month: 12)
    let next = december.adding(months: 1)
    XCTAssertEqual(next.year, 2026)
    XCTAssertEqual(next.month, 1)

    let january = CalendarMonth.make(year: 2026, month: 1)
    let previous = january.adding(months: -1)
    XCTAssertEqual(previous.year, 2025)
    XCTAssertEqual(previous.month, 12)
  }

  func testMonthTitleFormat() {
    let month = CalendarMonth.make(year: 2026, month: 8)
    XCTAssertEqual(month.monthTitle, "August 2026")
  }
}
