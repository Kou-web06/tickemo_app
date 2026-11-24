import XCTest
@testable import Tickemo

final class VenueSeatMap3DProjectionTests: XCTestCase {
  private var layout: VenueLayout!
  private var camera: VenueSeatMap3DProjection.Camera!

  override func setUpWithError() throws {
    try super.setUpWithError()
    layout = try VenueLayout.tokyoDome()
    camera = .homePlateViewpoint(
      maxOuterRadius: layout.tiers.map(\.outerRadius).max() ?? 98
    )
  }

  func testHeightUsesBaseHeightAndRake() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    let inner = VenueSeatMap3DProjection.height(tier: stand1, radius: stand1.innerRadius)
    let outer = VenueSeatMap3DProjection.height(tier: stand1, radius: stand1.outerRadius)

    XCTAssertEqual(inner, stand1.baseHeight, accuracy: 1e-9)
    XCTAssertEqual(
      outer,
      stand1.baseHeight + stand1.rake * (stand1.outerRadius - stand1.innerRadius),
      accuracy: 1e-9
    )
    XCTAssertGreaterThan(outer, inner)
  }

  func testFartherSameChordAppearsSmaller() throws {
    // 同じ水平弦長でも、ステージ側（遠い）の投影長の方が小さい
    let nearA = VenueSeatMap3DProjection.worldPoint(angleDegrees: 175, radius: 50, height: 4)
    let nearB = VenueSeatMap3DProjection.worldPoint(angleDegrees: 185, radius: 50, height: 4)
    let farA = VenueSeatMap3DProjection.worldPoint(angleDegrees: 5, radius: 50, height: 4)
    let farB = VenueSeatMap3DProjection.worldPoint(angleDegrees: 355, radius: 50, height: 4)

    let pNearA = try XCTUnwrap(VenueSeatMap3DProjection.project(nearA, camera: camera))
    let pNearB = try XCTUnwrap(VenueSeatMap3DProjection.project(nearB, camera: camera))
    let pFarA = try XCTUnwrap(VenueSeatMap3DProjection.project(farA, camera: camera))
    let pFarB = try XCTUnwrap(VenueSeatMap3DProjection.project(farB, camera: camera))

    let nearLen = hypot(pNearA.x - pNearB.x, pNearA.y - pNearB.y)
    let farLen = hypot(pFarA.x - pFarB.x, pFarA.y - pFarB.y)

    XCTAssertGreaterThan(pFarA.depth, pNearA.depth)
    XCTAssertGreaterThan(nearLen, farLen)
  }

  func testAngleOrderKeepsThirdBaseLeftOfFirstBase() throws {
    // 本塁手前視点で、同半径の 3塁側(90°)は 1塁側(270°)より投影 X が小さい（左）
    let third = VenueSeatMap3DProjection.worldPoint(angleDegrees: 90, radius: 60, height: 6)
    let first = VenueSeatMap3DProjection.worldPoint(angleDegrees: 270, radius: 60, height: 6)

    let pThird = try XCTUnwrap(VenueSeatMap3DProjection.project(third, camera: camera))
    let pFirst = try XCTUnwrap(VenueSeatMap3DProjection.project(first, camera: camera))

    XCTAssertLessThan(pThird.x, pFirst.x)
  }

  func testBlockCornersProjectAndOuterIsHigher() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    let block = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-20" })

    let corners = VenueSeatMap3DProjection.blockCornerWorldPoints(block: block, tier: stand1)
    XCTAssertEqual(corners.count, 4)

    let outerHeights = [corners[0].y, corners[1].y]
    let innerHeights = [corners[2].y, corners[3].y]
    XCTAssertEqual(outerHeights[0], outerHeights[1], accuracy: 1e-9)
    XCTAssertEqual(innerHeights[0], innerHeights[1], accuracy: 1e-9)
    XCTAssertGreaterThan(outerHeights[0], innerHeights[0])

    let projected = try XCTUnwrap(
      VenueSeatMap3DProjection.projectPoints(corners, camera: camera)
    )
    XCTAssertEqual(projected.count, 4)
  }

  func testProjectedOutlineDepthOrdersStageFartherThanHome() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    // 1塁側外野寄り ≈ 300°、3塁側外野寄り ≈ 60°、本塁寄り ≈ 180° 付近
    let homeSide = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-24" })
    let stageSide = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-01" })

    let homeProj = try XCTUnwrap(
      VenueSeatMap3DProjection.projectBlockOutline(block: homeSide, tier: stand1, camera: camera)
    )
    let stageProj = try XCTUnwrap(
      VenueSeatMap3DProjection.projectBlockOutline(block: stageSide, tier: stand1, camera: camera)
    )

    XCTAssertGreaterThan(stageProj.depth, homeProj.depth)
  }
}
