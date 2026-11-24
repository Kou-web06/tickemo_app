import SwiftUI

/// 東京ドーム常設席の上から見た 2D 模式図。ハイライトはブロック単位。
/// 本塁が下・外野（ステージ）が上。SceneKit / WebView は使わない。
struct TokyoDomeSeatMapView: View {
  let layout: VenueLayout
  @Binding var highlightedBlockId: String?

  private let maxRadiusMeters: CGFloat

  init(layout: VenueLayout, highlightedBlockId: Binding<String?>) {
    self.layout = layout
    self._highlightedBlockId = highlightedBlockId
    self.maxRadiusMeters = CGFloat(
      layout.tiers.map(\.outerRadius).max() ?? 100
    )
  }

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      let scale = (side * 0.46) / maxRadiusMeters

      ZStack {
        Canvas { context, _ in
          drawField(context: context, center: center, scale: scale)
          for tier in layout.tiers where tier.id != "arena" {
            for block in tier.blocks {
              drawBlock(
                block,
                tier: tier,
                context: context,
                center: center,
                scale: scale,
                highlighted: block.id == highlightedBlockId
              )
            }
          }
          // アリーナ概位置はフィールド上に薄く
          if let arena = layout.tier(id: "arena"),
             let block = arena.blocks.first {
            drawBlock(
              block,
              tier: arena,
              context: context,
              center: center,
              scale: scale,
              highlighted: block.id == highlightedBlockId
            )
          }
          drawStageMarker(context: context, center: center, scale: scale)
          drawHomeMarker(context: context, center: center, scale: scale)
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onEnded { value in
              if let id = hitTest(at: value.location, center: center, scale: scale) {
                highlightedBlockId = id
              }
            }
        )

        // VoiceOver: ブロックごとにアクセシビリティ要素
        ForEach(accessibilityBlocks, id: \.block.id) { item in
          let frame = accessibilityFrame(
            for: item.block,
            tier: item.tier,
            center: center,
            scale: scale
          )
          Color.clear
            .frame(width: max(frame.width, 8), height: max(frame.height, 8))
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement()
            .accessibilityLabel(item.block.name)
            .accessibilityAddTraits(item.block.id == highlightedBlockId ? .isSelected : [])
            .accessibilityAction {
              highlightedBlockId = item.block.id
            }
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("東京ドーム座席図")
  }

  private var accessibilityBlocks: [(tier: VenueTier, block: VenueBlock)] {
    layout.tiers.flatMap { tier in tier.blocks.map { (tier, $0) } }
  }

  // MARK: - Drawing

  private func drawField(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
    let r = 42 * scale
    var field = Path()
    field.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    context.fill(field, with: .color(Color.green.opacity(0.12)))
    context.stroke(field, with: .color(Color.secondary.opacity(0.25)), lineWidth: 1)
  }

  private func drawStageMarker(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
    // 外野中央（角度 0° = 画面上）
    let y = center.y - 38 * scale
    let rect = CGRect(x: center.x - 18, y: y - 6, width: 36, height: 12)
    var path = Path(roundedRect: rect, cornerRadius: 3)
    context.fill(path, with: .color(Color.orange.opacity(0.85)))
    context.draw(
      Text("ステージ").font(.system(size: 8, weight: .semibold)),
      at: CGPoint(x: center.x, y: y),
      anchor: .center
    )
  }

  private func drawHomeMarker(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
    let point = polarToScreen(angleDegrees: 180, radius: 36, center: center, scale: scale)
    var diamond = Path()
    let s: CGFloat = 5
    diamond.move(to: CGPoint(x: point.x, y: point.y - s))
    diamond.addLine(to: CGPoint(x: point.x + s, y: point.y))
    diamond.addLine(to: CGPoint(x: point.x, y: point.y + s))
    diamond.addLine(to: CGPoint(x: point.x - s, y: point.y))
    diamond.closeSubpath()
    context.fill(diamond, with: .color(Color.primary.opacity(0.55)))
  }

  private func drawBlock(
    _ block: VenueBlock,
    tier: VenueTier,
    context: GraphicsContext,
    center: CGPoint,
    scale: CGFloat,
    highlighted: Bool
  ) {
    let path = annularSectorPath(
      inner: tier.innerRadius,
      outer: tier.outerRadius,
      startAngle: block.startAngle,
      endAngle: block.endAngle,
      center: center,
      scale: scale
    )
    if highlighted {
      context.fill(path, with: .color(Color.accentColor.opacity(0.55)))
      context.stroke(path, with: .color(Color.accentColor), lineWidth: 1.5)
    } else {
      context.stroke(path, with: .color(Color.secondary.opacity(0.35)), lineWidth: 0.6)
    }
  }

  // MARK: - Geometry

  /// 角度 0 = 上（外野中央）、反時計回り → 画面座標。
  /// 本塁を下にしたとき CCW は 3塁側（左）へ進むので、x は `-sin`。
  private func polarToScreen(
    angleDegrees: Double,
    radius: Double,
    center: CGPoint,
    scale: CGFloat
  ) -> CGPoint {
    let radians = angleDegrees * .pi / 180
    let r = CGFloat(radius) * scale
    return CGPoint(
      x: center.x - r * CGFloat(sin(radians)),
      y: center.y - r * CGFloat(cos(radians))
    )
  }

  private func annularSectorPath(
    inner: Double,
    outer: Double,
    startAngle: Double,
    endAngle: Double,
    center: CGPoint,
    scale: CGFloat
  ) -> Path {
    // JSON は本塁回りで start>end（角度減少）。扇形は小さい方→大きい方へスイープ。
    let from = min(startAngle, endAngle)
    let to = max(startAngle, endAngle)
    // アリーナ全体 0–360
    let sweepFull = (to - from) >= 359.9

    var path = Path()
    if sweepFull {
      let outerR = CGFloat(outer) * scale
      let innerR = CGFloat(inner) * scale
      path.addEllipse(in: CGRect(
        x: center.x - outerR, y: center.y - outerR,
        width: outerR * 2, height: outerR * 2
      ))
      if innerR > 0.5 {
        path.addEllipse(in: CGRect(
          x: center.x - innerR, y: center.y - innerR,
          width: innerR * 2, height: innerR * 2
        ))
      }
      return path
    }

    let steps = max(Int((to - from) / 2), 4)
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = from + (to - from) * t
      let p = polarToScreen(angleDegrees: angle, radius: outer, center: center, scale: scale)
      if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let angle = to - (to - from) * t
      let p = polarToScreen(angleDegrees: angle, radius: inner, center: center, scale: scale)
      path.addLine(to: p)
    }
    path.closeSubpath()
    return path
  }

