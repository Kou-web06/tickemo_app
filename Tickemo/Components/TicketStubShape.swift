import SwiftUI

/// Exact port of `components/TicketCard.tsx`'s SVG path (`viewBox="0 0 322 118"`):
/// a physical-ticket-stub silhouette with a perforated notch column at
/// x≈111-119 (8 punched circles + rounded notches top/bottom). Built in the
/// original 322x118 coordinate space, then uniformly scaled to fill `rect`
/// (the aspect ratio is fixed at 118/322, matching how callers size this
/// view: `height = width * 0.366`).
struct TicketStubShape: Shape {
  static let baseSize = CGSize(width: 322, height: 118)

  func path(in rect: CGRect) -> Path {
    var path = Path()
    addOutline(to: &path)
    for index in 0..<8 {
      let centerY: CGFloat = 13 + CGFloat(index) * 13
      path.addEllipse(in: CGRect(x: 115 - 4, y: centerY - 4, width: 8, height: 8))
    }

    let scaleX = rect.width / Self.baseSize.width
    let scaleY = rect.height / Self.baseSize.height
    return path
      .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
      .offsetBy(dx: rect.minX, dy: rect.minY)
  }

  private func addOutline(to path: inout Path) {
    path.move(to: CGPoint(x: 111, y: 0))
    path.addCurve(to: CGPoint(x: 115, y: 4), control1: CGPoint(x: 111, y: 2.20914), control2: CGPoint(x: 112.791, y: 4))
    path.addCurve(to: CGPoint(x: 119, y: 0), control1: CGPoint(x: 117.209, y: 4), control2: CGPoint(x: 119, y: 2.20914))
    path.addLine(to: CGPoint(x: 313.014, y: 0))
    path.addCurve(to: CGPoint(x: 321.791, y: 8.9707), control1: CGPoint(x: 313.261, y: 4.77874), control2: CGPoint(x: 317.04, y: 8.62009))
    path.addLine(to: CGPoint(x: 321.791, y: 108.028))
    path.addCurve(to: CGPoint(x: 313, y: 117.5), control1: CGPoint(x: 316.876, y: 108.391), control2: CGPoint(x: 313, y: 112.492))
    path.addCurve(to: CGPoint(x: 313.014, y: 118), control1: CGPoint(x: 313, y: 117.668), control2: CGPoint(x: 313.005, y: 117.834))
    path.addLine(to: CGPoint(x: 118.874, y: 118))
    path.addCurve(to: CGPoint(x: 119, y: 117), control1: CGPoint(x: 118.956, y: 117.68), control2: CGPoint(x: 119, y: 117.345))
    path.addCurve(to: CGPoint(x: 115, y: 113), control1: CGPoint(x: 119, y: 114.791), control2: CGPoint(x: 117.209, y: 113))
    path.addCurve(to: CGPoint(x: 111, y: 117), control1: CGPoint(x: 112.791, y: 113), control2: CGPoint(x: 111, y: 114.791))
    path.addCurve(to: CGPoint(x: 111.126, y: 118), control1: CGPoint(x: 111, y: 117.345), control2: CGPoint(x: 111.044, y: 117.68))
    path.addLine(to: CGPoint(x: 9, y: 118))
    path.addCurve(to: CGPoint(x: 0, y: 109), control1: CGPoint(x: 9, y: 113.029), control2: CGPoint(x: 4.97056, y: 109))
    path.addLine(to: CGPoint(x: 0, y: 8.98633))
    path.addCurve(to: CGPoint(x: 0.5, y: 9), control1: CGPoint(x: 0.165593, y: 8.99492), control2: CGPoint(x: 0.33227, y: 9))
    path.addCurve(to: CGPoint(x: 9.98633, y: 0), control1: CGPoint(x: 5.57897, y: 9), control2: CGPoint(x: 9.7263, y: 5.01426))
    path.addLine(to: CGPoint(x: 111, y: 0))
    path.closeSubpath()
  }
}
