import XCTest
@testable import Tickemo

final class SeatResolverTests: XCTestCase {
  private var layout: VenueLayout!

  override func setUpWithError() throws {
    try super.setUpWithError()
    layout = try VenueLayout.tokyoDome()
  }

  func testStand1Aisle20ResolvesDespiteSideAndGateNoise() throws {
    let raw = "1階 3塁側 25ゲート 20通路 12列 5番"
    let resolution = SeatResolver.resolve(rawSeat: raw, layout: layout)

    guard case .resolved(let seat) = resolution else {
      return XCTFail("expected resolved, got \(resolution)")
    }
    XCTAssertEqual(seat.layoutId, "tokyo-dome")
    XCTAssertEqual(seat.tierId, "stand1")
    XCTAssertEqual(seat.blockId, "stand1-aisle-20")
    XCTAssertEqual(seat.input.aisle, 20)
    XCTAssertEqual(seat.input.gate, 25)
    XCTAssertEqual(seat.input.row, 12)
    XCTAssertEqual(seat.input.number, 5)
    XCTAssertNil(seat.position3D)
  }

  func testArenaFineBlockIsUnsupportedOrNeedsPicker() {
    let raw = "アリーナ B3ブロック 10列 15番"
    let resolution = SeatResolver.resolve(rawSeat: raw, layout: layout)

    switch resolution {
    case .unsupported, .needsPicker:
      break
    case .resolved(let seat):
      XCTFail("arena fine block must not resolve to a permanent block, got \(seat.blockId)")
    }
  }

  func testBrokenStringNeedsPicker() {
    let resolution = SeatResolver.resolve(rawSeat: "あいうえお", layout: layout)
    XCTAssertEqual(resolution, .needsPicker)

    let empty = SeatResolver.resolve(rawSeat: "   ", layout: layout)
    XCTAssertEqual(empty, .needsPicker)
  }

  func testParserExtractsTierAisleRow() {
    let input = SeatInputParser.parse("1階 3塁側 20通路 12列 5番")
    XCTAssertEqual(input.tierHint, .stand1)
    XCTAssertEqual(input.sideHint, .thirdBase)
    XCTAssertEqual(input.aisle, 20)
    XCTAssertEqual(input.row, 12)
    XCTAssertEqual(input.number, 5)
  }
}
