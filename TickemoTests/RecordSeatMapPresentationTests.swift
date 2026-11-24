import XCTest
@testable import Tickemo

final class RecordSeatMapPresentationTests: XCTestCase {
  private var layout: VenueLayout!

  override func setUpWithError() throws {
    try super.setUpWithError()
    layout = try VenueLayout.tokyoDome()
  }

  func testMatchesTokyoDomeVariants() {
    XCTAssertTrue(TokyoDomeVenueMatching.matches("東京ドーム"))
    XCTAssertTrue(TokyoDomeVenueMatching.matches("TOKYO DOME"))
    XCTAssertTrue(TokyoDomeVenueMatching.matches(" Tokyo Dome "))
    XCTAssertFalse(TokyoDomeVenueMatching.matches(nil))
    XCTAssertFalse(TokyoDomeVenueMatching.matches(""))
    XCTAssertFalse(TokyoDomeVenueMatching.matches("京セラドーム大阪"))
    XCTAssertFalse(TokyoDomeVenueMatching.matches("東京ドームシティホール"))
    XCTAssertFalse(TokyoDomeVenueMatching.matches("東京ドームホテル"))
  }

  func testNilWhenVenueOrSeatMissing() {
    XCTAssertNil(RecordSeatMapPresentation.make(
      venue: "東京ドーム",
      seat: nil,
      layout: layout
    ))
    XCTAssertNil(RecordSeatMapPresentation.make(
      venue: "東京ドーム",
      seat: "   ",
      layout: layout
    ))
    XCTAssertNil(RecordSeatMapPresentation.make(
      venue: "横浜アリーナ",
      seat: "1階 20通路 12列 5番",
      layout: layout
    ))
  }

  func testResolvedHighlightsBlock() {
    let model = RecordSeatMapPresentation.make(
      venue: "東京ドーム",
      seat: "1階 3塁側 20通路 12列 5番",
      layout: layout
    )
    guard let model else {
      return XCTFail("expected model")
    }
    XCTAssertEqual(model.initialBlockId, "stand1-aisle-20")
    XCTAssertFalse(model.encouragesPicker)
    XCTAssertTrue(model.statusText.contains("推定位置"))
    guard case .resolved = model.resolution else {
      return XCTFail("expected resolved")
    }
  }

  func testNeedsPickerWhenUnparseable() {
    let model = RecordSeatMapPresentation.make(
      venue: "TOKYO DOME",
      seat: "あいうえお",
      layout: layout
    )
    guard let model else {
      return XCTFail("expected model")
    }
    XCTAssertNil(model.initialBlockId)
    XCTAssertTrue(model.encouragesPicker)
    XCTAssertEqual(model.resolution, .needsPicker)
    XCTAssertTrue(model.statusText.contains("タップ"))
  }

  func testArenaFineBlockHighlightsApproximateOverview() {
    let model = RecordSeatMapPresentation.make(
      venue: "東京ドーム",
      seat: "アリーナ B3ブロック 10列 15番",
      layout: layout
    )
    guard let model else {
      return XCTFail("expected model")
    }
    XCTAssertEqual(model.initialBlockId, "arena-overview")
    XCTAssertFalse(model.encouragesPicker)
    XCTAssertTrue(model.statusText.contains("概位置"))
    XCTAssertTrue(model.statusText.contains("B3"))
    guard case .approximate = model.resolution else {
      return XCTFail("expected approximate, got \(model.resolution)")
    }
  }

  func testPlainArenaResolvesOverview() {
    let model = RecordSeatMapPresentation.make(
      venue: "東京ドーム",
      seat: "アリーナ 10列 15番",
      layout: layout
    )
    guard let model else {
      return XCTFail("expected model")
    }
    XCTAssertEqual(model.initialBlockId, "arena-overview")
    XCTAssertFalse(model.encouragesPicker)
    XCTAssertTrue(model.statusText.contains("推定位置"))
    guard case .resolved = model.resolution else {
      return XCTFail("expected resolved overview")
    }
  }
}
