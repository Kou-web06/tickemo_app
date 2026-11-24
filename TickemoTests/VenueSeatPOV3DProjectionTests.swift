import XCTest
@testable import Tickemo

final class VenueSeatPOV3DProjectionTests: XCTestCase {
  private var layout: VenueLayout!

  override func setUpWithError() throws {
    try super.setUpWithError()
    layout = try VenueLayout.tokyoDome()
  }

  func testCameraLooksTowardStage() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    let block = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-20" })
    let camera = VenueSeatPOV3DProjection.camera(
      for: block,
      tier: stand1,
      row: 12,
      number: 5
    )

    let stage = VenueSeatPOV3DProjection.stageLookAtPoint()
    XCTAssertEqual(camera.lookAt.x, stage.x, accuracy: 1e-9)
    XCTAssertEqual(camera.lookAt.z, stage.z, accuracy: 1e-9)

    let projectedStage = try XCTUnwrap(
      VenueSeatPOV3DProjection.project(stage, camera: camera)
    )
    // ステージは正面・カメラ前方にあり、投影 X はおおよそ中央
    XCTAssertGreaterThan(projectedStage.depth, 1)
    XCTAssertLessThan(abs(projectedStage.x), 12)

    let forward = camera.basis.forward
    // ステージは −Z 側なので、本塁寄りの席からの前方は −Z 成分を持つ
    XCTAssertLessThan(forward.z, 0)
  }

  func testFartherBlockAppearsSmallerAndHigher() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    // 本塁寄り席から見て、手前のアリーナ縁より対面スタンドの方が遠く・小さく・高い
    let cameraBlock = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-20" })
    let farBlock = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-01" })

    let camera = VenueSeatPOV3DProjection.camera(
      for: cameraBlock,
      tier: stand1,
      row: 12,
      number: 5
    )
    let lookAt = camera.lookAt

    let nearCenter = VenueSeatMap3DProjection.worldPoint(
      angleDegrees: 195,
      radius: 40,
      height: 0.5
    )
    let farCenter = VenueSeatPOV3DProjection.blockCenterWorldPoint(
      block: farBlock,
      tier: stand1
    )

    let pNear = try XCTUnwrap(VenueSeatPOV3DProjection.project(nearCenter, camera: camera))
    let pFar = try XCTUnwrap(VenueSeatPOV3DProjection.project(farCenter, camera: camera))
    XCTAssertGreaterThan(pFar.depth, pNear.depth)
    // 遠いスタンドの方が投影 Y が高い（画面上）
    XCTAssertGreaterThan(pFar.y, pNear.y)

    let nearChord = try XCTUnwrap(
      VenueSeatPOV3DProjection.projectPoints(
        VenueSeatPOV3DProjection.horizontalChordWorldPoints(
          around: nearCenter,
          chordLength: 8,
          toward: lookAt
        ),
        camera: camera
      )
    )
    let farChord = try XCTUnwrap(
      VenueSeatPOV3DProjection.projectPoints(
        VenueSeatPOV3DProjection.horizontalChordWorldPoints(
          around: farCenter,
          chordLength: 8,
          toward: lookAt
        ),
        camera: camera
      )
    )
    let nearSpan = projectedHorizontalSpan(nearChord)
    let farSpan = projectedHorizontalSpan(farChord)
    XCTAssertGreaterThan(nearSpan, farSpan)
  }

  func testRowAndNumberPullSeatTowardOuterAndAlongBlock() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    let block = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-20" })

    let front = VenueSeatPOV3DProjection.seatWorldPoint(
      block: block,
      tier: stand1,
      row: 1,
      number: 1
    )
    let back = VenueSeatPOV3DProjection.seatWorldPoint(
      block: block,
      tier: stand1,
      row: 20,
      number: 1
    )
    let frontR = hypot(front.x, front.z)
    let backR = hypot(back.x, back.z)
    XCTAssertGreaterThan(backR, frontR)
    XCTAssertGreaterThan(back.y, front.y)

    let leftish = VenueSeatPOV3DProjection.seatWorldPoint(
      block: block,
      tier: stand1,
      row: 10,
      number: 1
    )
    let rightish = VenueSeatPOV3DProjection.seatWorldPoint(
      block: block,
      tier: stand1,
      row: 10,
      number: 16
    )
    // 同じ列なら高さはほぼ同じ、角度方向で位置が変わる
    XCTAssertEqual(leftish.y, rightish.y, accuracy: 0.05)
    XCTAssertGreaterThan(hypot(leftish.x - rightish.x, leftish.z - rightish.z), 1)
  }

  func testStageProjectsFromSeatCamera() throws {
    let stand1 = try XCTUnwrap(layout.tier(id: "stand1"))
    let block = try XCTUnwrap(stand1.blocks.first { $0.id == "stand1-aisle-32" })
    let camera = VenueSeatPOV3DProjection.camera(for: block, tier: stand1, row: 8, number: 4)

    let top = try XCTUnwrap(
      VenueSeatPOV3DProjection.projectPoints(
        VenueSeatPOV3DProjection.stageBoxTopWorldPoints(),
        camera: camera
      )
    )
    XCTAssertEqual(top.count, 4)
    XCTAssertTrue(top.allSatisfy { $0.depth > 0.5 })
  }

  private func projectedHorizontalSpan(
    _ points: [VenueSeatPOV3DProjection.ProjectedPoint]
  ) -> Double {
    let xs = points.map(\.x)
    guard let minX = xs.min(), let maxX = xs.max() else { return 0 }
    return maxX - minX
  }
}
