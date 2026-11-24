import CoreGraphics
import Foundation

/// 座席視点（Seat POV）の簡易カメラ＋透視投影。俯瞰投影（`VenueSeatMap3DProjection`）とは別 API。
///
/// ワールド座標は俯瞰側と共通（メートル）:
/// - 原点 = フィールド中心
/// - 角度 0° = 外野中央（ステージ側）、反時計回り、本塁 ≈ 180°
/// - X / Y / Z は `VenueSeatMap3DProjection.worldPoint` と同じ
///
/// SceneKit / RealityKit 非依存。視線は座席ブロック（列・番があれば寄せた点）→ ステージ。
enum VenueSeatPOV3DProjection {
  typealias Point3D = VenueSeatMap3DProjection.Point3D
  typealias ProjectedPoint = VenueSeatMap3DProjection.ProjectedPoint

  /// 座席視点カメラ。`lookAt` はステージ側（外野中央 / 角度 0）。
  struct Camera: Equatable {
    var position: Point3D
    var lookAt: Point3D
    var focalLength: Double
    /// ワールド上方向（通常 +Y）。
    var worldUp: Point3D

    /// カメラ前方・右・上の正規化基底（右手系: right × up = forward）。
    var basis: (forward: Point3D, right: Point3D, up: Point3D) {
      let forward = normalize(subtract(lookAt, position))
      let right = normalize(cross(forward, worldUp))
      // forward が worldUp とほぼ平行なときフォールバック
      let safeRight: Point3D
      if length(right) < 1e-6 {
        safeRight = Point3D(x: 1, y: 0, z: 0)
      } else {
        safeRight = right
      }
      let up = normalize(cross(safeRight, forward))
      return (forward, safeRight, up)
    }
  }

  /// ステージ注視点（外野中央寄り・床上やや高め）。
  static func stageLookAtPoint(radius: Double = 38, height: Double = 1.5) -> Point3D {
    VenueSeatMap3DProjection.worldPoint(angleDegrees: 0, radius: radius, height: height)
  }

  /// ブロック中心（列・番があれば半径・角度を寄せる）にカメラを置く。
  /// - Parameters:
  ///   - eyeHeightAboveSeat: 座面からの目線高さ（メートル）
  ///   - assumedRowCount: 列番号が無い／大きいときの仮の総列数
  ///   - assumedSeatCount: 番が無い／大きいときの仮の総席数
  static func camera(
    for block: VenueBlock,
    tier: VenueTier,
    row: Int? = nil,
    number: Int? = nil,
    eyeHeightAboveSeat: Double = 1.15,
    assumedRowCount: Int = 20,
    assumedSeatCount: Int = 16,
    focalLength: Double = 72
  ) -> Camera {
    let seat = seatWorldPoint(
      block: block,
      tier: tier,
      row: row,
      number: number,
      assumedRowCount: assumedRowCount,
      assumedSeatCount: assumedSeatCount
    )
    let position = Point3D(
      x: seat.x,
      y: seat.y + eyeHeightAboveSeat,
      z: seat.z
    )
    return Camera(
      position: position,
      lookAt: stageLookAtPoint(),
      focalLength: focalLength,
      worldUp: Point3D(x: 0, y: 1, z: 0)
    )
  }

  /// 座席面のワールド点（列 = 内径→外径、番 = ブロック角の補間）。
  static func seatWorldPoint(
    block: VenueBlock,
    tier: VenueTier,
    row: Int? = nil,
    number: Int? = nil,
    assumedRowCount: Int = 20,
    assumedSeatCount: Int = 16
  ) -> Point3D {
    let angles = normalizedAngles(start: block.startAngle, end: block.endAngle)
    let midAngle = (angles.from + angles.to) / 2
    let angle: Double
    if let number, assumedSeatCount > 1 {
      let t = clampedUnit((Double(number) - 1) / Double(assumedSeatCount - 1))
      angle = angles.from + (angles.to - angles.from) * t
    } else {
      angle = midAngle
    }

    let radius: Double
    if let row, assumedRowCount > 1 {
      let t = clampedUnit((Double(row) - 1) / Double(assumedRowCount - 1))
      radius = tier.innerRadius + (tier.outerRadius - tier.innerRadius) * t
    } else {
      radius = (tier.innerRadius + tier.outerRadius) / 2
    }

    let height = VenueSeatMap3DProjection.height(tier: tier, radius: radius)
    return VenueSeatMap3DProjection.worldPoint(
      angleDegrees: angle,
      radius: radius,
      height: height
    )
  }

