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

  func testArenaFineBlockFallsBackToApproximateOverview() throws {
    let raw = "アリーナ B3ブロック 10列 15番"
    let resolution = SeatResolver.resolve(rawSeat: raw, layout: layout)

    guard case .approximate(let seat) = resolution else {
      return XCTFail("expected approximate overview, got \(resolution)")
    }
    XCTAssertEqual(seat.blockId, "arena-overview")
    XCTAssertEqual(seat.tierId, "arena")
    XCTAssertEqual(seat.input.arenaBlockLabel, "B3")
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

  // MARK: - Real-world string variations

  func testFullWidthDigitsAndSpacesParse() {
    let input = SeatInputParser.parse("１階　３塁側　２０通路　１２列　５番")
    XCTAssertEqual(input.tierHint, .stand1)
    XCTAssertEqual(input.sideHint, .thirdBase)
    XCTAssertEqual(input.aisle, 20)
    XCTAssertEqual(input.row, 12)
    XCTAssertEqual(input.number, 5)
  }

  func testNoSpacesStillParses() {
    let input = SeatInputParser.parse("1階3塁側20通路12列5番")
    XCTAssertEqual(input.tierHint, .stand1)
    XCTAssertEqual(input.sideHint, .thirdBase)
    XCTAssertEqual(input.aisle, 20)
    XCTAssertEqual(input.row, 12)
    XCTAssertEqual(input.number, 5)
  }

  func testSuffixBeforeNumberOrders() {
    let input = SeatInputParser.parse("1階 3塁側 通路20 ゲート25 列12 番5")
    XCTAssertEqual(input.aisle, 20)
    XCTAssertEqual(input.gate, 25)
    XCTAssertEqual(input.row, 12)
    XCTAssertEqual(input.number, 5)
  }

  func testFloorAliasesOneFAndKanji() {
    XCTAssertEqual(SeatInputParser.parse("1F 一塁側 20通路").tierHint, .stand1)
    XCTAssertEqual(SeatInputParser.parse("１Ｆ 三塁側 47通路").tierHint, .stand1)
    XCTAssertEqual(SeatInputParser.parse("二階 1塁側 3通路").tierHint, .stand2)
    XCTAssertEqual(SeatInputParser.parse("2F 中央 7通路").tierHint, .stand2)
  }

  func testSideAliasesKanjiAndEnglish() {
    XCTAssertEqual(SeatInputParser.parse("1階 一塁側 2通路").sideHint, .firstBase)
    XCTAssertEqual(SeatInputParser.parse("1階 三塁側 48通路").sideHint, .thirdBase)
    XCTAssertEqual(SeatInputParser.parse("1階 1B 10通路").sideHint, .firstBase)
    XCTAssertEqual(SeatInputParser.parse("バルコニー サード").sideHint, .thirdBase)
    XCTAssertEqual(SeatInputParser.parse("2階 センター 7通路").sideHint, .center)
  }

  func testDashedSeparatorsNormalize() {
    let input = SeatInputParser.parse("1階-3塁側-20通路-12列-5番")
    XCTAssertEqual(input.tierHint, .stand1)
    XCTAssertEqual(input.aisle, 20)
    XCTAssertEqual(input.row, 12)
    XCTAssertEqual(input.number, 5)
  }

  func testAisleWinsOverConflictingSideHint() throws {
    // レイアウト上 20通路は 1塁側。ユーザーが 3塁側と書いていても通路を優先する。
    let resolution = SeatResolver.resolve(
      rawSeat: "1階 3塁側 20通路",
      layout: layout
    )
    guard case .resolved(let seat) = resolution else {
      return XCTFail("expected resolved, got \(resolution)")
    }
    XCTAssertEqual(seat.blockId, "stand1-aisle-20")
    XCTAssertEqual(layout.block(id: seat.blockId)?.block.side, "1塁側")
  }

  func testSideOnlyStandResolvesCoarseBlock() throws {
    let resolution = SeatResolver.resolve(rawSeat: "1階 3塁側", layout: layout)
    guard case .resolved(let seat) = resolution else {
      return XCTFail("expected coarse resolve, got \(resolution)")
    }
    XCTAssertEqual(seat.tierId, "stand1")
    XCTAssertEqual(layout.block(id: seat.blockId)?.block.side, "3塁側")
    XCTAssertNil(seat.input.aisle)
  }

  func testBalconySideStillResolves() throws {
    let resolution = SeatResolver.resolve(rawSeat: "バルコニー 三塁側", layout: layout)
    guard case .resolved(let seat) = resolution else {
      return XCTFail("expected resolved, got \(resolution)")
    }
    XCTAssertEqual(seat.blockId, "balcony-3b")
  }

  func testArenaOverviewStillResolvesWithoutFineBlock() throws {
    let resolution = SeatResolver.resolve(rawSeat: "アリーナ 10列 15番", layout: layout)
    guard case .resolved(let seat) = resolution else {
      return XCTFail("expected arena overview, got \(resolution)")
    }
    XCTAssertEqual(seat.blockId, "arena-overview")
  }

  func testArenaBlockLabelReversedOrderStillApproximate() throws {
    let resolution = SeatResolver.resolve(
      rawSeat: "アリーナ ブロックB3 10列",
      layout: layout
    )
    guard case .approximate(let seat) = resolution else {
      return XCTFail("expected approximate, got \(resolution)")
    }
    XCTAssertEqual(seat.blockId, "arena-overview")
    XCTAssertEqual(seat.input.arenaBlockLabel, "B3")
  }

  func testArenaOverviewHelper() throws {
    let overview = try XCTUnwrap(SeatResolver.arenaOverview(in: layout))
    XCTAssertEqual(overview.tier.id, "arena")
    XCTAssertEqual(overview.block.id, "arena-overview")
    XCTAssertEqual(overview.block.name, "アリーナ（概位置）")
  }
}
