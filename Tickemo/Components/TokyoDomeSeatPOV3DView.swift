import SwiftUI

/// 東京ドーム常設席の「座席から見た」簡易 3D 模式図（SwiftUI Canvas のみ）。
/// ステージ（外野中央）を注視。ハイライトは自分の席付近。SceneKit / RealityKit / WKWebView は使わない。
struct TokyoDomeSeatPOV3DView: View {
  let layout: VenueLayout
  let tierId: String
  let blockId: String
  var row: Int? = nil
  var number: Int? = nil

  var body: some View {
    GeometryReader { proxy in
      let canvasRect = CGRect(origin: .zero, size: proxy.size)
      let scene = buildScene()
      let fitBounds = VenueSeatPOV3DProjection.bounds(of: scene.framingPoints)
        ?? CGRect(x: -40, y: -25, width: 80, height: 55)
      // 余白を抑え、ステージ〜手前席が画面を占めるようにする
      let paddedBounds = fitBounds.insetBy(
        dx: -fitBounds.width * 0.04,
        dy: -fitBounds.height * 0.06
      )

      Canvas { context, _ in
        drawBackground(context: context, in: canvasRect)

        for band in scene.farBands {
          drawPolygon(
            band.points,
            context: context,
            bounds: paddedBounds,
            in: canvasRect,
            fill: Color.secondary.opacity(0.30),
            stroke: Color.secondary.opacity(0.55),
            lineWidth: 0.8,
            padding: 0.04
          )
        }

        drawPolygon(
          scene.arenaFloor,
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          fill: Color.green.opacity(0.32),
          stroke: Color.secondary.opacity(0.4),
          lineWidth: 0.9,
          padding: 0.04
        )

        let stageFill = Color(red: 1.0, green: 0.55, blue: 0.12)
        drawPolygon(
          scene.stageFront,
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          fill: stageFill.opacity(0.7),
          stroke: stageFill,
          lineWidth: 1,
          padding: 0.04
        )
        drawPolygon(
          scene.stageTop,
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          fill: stageFill.opacity(0.95),
          stroke: stageFill,
          lineWidth: 1.3,
          padding: 0.04
        )
        drawStageLabel(
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          points: scene.stageTop
        )

        for band in scene.sideBands {
          drawPolygon(
            band.points,
            context: context,
            bounds: paddedBounds,
            in: canvasRect,
            fill: Color.secondary.opacity(0.22),
            stroke: Color.secondary.opacity(0.5),
            lineWidth: 0.7,
            padding: 0.04
          )
        }

        drawPolygon(
          scene.seatMarker,
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          fill: Color.accentColor.opacity(0.8),
          stroke: Color.accentColor,
          lineWidth: 2,
          padding: 0.04
        )
        drawSeatLabel(
          context: context,
          bounds: paddedBounds,
          in: canvasRect,
          points: scene.seatMarker
        )
      }
    }
    .aspectRatio(3 / 4, contentMode: .fit)
    .accessibilityElement()
    .accessibilityLabel("座席視点 3D（仮）")
    .accessibilityHint(accessibilityHintText)
  }

  private var accessibilityHintText: String {
    if let pair = layout.block(id: blockId) {
      return "\(pair.block.name)からステージ方向を見た模式図"
    }
    return "ステージ方向を見た模式図"
  }

  // MARK: - Scene

  private struct ProjectedBand {
    let points: [VenueSeatPOV3DProjection.ProjectedPoint]
  }

  private struct SceneProjection {
    let arenaFloor: [VenueSeatPOV3DProjection.ProjectedPoint]
    let stageTop: [VenueSeatPOV3DProjection.ProjectedPoint]
    let stageFront: [VenueSeatPOV3DProjection.ProjectedPoint]
    let farBands: [ProjectedBand]
    let sideBands: [ProjectedBand]
    let seatMarker: [VenueSeatPOV3DProjection.ProjectedPoint]

    /// フィットは床・ステージ・スタンド帯のみ。席マーカーは手前で発散しやすいので除外。
    var framingPoints: [VenueSeatPOV3DProjection.ProjectedPoint] {
      let minDepth = 8.0
      return (
        arenaFloor + stageTop + stageFront
          + farBands.flatMap(\.points)
          + sideBands.flatMap(\.points)
      ).filter { $0.depth >= minDepth }
    }
  }

