import SwiftUI

/// 見切れる端をぼかす横スクロール。`ScrollView(.horizontal,
/// showsIndicators: false)` の置き換えとして使う。列の幅はそのままで、
/// はみ出している側の端だけをフェードさせる（濃さの計算は EdgeFade）。
/// ライブ詳細の #photos で作ったぼかしを、他の横スクロールにも揃えるための部品。
struct EdgeFadingScrollView<Content: View>: View {
  var fadeWidth: CGFloat = 24
  @ViewBuilder var content: Content

  @State private var contentFrame: CGRect = .zero
  @State private var viewportWidth: CGFloat = 0

  private static var coordinateSpaceName: String { "EdgeFadingScrollView" }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      content
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpaceName)) } action: { frame in
          contentFrame = frame
        }
    }
    .coordinateSpace(name: Self.coordinateSpaceName)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      viewportWidth = width
    }
    .mask(edgeMask)
  }

  private var edgeMask: some View {
    let leading = EdgeFade.leading(contentMinX: contentFrame.minX, fadeWidth: fadeWidth)
    let trailing = EdgeFade.trailing(contentMaxX: contentFrame.maxX, viewportWidth: viewportWidth, fadeWidth: fadeWidth)
    return HStack(spacing: 0) {
      LinearGradient(colors: [.black.opacity(1 - leading), .black], startPoint: .leading, endPoint: .trailing)
        .frame(width: fadeWidth)
      Rectangle().fill(.black)
      LinearGradient(colors: [.black, .black.opacity(1 - trailing)], startPoint: .leading, endPoint: .trailing)
        .frame(width: fadeWidth)
    }
  }
}