  private func hitTest(at point: CGPoint, center: CGPoint, scale: CGFloat) -> String? {
    let dx = point.x - center.x
    let dy = center.y - point.y
    let radius = Double(sqrt(dx * dx + dy * dy) / scale)
    // polarToScreen の x = cx - r·sin(θ) に合わせる
    var angle = atan2(Double(-dx), Double(dy)) * 180 / .pi
    if angle < 0 { angle += 360 }

    // 外側の階を優先（バルコニー → stand2 → stand1 → arena）
    for tier in layout.tiers.reversed() {
      guard radius >= tier.innerRadius, radius <= tier.outerRadius else { continue }
      for block in tier.blocks {
        if angleInBlock(angle, block: block) {
          return block.id
        }
      }
    }
    return nil
  }

  private func angleInBlock(_ angle: Double, block: VenueBlock) -> Bool {
    let a0 = block.startAngle
    let a1 = block.endAngle
    if abs(a1 - a0) >= 359.9 { return true }
    let low = min(a0, a1)
    let high = max(a0, a1)
    return angle >= low && angle <= high
  }

  private func accessibilityFrame(
    for block: VenueBlock,
    tier: VenueTier,
    center: CGPoint,
    scale: CGFloat
  ) -> CGRect {
    let midAngle = (block.startAngle + block.endAngle) / 2
    let midR = (tier.innerRadius + tier.outerRadius) / 2
    let p = polarToScreen(angleDegrees: midAngle, radius: midR, center: center, scale: scale)
    let w = max(CGFloat(abs(block.startAngle - block.endAngle)) * scale * 0.35, 12)
    let h = max(CGFloat(tier.outerRadius - tier.innerRadius) * scale, 12)
    return CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
  }
}

#if DEBUG
extension TokyoDomeSeatMapView {
  /// デバッグシート用。解決できなければハイライトなしで開き、タップで選べる。
  static func debugHost(seatRaw: String = "1階 3塁側 20通路 12列 5番") -> some View {
    TokyoDomeSeatMapDebugHost(seatRaw: seatRaw)
  }
}

private struct TokyoDomeSeatMapDebugHost: View {
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
            TokyoDomeSeatMapView(layout: layout, highlightedBlockId: $highlighted)
              .padding()
            Spacer(minLength: 0)
          }
          .padding()
        } else {
          ContentUnavailableView("レイアウトを読めませんでした", systemImage: "map")
        }
      }
      .navigationTitle("東京ドーム座席図")
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