  private func buildScene() -> SceneProjection {
    guard let pair = layout.block(id: blockId) else {
      return emptyScene()
    }
    let tier = layout.tier(id: tierId) ?? pair.tier
    let block = pair.block
    let camera = VenueSeatPOV3DProjection.camera(
      for: block,
      tier: tier,
      row: row,
      number: number
    )
    let camAngle = VenueSeatPOV3DProjection.cameraAngleDegrees(position: camera.position)

    let arena = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
      VenueSeatPOV3DProjection.arenaFloorFanWorldPoints(cameraAngleDegrees: camAngle),
      camera: camera
    )
    let stageTop = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
      VenueSeatPOV3DProjection.stageBoxTopWorldPoints(width: 32, depth: 12, height: 2.2),
      camera: camera
    )
    let stageFront = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
      VenueSeatPOV3DProjection.stageBoxFrontWorldPoints(width: 32, depth: 12, height: 2.2),
      camera: camera
    )
    let marker = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
      VenueSeatPOV3DProjection.seatMarkerWorldPoints(
        block: block,
        tier: tier,
        row: row,
        number: number,
        halfWidth: 2.4,
        halfDepth: 1.8,
        forwardOffset: 8
      ),
      camera: camera
    )

    var farBands: [ProjectedBand] = []
    var sideBands: [ProjectedBand] = []

    // 対面は 2階 or 1階の粗い帯
    let oppositeTier = layout.tier(id: "stand2") ?? tier
    let opposite = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
      VenueSeatPOV3DProjection.oppositeStandBandWorldPoints(
        cameraAngleDegrees: camAngle,
        tier: oppositeTier
      ),
      camera: camera
    )
    if opposite.count >= 3 {
      farBands.append(ProjectedBand(points: opposite))
    }

    if let balcony = layout.tier(id: "balcony") {
      let balconyBand = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
        VenueSeatPOV3DProjection.oppositeStandBandWorldPoints(
          cameraAngleDegrees: camAngle,
          tier: balcony,
          halfSpanDegrees: 45
        ),
        camera: camera
      )
      if balconyBand.count >= 3 {
        farBands.append(ProjectedBand(points: balconyBand))
      }
    }

    let sideTier = layout.tier(id: "stand1") ?? tier
    for sign in [-1.0, 1.0] {
      let side = VenueSeatPOV3DProjection.projectPointsAllowingPartial(
        VenueSeatPOV3DProjection.sideStandBandWorldPoints(
          cameraAngleDegrees: camAngle,
          tier: sideTier,
          sideSign: sign
        ),
        camera: camera
      ).filter { $0.depth >= 4 }
      if side.count >= 3 {
        sideBands.append(ProjectedBand(points: side))
      }
    }

    return SceneProjection(
      arenaFloor: arena,
      stageTop: stageTop,
      stageFront: stageFront,
      farBands: farBands,
      sideBands: sideBands,
      seatMarker: marker
    )
  }

  private func emptyScene() -> SceneProjection {
    SceneProjection(
      arenaFloor: [],
      stageTop: [],
      stageFront: [],
      farBands: [],
      sideBands: [],
      seatMarker: []
    )
  }

  // MARK: - Drawing

  private func drawBackground(context: GraphicsContext, in rect: CGRect) {
    let top = Path(CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.52))
    context.fill(top, with: .color(Color(red: 0.78, green: 0.86, blue: 0.94)))
    let bottom = Path(
      CGRect(x: 0, y: rect.height * 0.42, width: rect.width, height: rect.height * 0.58)
    )
    context.fill(bottom, with: .color(Color(red: 0.91, green: 0.92, blue: 0.93)))
  }

  private func drawPolygon(
    _ points: [VenueSeatPOV3DProjection.ProjectedPoint],
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect,
    fill: Color,
    stroke: Color,
    lineWidth: CGFloat,
    padding: CGFloat = 0.08
  ) {
    guard let first = points.first else { return }
    var path = Path()
    path.move(
      to: VenueSeatPOV3DProjection.screenPoint(
        first,
        bounds: bounds,
        in: rect,
        padding: padding
      )
    )
    for point in points.dropFirst() {
      path.addLine(
        to: VenueSeatPOV3DProjection.screenPoint(
          point,
          bounds: bounds,
          in: rect,
          padding: padding
        )
      )
    }
    path.closeSubpath()
    context.fill(path, with: .color(fill))
    context.stroke(path, with: .color(stroke), lineWidth: lineWidth)
  }

  private func drawStageLabel(
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect,
    points: [VenueSeatPOV3DProjection.ProjectedPoint]
  ) {
    guard !points.isEmpty else { return }
    let screens = points.map {
      VenueSeatPOV3DProjection.screenPoint($0, bounds: bounds, in: rect, padding: 0.04)
    }
    let midX = screens.map(\.x).reduce(0, +) / CGFloat(screens.count)
    let midY = screens.map(\.y).reduce(0, +) / CGFloat(screens.count)
    context.draw(
      Text("ステージ").font(.system(size: 12, weight: .semibold)),
      at: CGPoint(x: midX, y: midY),
      anchor: .center
    )
  }

  private func drawSeatLabel(
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect,
    points: [VenueSeatPOV3DProjection.ProjectedPoint]
  ) {
    guard !points.isEmpty else { return }
    let screens = points.map {
      VenueSeatPOV3DProjection.screenPoint($0, bounds: bounds, in: rect, padding: 0.04)
    }
    let midX = screens.map(\.x).reduce(0, +) / CGFloat(screens.count)
    let midY = screens.map(\.y).reduce(0, +) / CGFloat(screens.count)
    context.draw(
      Text("席").font(.system(size: 11, weight: .bold)),
      at: CGPoint(x: midX, y: midY),
      anchor: .center
    )
  }
}