  /// ワールド点を座席視点で透視投影。カメラ背面は nil。
  static func project(_ point: Point3D, camera: Camera) -> ProjectedPoint? {
    let basis = camera.basis
    let rel = subtract(point, camera.position)
    let camX = dot(rel, basis.right)
    let camY = dot(rel, basis.up)
    let depth = dot(rel, basis.forward)
    guard depth > 0.35 else { return nil }
    return ProjectedPoint(
      x: camera.focalLength * camX / depth,
      y: camera.focalLength * camY / depth,
      depth: depth
    )
  }

  static func projectPoints(_ points: [Point3D], camera: Camera) -> [ProjectedPoint]? {
    var projected: [ProjectedPoint] = []
    projected.reserveCapacity(points.count)
    for point in points {
      guard let p = project(point, camera: camera) else { return nil }
      projected.append(p)
    }
    return projected
  }

  /// カメラ背面の点は捨てて投影。輪郭がカメラをまたぐスタンド帯向け。
  static func projectPointsAllowingPartial(
    _ points: [Point3D],
    camera: Camera
  ) -> [ProjectedPoint] {
    points.compactMap { project($0, camera: camera) }
  }

  /// ブロック中心の座面点（列・番なし）。性質テスト・深度比較用。
  static func blockCenterWorldPoint(block: VenueBlock, tier: VenueTier) -> Point3D {
    seatWorldPoint(block: block, tier: tier, row: nil, number: nil)
  }

  /// 指定ワールド点まわりの水平弦（長さ `chordLength`）。遠近による見かけサイズ比較用。
  static func horizontalChordWorldPoints(
    around center: Point3D,
    chordLength: Double,
    toward lookAt: Point3D
  ) -> [Point3D] {
    let forward = normalize(subtract(lookAt, center))
    let right = normalize(cross(forward, Point3D(x: 0, y: 1, z: 0)))
    let half = chordLength / 2
    return [
      Point3D(x: center.x - right.x * half, y: center.y, z: center.z - right.z * half),
      Point3D(x: center.x + right.x * half, y: center.y, z: center.z + right.z * half)
    ]
  }

  // MARK: - Scene meshes（模式図用の簡易ポリゴン）

  /// アリーナ床（円近似、高さ 0）。俯瞰側との共用。
  static func arenaFloorWorldPoints(radius: Double = 42, samples: Int = 28) -> [Point3D] {
    let steps = max(samples, 8)
    var points: [Point3D] = []
    for i in 0..<steps {
      let angle = 360.0 * Double(i) / Double(steps)
      points.append(
        VenueSeatMap3DProjection.worldPoint(angleDegrees: angle, radius: radius, height: 0)
      )
    }
    return points
  }

