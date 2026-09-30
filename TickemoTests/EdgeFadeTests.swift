import XCTest
@testable import Tickemo

final class EdgeFadeTests: XCTestCase {
  func testNoLeadingFadeAtRest() {
    XCTAssertEqual(EdgeFade.leading(contentMinX: 0, fadeWidth: 24), 0)
  }

  func testLeadingFadeGrowsWithScrollAndCapsAtOne() {
    XCTAssertEqual(EdgeFade.leading(contentMinX: -12, fadeWidth: 24), 0.5)
    XCTAssertEqual(EdgeFade.leading(contentMinX: -200, fadeWidth: 24), 1)
  }

  func testTrailingFadeOnlyWhileContentOverflowsTheRight() {
    XCTAssertEqual(EdgeFade.trailing(contentMaxX: 460, viewportWidth: 346, fadeWidth: 24), 1)
    XCTAssertEqual(EdgeFade.trailing(contentMaxX: 358, viewportWidth: 346, fadeWidth: 24), 0.5)
    // 右端まで行った／そもそもはみ出さない列はぼかさない
    XCTAssertEqual(EdgeFade.trailing(contentMaxX: 346, viewportWidth: 346, fadeWidth: 24), 0)
    XCTAssertEqual(EdgeFade.trailing(contentMaxX: 200, viewportWidth: 346, fadeWidth: 24), 0)
  }

  func testInvalidInputsNeverFade() {
    XCTAssertEqual(EdgeFade.leading(contentMinX: -10, fadeWidth: 0), 0)
    XCTAssertEqual(EdgeFade.trailing(contentMaxX: .nan, viewportWidth: 100, fadeWidth: 24), 0)
  }
}
