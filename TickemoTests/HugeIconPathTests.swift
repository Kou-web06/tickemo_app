import XCTest
import SwiftUI
@testable import Tickemo

final class HugeIconPathTests: XCTestCase {
  private func cgPathElements(_ path: Path) -> [(CGPathElementType, [CGPoint])] {
    var elements: [(CGPathElementType, [CGPoint])] = []
    path.cgPath.applyWithBlock { pointer in
      let element = pointer.pointee
      let points: [CGPoint]
      switch element.type {
      case .moveToPoint, .addLineToPoint:
        points = [element.points[0]]
      case .addQuadCurveToPoint:
        points = [element.points[0], element.points[1]]
      case .addCurveToPoint:
        points = [element.points[0], element.points[1], element.points[2]]
      case .closeSubpath:
        points = []
      @unknown default:
        points = []
      }
      elements.append((element.type, points))
    }
    return elements
  }

  func testStraightLineCommandsFormAClosedSquare() {
    let elements = cgPathElements(HugeIconPath.parse("M0 0L10 0L10 10L0 10Z"))
    XCTAssertEqual(elements.map(\.0), [.moveToPoint, .addLineToPoint, .addLineToPoint, .addLineToPoint, .closeSubpath])
    XCTAssertEqual(elements[0].1, [CGPoint(x: 0, y: 0)])
    XCTAssertEqual(elements[1].1, [CGPoint(x: 10, y: 0)])
    XCTAssertEqual(elements[3].1, [CGPoint(x: 0, y: 10)])
  }

  // Caught mid-implementation: Add01Icon's own path ("M12.001
  // 5.00003V19.002") uses "V", disproving the initial M/L/C/Z-only
  // assumption. Covers both H and V here since both were missed together.
  func testHorizontalAndVerticalShorthandsProduceLines() {
    let elements = cgPathElements(HugeIconPath.parse("M0 0H10V10H0Z"))
    XCTAssertEqual(elements.map(\.0), [.moveToPoint, .addLineToPoint, .addLineToPoint, .addLineToPoint, .closeSubpath])
    XCTAssertEqual(elements[1].1, [CGPoint(x: 10, y: 0)])
    XCTAssertEqual(elements[2].1, [CGPoint(x: 10, y: 10)])
    XCTAssertEqual(elements[3].1, [CGPoint(x: 0, y: 10)])
  }

  func testCubicCurveCommandPassesThroughItsControlPoints() {
    let elements = cgPathElements(HugeIconPath.parse("M0 0C0 10 10 10 10 0"))
    XCTAssertEqual(elements.map(\.0), [.moveToPoint, .addCurveToPoint])
    XCTAssertEqual(elements[1].1, [CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 0)])
  }

  func testRelativeCommandsMatchTheirAbsoluteEquivalent() {
    let absolute = cgPathElements(HugeIconPath.parse("M0 0L10 0L10 10Z"))
    let relative = cgPathElements(HugeIconPath.parse("M0 0l10 0l0 10Z"))
    XCTAssertEqual(absolute.map(\.0), relative.map(\.0))
    for (a, r) in zip(absolute, relative) {
      XCTAssertEqual(a.1, r.1)
    }
  }

  func testSmoothCurveReflectsThePreviousCurvesControlPoint() {
    let elements = cgPathElements(HugeIconPath.parse("M0 0C0 10 10 10 10 0S30 -10 30 0"))
    XCTAssertEqual(elements.map(\.0), [.moveToPoint, .addCurveToPoint, .addCurveToPoint])
    // Reflecting (10,10) over the current point (10,0) gives (10,-10).
    XCTAssertEqual(elements[2].1[0], CGPoint(x: 10, y: -10))
  }
}