  /// 座席前方に見えるアリーナ床（扇形）。カメラ背面の欠落で輪郭が潰れるのを防ぐ。
  static func arenaFloorFanWorldPoints(
    cameraAngleDegrees: Double,
    nearRadius: Double = 8,
    farRadius: Double = 42,
    halfSpanDegrees: Double = 70,
    samples: Int = 10
  ) -> [Point3D] {
    let steps = max(samples, 3)
    var points: [Point3D] = []
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = cameraAngleDegrees - halfSpanDegrees + (2 * halfSpanDegrees) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(angleDegrees: angle, radius: farRadius, height: 0)
      )
    }
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = cameraAngleDegrees + halfSpanDegrees - (2 * halfSpanDegrees) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(angleDegrees: angle, radius: nearRadius, height: 0)
      )
    }
    return points
  }

  /// 対面スタンド帯（カメラ角の反対側の粗い帯）。
  static func oppositeStandBandWorldPoints(
    cameraAngleDegrees: Double,
    tier: VenueTier,
    halfSpanDegrees: Double = 55,
    samples: Int = 8
  ) -> [Point3D] {
    let opposite = (cameraAngleDegrees + 180).truncatingRemainder(dividingBy: 360)
    let from = opposite - halfSpanDegrees
    let to = opposite + halfSpanDegrees
    let steps = max(samples, 3)
    var points: [Point3D] = []
    let outerH = VenueSeatMap3DProjection.height(tier: tier, radius: tier.outerRadius)
    let innerH = VenueSeatMap3DProjection.height(tier: tier, radius: tier.innerRadius)
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = from + (to - from) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(
          angleDegrees: angle,
          radius: tier.outerRadius,
          height: outerH
        )
      )
    }
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = to - (to - from) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(
          angleDegrees: angle,
          radius: tier.innerRadius,
          height: innerH
        )
      )
    }
    return points
  }

  /// 左右スタンド帯（カメラ角±オフセット）。
  static func sideStandBandWorldPoints(
    cameraAngleDegrees: Double,
    tier: VenueTier,
    sideSign: Double,
    centerOffsetDegrees: Double = 55,
    halfSpanDegrees: Double = 28,
    samples: Int = 5
  ) -> [Point3D] {
    let center = cameraAngleDegrees + sideSign * centerOffsetDegrees
    let from = center - halfSpanDegrees
    let to = center + halfSpanDegrees
    let steps = max(samples, 2)
    var points: [Point3D] = []
    let outerH = VenueSeatMap3DProjection.height(tier: tier, radius: tier.outerRadius)
    let innerH = VenueSeatMap3DProjection.height(tier: tier, radius: tier.innerRadius)
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = from + (to - from) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(
          angleDegrees: angle,
          radius: tier.outerRadius,
          height: outerH
        )
      )
    }
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = to - (to - from) * t
      points.append(
        VenueSeatMap3DProjection.worldPoint(
          angleDegrees: angle,
          radius: tier.innerRadius,
          height: innerH
        )
      )
    }
    return points
  }

  /// カメラ位置の極角（度、会場座標系）。
  static func cameraAngleDegrees(position: Point3D) -> Double {
    let degrees = atan2(-position.x, -position.z) * 180 / .pi
    return (degrees + 360).truncatingRemainder(dividingBy: 360)
  }

  /// ステージ箱の上面 4 角（外野中央・角度 0 側）。
  static func stageBoxTopWorldPoints(
    centerRadius: Double = 38,
    width: Double = 28,
    depth: Double = 10,
    height: Double = 1.5
  ) -> [Point3D] {
    // ステージは −Z 側。幅 = ±X、奥行き = Z 方向。
    let center = VenueSeatMap3DProjection.worldPoint(
      angleDegrees: 0,
      radius: centerRadius,
      height: height
    )
    let halfW = width / 2
    let halfD = depth / 2
    return [
      Point3D(x: center.x - halfW, y: height, z: center.z - halfD),
      Point3D(x: center.x + halfW, y: height, z: center.z - halfD),
      Point3D(x: center.x + halfW, y: height, z: center.z + halfD),
      Point3D(x: center.x - halfW, y: height, z: center.z + halfD)
    ]
  }

  /// ステージ箱の手前立面（観客側の面）。
  static func stageBoxFrontWorldPoints(
    centerRadius: Double = 38,
    width: Double = 28,
    depth: Double = 10,
    height: Double = 1.5
  ) -> [Point3D] {
    let center = VenueSeatMap3DProjection.worldPoint(
      angleDegrees: 0,
      radius: centerRadius,
      height: 0
    )
    let halfW = width / 2
    let frontZ = center.z + depth / 2
    return [
      Point3D(x: center.x - halfW, y: 0, z: frontZ),
      Point3D(x: center.x + halfW, y: 0, z: frontZ),
      Point3D(x: center.x + halfW, y: height, z: frontZ),
      Point3D(x: center.x - halfW, y: height, z: frontZ)
    ]
  }

  /// スタンド帯の輪郭（俯瞰投影と同じ角サンプリング）。遠い帯ほど小さく・高く見える。
  static func standBandWorldPoints(
    block: VenueBlock,
    tier: VenueTier,
    arcSamples: Int = 5
  ) -> [Point3D] {
    VenueSeatMap3DProjection.blockOutlineWorldPoints(
      block: block,
      tier: tier,
      arcSamples: arcSamples
    )
  }

  /// 自分の席付近を示す小さなマーカー四角形。
  /// カメラ直下だと透視の深度が取れないため、ステージ方向へ少し前にずらす。
  static func seatMarkerWorldPoints(
    block: VenueBlock,
    tier: VenueTier,
    row: Int? = nil,
    number: Int? = nil,
    halfWidth: Double = 1.8,
    halfDepth: Double = 1.2,
    forwardOffset: Double = 8
  ) -> [Point3D] {
    let seat = seatWorldPoint(block: block, tier: tier, row: row, number: number)
    let toStage = normalize(subtract(stageLookAtPoint(), seat))
    let right = normalize(cross(toStage, Point3D(x: 0, y: 1, z: 0)))
    let forward = Point3D(x: toStage.x, y: 0, z: toStage.z)
    let forwardFlat = normalize(forward)
    let center = Point3D(
      x: seat.x + forwardFlat.x * forwardOffset,
      y: seat.y + 0.08,
      z: seat.z + forwardFlat.z * forwardOffset
    )
    return [
      Point3D(
        x: center.x - right.x * halfWidth - forwardFlat.x * halfDepth,
        y: center.y,
        z: center.z - right.z * halfWidth - forwardFlat.z * halfDepth
      ),
      Point3D(
        x: center.x + right.x * halfWidth - forwardFlat.x * halfDepth,
        y: center.y,
        z: center.z + right.z * halfWidth - forwardFlat.z * halfDepth
      ),
      Point3D(
        x: center.x + right.x * halfWidth + forwardFlat.x * halfDepth,
        y: center.y,
        z: center.z + right.z * halfWidth + forwardFlat.z * halfDepth
      ),
      Point3D(
        x: center.x - right.x * halfWidth + forwardFlat.x * halfDepth,
        y: center.y,
        z: center.z - right.z * halfWidth + forwardFlat.z * halfDepth
      )
    ]
  }

  /// 投影座標のバウンディングボックス。
  static func bounds(of points: [ProjectedPoint]) -> CGRect? {
    VenueSeatMap3DProjection.bounds(of: points)
  }

  /// 投影平面 → 画面座標（+Y が画面上）。
  static func screenPoint(
    _ projected: ProjectedPoint,
    bounds: CGRect,
    in rect: CGRect,
    padding: CGFloat = 0.1
  ) -> CGPoint {
    VenueSeatMap3DProjection.screenPoint(
      projected,
      bounds: bounds,
      in: rect,
      padding: padding
    )
  }

  // MARK: - Math helpers

  private static func normalizedAngles(start: Double, end: Double) -> (from: Double, to: Double) {
    (from: min(start, end), to: max(start, end))
  }

  private static func clampedUnit(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  private static func subtract(_ a: Point3D, _ b: Point3D) -> Point3D {
    Point3D(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
  }

  private static func dot(_ a: Point3D, _ b: Point3D) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
  }

  private static func cross(_ a: Point3D, _ b: Point3D) -> Point3D {
    Point3D(
      x: a.y * b.z - a.z * b.y,
      y: a.z * b.x - a.x * b.z,
      z: a.x * b.y - a.y * b.x
    )
  }

  private static func length(_ v: Point3D) -> Double {
    sqrt(dot(v, v))
  }

  private static func normalize(_ v: Point3D) -> Point3D {
    let len = length(v)
    guard len > 1e-9 else { return Point3D(x: 0, y: 0, z: 0) }
    return Point3D(x: v.x / len, y: v.y / len, z: v.z / len)
  }
}
