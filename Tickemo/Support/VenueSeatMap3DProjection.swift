import CoreGraphics
import Foundation

/// 会場ブロックの簡易 3D→2D 透視投影。SceneKit / RealityKit 非依存。
///
/// ワールド座標（メートル）:
/// - 原点 = フィールド中心
/// - 角度 0° = 外野中央（ステージ側）、反時計回り、本塁 ≈ 180°
/// - X = `-r·sin(θ)`（本塁を手前にしたとき 3塁側が −X）
/// - Y = 高さ（`VenueTier.baseHeight` + `rake·(r − innerRadius)`）
/// - Z = `-r·cos(θ)`（本塁側 +Z、ステージ側 −Z）
enum VenueSeatMap3DProjection {
  struct Point3D: Equatable {
    var x: Double
    var y: Double
    var z: Double
  }

  /// 透視投影後の平面座標。`depth` はカメラ前方距離（大きいほど遠い）。
  struct ProjectedPoint: Equatable {
    var x: Double
    var y: Double
    var depth: Double
  }

  /// 本塁下寄り視点の簡易カメラ。視線はおおよそ −Z（ステージ方向）。
  struct Camera: Equatable {
    var position: Point3D
    /// 水平からの俯角（ラジアン）。正 = 見下ろし。
    var pitchRadians: Double
    var focalLength: Double

    /// 東京ドーム常設席向けデフォルト（本塁後方・やや高め）。
    static func homePlateViewpoint(maxOuterRadius: Double = 98) -> Camera {
      Camera(
        position: Point3D(
          x: 0,
          y: 32,
          z: max(maxOuterRadius + 28, 120)
        ),
        pitchRadians: 0.42,
        focalLength: 95
      )
    }
  }

  /// 階の半径位置における座席面高さ（メートル）。
  static func height(tier: VenueTier, radius: Double) -> Double {
    let depth = max(radius - tier.innerRadius, 0)
    return tier.baseHeight + tier.rake * depth
  }

  /// 極座標 + 高さ → ワールド座標。
  static func worldPoint(angleDegrees: Double, radius: Double, height: Double) -> Point3D {
    let radians = angleDegrees * .pi / 180
    return Point3D(
      x: -radius * sin(radians),
      y: height,
      z: -radius * cos(radians)
    )
  }

  /// ブロックの 4 角（内径・外径 × 開始・終了角）。時計回りで外弧→内弧。
  static func blockCornerWorldPoints(block: VenueBlock, tier: VenueTier) -> [Point3D] {
    let angles = cornerAngles(start: block.startAngle, end: block.endAngle)
    let innerH = height(tier: tier, radius: tier.innerRadius)
    let outerH = height(tier: tier, radius: tier.outerRadius)
    return [
      worldPoint(angleDegrees: angles.from, radius: tier.outerRadius, height: outerH),
      worldPoint(angleDegrees: angles.to, radius: tier.outerRadius, height: outerH),
      worldPoint(angleDegrees: angles.to, radius: tier.innerRadius, height: innerH),
      worldPoint(angleDegrees: angles.from, radius: tier.innerRadius, height: innerH)
    ]
  }

  /// 描画用に外弧・内弧をサンプリングした輪郭（閉じた多角形の頂点）。
  static func blockOutlineWorldPoints(
    block: VenueBlock,
    tier: VenueTier,
    arcSamples: Int = 6
  ) -> [Point3D] {
    let angles = cornerAngles(start: block.startAngle, end: block.endAngle)
    let sweep = angles.to - angles.from
    if sweep >= 359.9 {
      // アリーナ概位置など全周: 外円のみを多角形近似
      let steps = max(arcSamples * 4, 16)
      var points: [Point3D] = []
      let h = height(tier: tier, radius: tier.outerRadius)
      for i in 0..<steps {
        let angle = 360.0 * Double(i) / Double(steps)
        points.append(worldPoint(angleDegrees: angle, radius: tier.outerRadius, height: h))
      }
      return points
    }

    let steps = max(arcSamples, 2)
    var points: [Point3D] = []
    let outerH = height(tier: tier, radius: tier.outerRadius)
    let innerH = height(tier: tier, radius: tier.innerRadius)
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = angles.from + sweep * t
      points.append(worldPoint(angleDegrees: angle, radius: tier.outerRadius, height: outerH))
    }
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = angles.to - sweep * t
      points.append(worldPoint(angleDegrees: angle, radius: tier.innerRadius, height: innerH))
    }
    return points
  }

  /// ワールド点を透視投影。カメラ背面は nil。
  static func project(_ point: Point3D, camera: Camera) -> ProjectedPoint? {
    let relX = point.x - camera.position.x
    let relY = point.y - camera.position.y
    let relZ = point.z - camera.position.z

    // 視線は −Z。pitch > 0 で見下ろす（X 軸まわり）。
    let cosP = cos(camera.pitchRadians)
    let sinP = sin(camera.pitchRadians)
    // カメラ空間: X 右、Y 上、depth 前方（ステージ方向が正）
    let camX = relX
    let forwardHorizontal = -relZ
    let camY = relY * cosP - forwardHorizontal * sinP
    let depth = relY * sinP + forwardHorizontal * cosP

    guard depth > 0.5 else { return nil }
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

  /// ブロック輪郭の投影と代表深度（遠いほど大きい = 先に描く）。
  static func projectBlockOutline(
    block: VenueBlock,
    tier: VenueTier,
    camera: Camera,
    arcSamples: Int = 6
  ) -> (points: [ProjectedPoint], depth: Double)? {
    let world = blockOutlineWorldPoints(block: block, tier: tier, arcSamples: arcSamples)
    guard let projected = projectPoints(world, camera: camera), !projected.isEmpty else {
      return nil
    }
    let depth = projected.map(\.depth).reduce(0, +) / Double(projected.count)
    return (projected, depth)
  }

  /// 投影座標のバウンディングボックス（フィット用）。
  static func bounds(of points: [ProjectedPoint]) -> CGRect? {
    guard let first = points.first else { return nil }
    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y
    for p in points.dropFirst() {
      minX = min(minX, p.x)
      maxX = max(maxX, p.x)
      minY = min(minY, p.y)
      maxY = max(maxY, p.y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// 投影平面 → 画面座標。`bounds` を `rect` にフィット（Y は上がステージ側になるよう反転しない: 投影の +Y が上）。
  static func screenPoint(
    _ projected: ProjectedPoint,
    bounds: CGRect,
    in rect: CGRect,
    padding: CGFloat = 0.08
  ) -> CGPoint {
    let inset = rect.insetBy(dx: rect.width * padding, dy: rect.height * padding)
    let bw = max(bounds.width, 0.001)
    let bh = max(bounds.height, 0.001)
    let scale = min(inset.width / CGFloat(bw), inset.height / CGFloat(bh))
    let midX = bounds.midX
    let midY = bounds.midY
    return CGPoint(
      x: inset.midX + CGFloat(projected.x - midX) * scale,
      y: inset.midY - CGFloat(projected.y - midY) * scale
    )
  }

  // MARK: - Helpers

  /// JSON の start>end（本塁回りで角度減少）を、小さい角→大きい角のスイープに正規化。
  private static func cornerAngles(start: Double, end: Double) -> (from: Double, to: Double) {
    (from: min(start, end), to: max(start, end))
  }
}
