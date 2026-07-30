import SwiftUI

/// Exact port of screens/StatisticsScreen.tsx's `ArtistArchiveCard` clip
/// path (`viewBox="0 0 118 121"`): rounded top corners plus a row of 12
/// scalloped notches along the bottom edge. Built in the original 118x121
/// coordinate space, then uniformly scaled + letterboxed to fill `rect` —
/// same technique as TicketStubShape/ShareTicketShape.
struct ArtistArchiveShape: Shape {
  static let baseSize = CGSize(width: 118, height: 121)

  func path(in rect: CGRect) -> Path {
    var path = Path()
    addOutline(to: &path)

    let scale = min(rect.width / Self.baseSize.width, rect.height / Self.baseSize.height)
    let scaledSize = CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
    let offsetX = rect.minX + (rect.width - scaledSize.width) / 2
    let offsetY = rect.minY + (rect.height - scaledSize.height) / 2
    return path
      .applying(CGAffineTransform(scaleX: scale, y: scale))
      .offsetBy(dx: offsetX, dy: offsetY)
  }

  private func addOutline(to path: inout Path) {
    path.move(to: CGPoint(x: 118, y: 117.37))
    path.addCurve(to: CGPoint(x: 114.018, y: 121), control1: CGPoint(x: 115.916, y: 117.37), control2: CGPoint(x: 114.205, y: 118.965))
    path.addLine(to: CGPoint(x: 108.982, y: 121))
    path.addCurve(to: CGPoint(x: 105, y: 117.37), control1: CGPoint(x: 108.795, y: 118.965), control2: CGPoint(x: 107.084, y: 117.37))
    path.addCurve(to: CGPoint(x: 101.018, y: 121), control1: CGPoint(x: 102.916, y: 117.37), control2: CGPoint(x: 101.205, y: 118.965))
    path.addLine(to: CGPoint(x: 95.9824, y: 121))
    path.addCurve(to: CGPoint(x: 92, y: 117.37), control1: CGPoint(x: 95.7955, y: 118.965), control2: CGPoint(x: 94.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 88.0176, y: 121), control1: CGPoint(x: 89.9158, y: 117.37), control2: CGPoint(x: 88.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 82.9824, y: 121))
    path.addCurve(to: CGPoint(x: 79, y: 117.37), control1: CGPoint(x: 82.7955, y: 118.965), control2: CGPoint(x: 81.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 75.0176, y: 121), control1: CGPoint(x: 76.9158, y: 117.37), control2: CGPoint(x: 75.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 69.9824, y: 121))
    path.addCurve(to: CGPoint(x: 66, y: 117.37), control1: CGPoint(x: 69.7955, y: 118.965), control2: CGPoint(x: 68.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 62.0176, y: 121), control1: CGPoint(x: 63.9158, y: 117.37), control2: CGPoint(x: 62.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 56.9824, y: 121))
    path.addCurve(to: CGPoint(x: 53, y: 117.37), control1: CGPoint(x: 56.7955, y: 118.965), control2: CGPoint(x: 55.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 49.0176, y: 121), control1: CGPoint(x: 50.9158, y: 117.37), control2: CGPoint(x: 49.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 43.9824, y: 121))
    path.addCurve(to: CGPoint(x: 40, y: 117.37), control1: CGPoint(x: 43.7955, y: 118.965), control2: CGPoint(x: 42.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 36.0176, y: 121), control1: CGPoint(x: 37.9158, y: 117.37), control2: CGPoint(x: 36.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 30.9824, y: 121))
    path.addCurve(to: CGPoint(x: 27, y: 117.37), control1: CGPoint(x: 30.7955, y: 118.965), control2: CGPoint(x: 29.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 23.0176, y: 121), control1: CGPoint(x: 24.9158, y: 117.37), control2: CGPoint(x: 23.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 17.9824, y: 121))
    path.addCurve(to: CGPoint(x: 14, y: 117.37), control1: CGPoint(x: 17.7955, y: 118.965), control2: CGPoint(x: 16.0842, y: 117.37))
    path.addCurve(to: CGPoint(x: 10.0176, y: 121), control1: CGPoint(x: 11.9158, y: 117.37), control2: CGPoint(x: 10.2045, y: 118.965))
    path.addLine(to: CGPoint(x: 4.98242, y: 121))
    path.addCurve(to: CGPoint(x: 1, y: 117.37), control1: CGPoint(x: 4.79549, y: 118.965), control2: CGPoint(x: 3.08422, y: 117.37))
    path.addCurve(to: CGPoint(x: 0, y: 117.496), control1: CGPoint(x: 0.654731, y: 117.37), control2: CGPoint(x: 0.319595, y: 117.414))
    path.addLine(to: CGPoint(x: 0, y: 9.98633))
    path.addCurve(to: CGPoint(x: 9, y: 0), control1: CGPoint(x: 5.01428, y: 9.71264), control2: CGPoint(x: 9, y: 5.3463))
    path.addLine(to: CGPoint(x: 108.014, y: 0))
    path.addCurve(to: CGPoint(x: 108, y: 0.5), control1: CGPoint(x: 108.005, y: 0.165593), control2: CGPoint(x: 108, y: 0.33227))
    path.addCurve(to: CGPoint(x: 117.5, y: 10), control1: CGPoint(x: 108, y: 5.74671), control2: CGPoint(x: 112.253, y: 10))
    path.addCurve(to: CGPoint(x: 118, y: 9.98633), control1: CGPoint(x: 117.668, y: 10), control2: CGPoint(x: 117.834, y: 9.99492))
    path.addLine(to: CGPoint(x: 118, y: 117.37))
    path.closeSubpath()
  }
}
