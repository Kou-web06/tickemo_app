import SwiftUI

/// Renders a `HugeIcon`'s path/circle elements, built in the fixed 24x24
/// coordinate space every HugeIcons icon uses (see Support/HugeIcon.swift),
/// then uniformly scaled to fit `rect` — same technique as TicketStubShape.
struct HugeIconShape: Shape {
  static let baseSize = CGSize(width: 24, height: 24)

  let icon: HugeIcon

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for element in icon.elements {
      switch element {
      case .path(let d):
        path.addPath(HugeIconPath.parse(d))
      case .circle(let cx, let cy, let r):
        path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
      }
    }

    let scale = min(rect.width / Self.baseSize.width, rect.height / Self.baseSize.height)
    let scaledWidth = Self.baseSize.width * scale
    let scaledHeight = Self.baseSize.height * scale
    let dx = rect.minX + (rect.width - scaledWidth) / 2
    let dy = rect.minY + (rect.height - scaledHeight) / 2
    return path
      .applying(CGAffineTransform(scaleX: scale, y: scale))
      .offsetBy(dx: dx, dy: dy)
  }
}

/// Drop-in replacement for `Image(systemName:)`, rendering a HugeIcons
/// stroke icon at a fixed square size. Color comes from `.foregroundStyle()`
/// as usual; `weight` scales the stroke width the same way SF Symbols'
/// `.fontWeight()` would (HugeIcons' own source icons use strokeWidth 1.5
/// at their native 24pt size, so that's the default).
struct HugeIconView: View {
  var icon: HugeIcon
  var size: CGFloat = 20
  var weight: CGFloat = 1.5

  var body: some View {
    HugeIconShape(icon: icon)
      .stroke(style: StrokeStyle(lineWidth: weight * size / 24, lineCap: .round, lineJoin: .round))
      .frame(width: size, height: size)
  }
}

/// Drop-in replacement for `Label(_:systemImage:)`.
struct HugeIconLabel<Title: View>: View {
  private var icon: HugeIcon
  private var size: CGFloat
  private var title: Title

  init(icon: HugeIcon, size: CGFloat = 17, @ViewBuilder title: () -> Title) {
    self.icon = icon
    self.size = size
    self.title = title()
  }

  var body: some View {
    HStack(spacing: 6) {
      HugeIconView(icon: icon, size: size)
      title
    }
  }
}

extension HugeIconLabel where Title == Text {
  init(_ titleKey: String, icon: HugeIcon, size: CGFloat = 17) {
    self.init(icon: icon, size: size) { Text(titleKey) }
  }
}

/// Drop-in replacement for `ContentUnavailableView(_:systemImage:description:)`.
struct HugeIconUnavailableView: View {
  var title: String
  var icon: HugeIcon
  var description: Text?

  var body: some View {
    VStack(spacing: 8) {
      HugeIconView(icon: icon, size: 52, weight: 1.25)
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
      Text(title)
        .font(.title2.weight(.semibold))
      if let description {
        description
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
