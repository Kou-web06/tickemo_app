import SwiftUI

/// Ports ShareImageGenerator.tsx's decorative BARCODE_SVG for the CD share
/// card — a purely decorative bar pattern (encodes no real data), scaled
/// from its 315x101 source coordinate space to fill this view's frame.
struct ShareBarcodeView: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      let scaleX = size.width / ShareCardData.cdBarcodeSourceSize.width
      for bar in ShareCardData.cdBarcodeBars {
        let rightX = bar.rightEdgeX * scaleX
        let width = bar.thickness * scaleX
        let rect = CGRect(x: rightX - width, y: 0, width: width, height: size.height)
        context.fill(Path(rect), with: .color(color))
      }
    }
  }
}
