import XCTest
@testable import Tickemo

final class EarlyOfferServiceTests: XCTestCase {
  func testFormatZeroRemaining() {
    XCTAssertEqual(EarlyOfferService.format(remaining: 0), "00:00:00")
  }

  func testFormatHoursMinutesSeconds() {
    XCTAssertEqual(EarlyOfferService.format(remaining: 3661), "01:01:01")
  }

  func testFormatRoundsDownFractionalSeconds() {
    XCTAssertEqual(EarlyOfferService.format(remaining: 59.9), "00:00:59")
  }

  func testFormatBeyondOneDayStillFormats() {
    XCTAssertEqual(EarlyOfferService.format(remaining: 90000), "25:00:00")
  }
}
