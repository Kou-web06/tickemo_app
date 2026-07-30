import XCTest
@testable import Tickemo

final class JoinedDateFormattingTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private func isoString(secondsBeforeNow: TimeInterval) -> String {
    isoFormatter.string(from: now.addingTimeInterval(-secondsBeforeNow))
  }

  func testNilOrEmptyReturnsDash() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: nil, now: now), "-")
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: "", now: now), "-")
  }

  func testUnparseableStringPassesThroughRaw() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: "not-a-date", now: now), "not-a-date")
  }

  func testUnder60SecondsClampsToOneMinuteAgo() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: isoString(secondsBeforeNow: 30), now: now), "1m ago")
  }

  func testMinutesAgo() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: isoString(secondsBeforeNow: 5 * 60), now: now), "5m ago")
  }

  func testHoursAgo() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: isoString(secondsBeforeNow: 3 * 3600), now: now), "3h ago")
  }

  func testDaysAgo() {
    XCTAssertEqual(JoinedDateFormatting.relativeString(from: isoString(secondsBeforeNow: 10 * 86400), now: now), "10d ago")
  }

  func testBeyond30DaysUsesAbsoluteDate() {
    let result = JoinedDateFormatting.relativeString(from: isoString(secondsBeforeNow: 45 * 86400), now: now)
    XCTAssertTrue(result.contains("/"), "expected an absolute YYYY/MM/DD date, got \(result)")
    XCTAssertFalse(result.contains("ago"))
  }
}