#if DEBUG
extension TokyoDomeSeatPOV3DView {
  static func debugHost(seatRaw: String = "1階 3塁側 20通路 12列 5番") -> some View {
    TokyoDomeSeatPOV3DDebugHost(seatRaw: seatRaw)
  }
}

private struct TokyoDomeSeatPOV3DDebugHost: View {
  let seatRaw: String
  @State private var layout: VenueLayout?
  @State private var tierId = ""
  @State private var blockId = ""
  @State private var row: Int?
  @State private var number: Int?
  @State private var resolutionLabel = ""

  var body: some View {
    NavigationStack {
      Group {
        if let layout, !blockId.isEmpty {
          VStack(spacing: 12) {
            Text(seatRaw)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(resolutionLabel)
              .font(.caption)
              .frame(maxWidth: .infinity, alignment: .leading)
            TokyoDomeSeatPOV3DView(
              layout: layout,
              tierId: tierId,
              blockId: blockId,
              row: row,
              number: number
            )
            .padding(.horizontal)
            Text("自分の席付近をアクセント色で示しています（仮）")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
          }
          .padding()
        } else {
          ContentUnavailableView("レイアウトを読めませんでした", systemImage: "eye")
        }
      }
      .navigationTitle("座席視点 3D（仮）")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear(perform: load)
    }
  }

  private func load() {
    do {
      let loaded = try VenueLayout.tokyoDome()
      layout = loaded
      let resolution = SeatResolver.resolve(rawSeat: seatRaw, layout: loaded)
      let input = SeatInputParser.parse(seatRaw)
      row = input.row
      number = input.number
      switch resolution {
      case .resolved(let seat), .approximate(let seat):
        tierId = seat.tierId
        blockId = seat.blockId
        let name = loaded.block(id: seat.blockId)?.block.name ?? seat.blockId
        let detail: [String] = [
          input.row.map { "\($0)列" },
          input.number.map { "\($0)番" }
        ].compactMap { $0 }
        let suffix = detail.isEmpty ? "" : " / " + detail.joined(separator: " ")
        resolutionLabel = "視点: \(name)\(suffix)"
      case .needsPicker:
        blockId = ""
        resolutionLabel = "要選択（座席を解決できません）"
      case .unsupported:
        blockId = ""
        resolutionLabel = "未対応の座席表記"
      }
    } catch {
      layout = nil
      resolutionLabel = "読込失敗: \(error)"
    }
  }
}
#endif
