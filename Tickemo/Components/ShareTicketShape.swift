import SwiftUI

/// Exact port of `components/EditableTicketPreviewCard.tsx`'s
/// `TICKET_SHAPE_PATH_D` (viewBox `0 0 352 148`) — the ticket-stub
/// silhouette used by the shareable Ticket card. This is a distinct shape
/// from `TicketStubShape` (viewBox `322 118`, used by the list-row ticket
/// card): different proportions, different perforation-column position.
/// Built in the original 352x148 coordinate space, then uniformly scaled
/// to fill `rect`, same technique as `TicketStubShape`. The 8 perforation
/// dots are each drawn as 4 cubic Beziers in the original SVG (a
/// rounded-square approximation of a circle); as with `TicketStubShape`,
/// simplified here to plain circles via `addEllipse`, which is visually
/// identical at this size.
struct ShareTicketShape: Shape {
  static let baseSize = CGSize(width: 352, height: 148)

  func path(in rect: CGRect) -> Path {
    var path = Path()
    addOutline(to: &path)
    for index in 0..<8 {
      let centerY: CGFloat = 28 + CGFloat(index) * 13
      path.addEllipse(in: CGRect(x: 130 - 4, y: centerY - 4, width: 8, height: 8))
    }

    let scaleX = rect.width / Self.baseSize.width
    let scaleY = rect.height / Self.baseSize.height
    return path
      .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
      .offsetBy(dx: rect.minX, dy: rect.minY)
  }

  private func addOutline(to path: inout Path) {
    path.move(to: CGPoint(x: 126, y: 15))
    path.addCurve(to: CGPoint(x: 130, y: 19), control1: CGPoint(x: 126, y: 17.2091), control2: CGPoint(x: 127.791, y: 19))
    path.addCurve(to: CGPoint(x: 134, y: 15), control1: CGPoint(x: 132.209, y: 19), control2: CGPoint(x: 134, y: 17.2091))
    path.addLine(to: CGPoint(x: 328.014, y: 15))
    path.addCurve(to: CGPoint(x: 336.791, y: 23.9707), control1: CGPoint(x: 328.261, y: 19.7787), control2: CGPoint(x: 332.04, y: 23.6201))
    path.addLine(to: CGPoint(x: 336.791, y: 123.028))
    path.addCurve(to: CGPoint(x: 328, y: 132.5), control1: CGPoint(x: 331.876, y: 123.391), control2: CGPoint(x: 328, y: 127.492))
    path.addCurve(to: CGPoint(x: 328.014, y: 133), control1: CGPoint(x: 328, y: 132.668), control2: CGPoint(x: 328.005, y: 132.834))
    path.addLine(to: CGPoint(x: 133.874, y: 133))
    path.addCurve(to: CGPoint(x: 134, y: 132), control1: CGPoint(x: 133.956, y: 132.68), control2: CGPoint(x: 134, y: 132.345))
    path.addCurve(to: CGPoint(x: 130, y: 128), control1: CGPoint(x: 134, y: 129.791), control2: CGPoint(x: 132.209, y: 128))
    path.addCurve(to: CGPoint(x: 126, y: 132), control1: CGPoint(x: 127.791, y: 128), control2: CGPoint(x: 126, y: 129.791))
    path.addCurve(to: CGPoint(x: 126.126, y: 133), control1: CGPoint(x: 126, y: 132.345), control2: CGPoint(x: 126.044, y: 132.68))
    path.addLine(to: CGPoint(x: 24, y: 133))
    path.addCurve(to: CGPoint(x: 15, y: 124), control1: CGPoint(x: 24, y: 128.029), control2: CGPoint(x: 19.9706, y: 124))
    path.addLine(to: CGPoint(x: 15, y: 23.9863))
    path.addCurve(to: CGPoint(x: 15.5, y: 24), control1: CGPoint(x: 15.1656, y: 23.9949), control2: CGPoint(x: 15.3323, y: 24))
    path.addCurve(to: CGPoint(x: 24.9863, y: 15), control1: CGPoint(x: 20.579, y: 24), control2: CGPoint(x: 24.7263, y: 20.0143))
    path.addLine(to: CGPoint(x: 126, y: 15))
    path.closeSubpath()
  }
}
