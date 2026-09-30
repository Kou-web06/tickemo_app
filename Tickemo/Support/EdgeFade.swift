import CoreGraphics

/// 横スクロールの見切れる端をぼかすときの、左右それぞれのフェードの濃さ
/// （0 = ぼかさない 〜 1 = 最大）。はみ出している側だけをぼかし、はみ出し量が
/// フェード幅に満たないうちは濃さもそれに比例させて、スクロール量に合わせて
/// なめらかに出入りさせる。静止時の先頭（左端がはみ出していない）はぼけない。
enum EdgeFade {
  /// コンテンツが左にスクロールして隠れている量に応じた左端の濃さ。
  /// `contentMinX` はスクロール領域の座標系でのコンテンツの左端（隠れると負）
  static func leading(contentMinX: CGFloat, fadeWidth: CGFloat) -> CGFloat {
    clamp(-contentMinX / fadeWidth)
  }

  /// コンテンツが右にまだはみ出している量に応じた右端の濃さ
  static func trailing(contentMaxX: CGFloat, viewportWidth: CGFloat, fadeWidth: CGFloat) -> CGFloat {
    clamp((contentMaxX - viewportWidth) / fadeWidth)
  }

  private static func clamp(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}
