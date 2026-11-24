import SwiftUI

/// 東京ドーム常設席の簡易 3D 模式図（SwiftUI Canvas + 透視投影のみ）。
/// 本塁下寄り視点。ハイライトはブロック単位。SceneKit / RealityKit / WKWebView は使わない。
struct TokyoDomeSeatMap3DView: View {
  let layout: VenueLayout
  @Binding var highlightedBlockId: String?

  private let camera: VenueSeatMap3DProjection.Camera

  init(
    layout: VenueLayout,
    highlightedBlockId: Binding<String?>,
    camera: VenueSeatMap3DProjection.Camera? = nil
  ) {
    self.layout = layout
    self._highlightedBlockId = highlightedBlockId
    let maxR = layout.tiers.map(\.outerRadius).max() ?? 98
    self.camera = camera ?? .homePlateViewpoint(maxOuterRadius: maxR)
  }

  var body: some View {
    GeometryReader { proxy in
      let canvasRect = CGRect(origin: .zero, size: proxy.size)
      let projected = projectedBlocks()
      let allPoints = projected.flatMap(\.points)
      let fitBounds = VenueSeatMap3DProjection.bounds(of: allPoints)
        ?? CGRect(x: -40, y: -30, width: 80, height: 60)

      ZStack {
        Canvas { context, _ in
          drawField(context: context, bounds: fitBounds, in: canvasRect)
          // 遠いブロックから描く
          for item in projected.sorted(by: { $0.depth > $1.depth }) {
            drawBlock(
              item,
              context: context,
              bounds: fitBounds,
              in: canvasRect,
              highlighted: item.blockId == highlightedBlockId
            )
          }
          drawStageMarker(context: context, bounds: fitBounds, in: canvasRect)
          drawHomeMarker(context: context, bounds: fitBounds, in: canvasRect)
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onEnded { value in
              if let id = hitTest(
                at: value.location,
                projected: projected,
                bounds: fitBounds,
                in: canvasRect
              ) {
                highlightedBlockId = id
              }
            }
        )

        ForEach(projected, id: \.blockId) { item in
          let frame = accessibilityFrame(
            for: item,
            bounds: fitBounds,
            in: canvasRect
          )
          Color.clear
            .frame(width: max(frame.width, 10), height: max(frame.height, 10))
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement()
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(item.blockId == highlightedBlockId ? .isSelected : [])
            .accessibilityAction {
              highlightedBlockId = item.blockId
            }
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("東京ドーム座席図（3D）")
  }

  // MARK: - Projection cache

  private struct ProjectedBlock {
    let blockId: String
    let name: String
    let points: [VenueSeatMap3DProjection.ProjectedPoint]
    let depth: Double
  }

  private func projectedBlocks() -> [ProjectedBlock] {
    var result: [ProjectedBlock] = []
    for tier in layout.tiers {
      for block in tier.blocks {
        // アリーナ全周はフィールド描画に任せて輪郭だけ薄く
        guard let outline = VenueSeatMap3DProjection.projectBlockOutline(
          block: block,
          tier: tier,
          camera: camera,
          arcSamples: tier.id == "arena" ? 12 : 5
        ) else { continue }
        result.append(
          ProjectedBlock(
            blockId: block.id,
            name: block.name,
            points: outline.points,
            depth: outline.depth
          )
        )
      }
    }
    return result
  }

  // MARK: - Drawing

  private func drawField(
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect
  ) {
    let samples = 24
    var path = Path()
    var started = false
    for i in 0...samples {
      let angle = 360.0 * Double(i) / Double(samples)
      let world = VenueSeatMap3DProjection.worldPoint(
        angleDegrees: angle,
        radius: 42,
        height: 0
      )
      guard let projected = VenueSeatMap3DProjection.project(world, camera: camera) else {
        continue
      }
      let screen = VenueSeatMap3DProjection.screenPoint(projected, bounds: bounds, in: rect)
      if started {
        path.addLine(to: screen)
      } else {
        path.move(to: screen)
        started = true
      }
    }
    guard started else { return }
    path.closeSubpath()
    context.fill(path, with: .color(Color.green.opacity(0.14)))
    context.stroke(path, with: .color(Color.secondary.opacity(0.28)), lineWidth: 1)
  }

  private func drawBlock(
    _ item: ProjectedBlock,
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect,
    highlighted: Bool
  ) {
    guard let first = item.points.first else { return }
    var path = Path()
    let start = VenueSeatMap3DProjection.screenPoint(first, bounds: bounds, in: rect)
    path.move(to: start)
    for point in item.points.dropFirst() {
      path.addLine(to: VenueSeatMap3DProjection.screenPoint(point, bounds: bounds, in: rect))
    }
    path.closeSubpath()

    if highlighted {
      context.fill(path, with: .color(Color.accentColor.opacity(0.55)))
      context.stroke(path, with: .color(Color.accentColor), lineWidth: 1.6)
    } else {
      context.fill(path, with: .color(Color.secondary.opacity(0.06)))
      context.stroke(path, with: .color(Color.secondary.opacity(0.32)), lineWidth: 0.55)
    }
  }

  private func drawStageMarker(
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect
  ) {
    let world = VenueSeatMap3DProjection.worldPoint(angleDegrees: 0, radius: 38, height: 1.2)
    guard let projected = VenueSeatMap3DProjection.project(world, camera: camera) else { return }
    let center = VenueSeatMap3DProjection.screenPoint(projected, bounds: bounds, in: rect)
    let marker = CGRect(x: center.x - 22, y: center.y - 7, width: 44, height: 14)
    var path = Path(roundedRect: marker, cornerRadius: 3)
    context.fill(path, with: .color(Color.orange.opacity(0.88)))
    context.draw(
      Text("ステージ").font(.system(size: 8, weight: .semibold)),
      at: center,
      anchor: .center
    )
  }

  private func drawHomeMarker(
    context: GraphicsContext,
    bounds: CGRect,
    in rect: CGRect
  ) {
    let world = VenueSeatMap3DProjection.worldPoint(angleDegrees: 180, radius: 36, height: 0.2)
    guard let projected = VenueSeatMap3DProjection.project(world, camera: camera) else { return }
    let point = VenueSeatMap3DProjection.screenPoint(projected, bounds: bounds, in: rect)
    var diamond = Path()
    let s: CGFloat = 6
    diamond.move(to: CGPoint(x: point.x, y: point.y - s))
    diamond.addLine(to: CGPoint(x: point.x + s, y: point.y))
    diamond.addLine(to: CGPoint(x: point.x, y: point.y + s))
    diamond.addLine(to: CGPoint(x: point.x - s, y: point.y))
    diamond.closeSubpath()
    context.fill(diamond, with: .color(Color.primary.opacity(0.55)))
  }

  // MARK: - Hit / a11y

  private func hitTest(
    at location: CGPoint,
    projected: [ProjectedBlock],
    bounds: CGRect,
    in rect: CGRect
  ) -> String? {
    // 近いブロック優先
    for item in projected.sorted(by: { $0.depth < $1.depth }) {
      let path = screenPath(for: item, bounds: bounds, in: rect)
      if path.contains(location) {
        return item.blockId
      }
    }
    return nil
  }

  private func screenPath(
    for item: ProjectedBlock,
    bounds: CGRect,
    in rect: CGRect
  ) -> Path {
    var path = Path()
    guard let first = item.points.first else { return path }
    path.move(to: VenueSeatMap3DProjection.screenPoint(first, bounds: bounds, in: rect))
    for point in item.points.dropFirst() {
      path.addLine(to: VenueSeatMap3DProjection.screenPoint(point, bounds: bounds, in: rect))
    }
    path.closeSubpath()
    return path
  }

  private func accessibilityFrame(
    for item: ProjectedBlock,
    bounds: CGRect,
    in rect: CGRect
  ) -> CGRect {
    let screens = item.points.map {
      VenueSeatMap3DProjection.screenPoint($0, bounds: bounds, in: rect)
    }
    guard let first = screens.first else {
      return .zero
    }
    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y
    for p in screens.dropFirst() {
      minX = min(minX, p.x)
      maxX = max(maxX, p.x)
      minY = min(minY, p.y)
      maxY = max(maxY, p.y)
    }
    return CGRect(x: minX, y: minY, width: max(maxX - minX, 12), height: max(maxY - minY, 12))
  }
}

#if DEBUG
extension TokyoDomeSeatMap3DView {
  static func debugHost(seatRaw: String = "1階 3塁側 20通路 12列 5番") -> some View {
    TokyoDomeSeatMap3DDebugHost(seatRaw: seatRaw)
  }
}

private struct TokyoDomeSeatMap3DDebugHost: View {
  let seatRaw: String
  @State private var highlighted: String?
  @State private var layout: VenueLayout?
  @State private var resolutionLabel = ""

  var body: some View {
    NavigationStack {
      Group {
        if let layout {
          VStack(spacing: 12) {
            Text(seatRaw)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(resolutionLabel)
              .font(.caption)
              .frame(maxWidth: .infinity, alignment: .leading)
            TokyoDomeSeatMap3DView(layout: layout, highlightedBlockId: $highlighted)
              .padding()
            Spacer(minLength: 0)
          }
          .padding()
        } else {
          ContentUnavailableView("レイアウトを読めませんでした", systemImage: "map")
        }
      }
      .navigationTitle("東京ドーム座席図（3D）")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        do {
          let loaded = try VenueLayout.tokyoDome()
          layout = loaded
          let resolution = SeatResolver.resolve(rawSeat: seatRaw, layout: loaded)
          switch resolution {
          case .resolved(let seat):
            highlighted = seat.blockId
            let name = loaded.block(id: seat.blockId)?.block.name ?? seat.blockId
            resolutionLabel = "解決: \(name)"
          case .approximate(let seat):
            highlighted = seat.blockId
            let name = loaded.block(id: seat.blockId)?.block.name ?? seat.blockId
            resolutionLabel = "概位置: \(name)"
          case .needsPicker:
            highlighted = nil
            resolutionLabel = "要選択（ブロックをタップ）"
          case .unsupported:
            highlighted = nil
            resolutionLabel = "未対応の座席表記"
          }
        } catch {
          layout = nil
          resolutionLabel = "読込失敗: \(error)"
        }
      }
    }
  }
}
#endif
