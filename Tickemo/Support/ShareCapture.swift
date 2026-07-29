import SwiftUI

/// Which shareable card to render and capture, and the parameters each
/// card type needs (ports the RN `cardType` switch plus the per-card props
/// ShareImageGenerator.tsx threads through).
enum ShareCardKind {
  case ticket(record: CD_ChekiRecord, blurredBackground: Bool)
  case cd(record: CD_ChekiRecord, textColor: ShareCDTextColor, username: String?)
  case receipt(record: CD_ChekiRecord, username: String?)
}

/// `ImageRenderer`-based PNG capture, replacing RN's
/// `react-native-view-shot` `captureRef`. The canvas sizes below are
/// already literal target pixel dimensions (not "points to be multiplied
/// by device scale"), so the card views are hosted at these numbers
/// directly as SwiftUI points, and `ImageRenderer.scale` is pinned to `1`
/// — otherwise `ImageRenderer` would multiply by the current device's
/// display scale (2x/3x) and produce an oversized image.
enum ShareCapture {
  static let ticketCanvasSize = CGSize(width: 1480, height: 1200)
  static let cdCanvasSize = CGSize(width: 1480, height: 1200)
  static let receiptCanvasSize = CGSize(width: 826, height: 2044)

  @MainActor
  static func capturePNG(_ kind: ShareCardKind) -> Data? {
    let size: CGSize
    let view: AnyView

    switch kind {
    case .ticket(let record, let blurredBackground):
      size = ticketCanvasSize
      view = AnyView(ShareTicketCardView(record: record, showsBlurredBackground: blurredBackground))
    case .cd(let record, let textColor, let username):
      size = cdCanvasSize
      view = AnyView(ShareCDCardView(record: record, textColor: textColor, username: username))
    case .receipt(let record, let username):
      size = receiptCanvasSize
      view = AnyView(ShareReceiptCardView(record: record, username: username))
    }

    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    guard let uiImage = renderer.uiImage else { return nil }
    return uiImage.pngData()
  }
}
