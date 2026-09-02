import SwiftUI

/// ライブ詳細の `#artist` カード。見た目はレポート画面の ALL ARTISTS
/// （`ArtistArchiveCardView`）をそのまま使い、公式写真が保存されていない
/// チケット向けにライブ検索のバックフィルだけを足したもの。
///
/// レポート画面は同じバックフィルをセクション単位でまとめて回している
/// （`StatisticsView.backfillArtistImages`）が、ここは1チケットぶんの
/// 数枚しか出ないので、`ArtistGridItemView` と同じくカード単位で持たせる。
/// 検索結果はメモリ上だけで、レコードには書き戻さない。
struct ArtistArchiveBackfillCardView: View {
  let entry: ArtistArchiveEntry

  @State private var backfillImageUrl: String?
  private let appleMusicService = AppleMusicService()

  private var resolvedEntry: ArtistArchiveEntry {
    guard entry.artistImageUrl == nil, let backfillImageUrl else { return entry }
    return ArtistArchiveEntry(
      id: entry.id,
      name: entry.name,
      lastLiveDateText: entry.lastLiveDateText,
      artistImageUrl: backfillImageUrl
    )
  }

  var body: some View {
    ArtistArchiveCardView(entry: resolvedEntry)
      .task(id: entry.artistImageUrl) {
        // ArtistDetailView のヒーローと同じ 800px URL に解決するので、
        // 遷移先の背景色をここで先読みしておく。
        if let urlString = entry.artistImageUrl {
          DominantColorCache.shared.prewarm(urlString: urlString, mode: .dominant)
          return
        }
        guard backfillImageUrl == nil,
              let url = await appleMusicService.bestMatchArtistImageUrl(for: entry.name)
        else { return }
        let resolved = AppleMusicService.resolvedArtworkURL(url, size: 800)
        backfillImageUrl = resolved
        DominantColorCache.shared.prewarm(urlString: resolved, mode: .dominant)
      }
  }
}
