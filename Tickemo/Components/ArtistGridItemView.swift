import SwiftUI

/// Ports components/ArtistGridItem.tsx: a square tile with a cover photo
/// (or a person-icon placeholder), a bottom gradient for legibility, the
/// artist name, and two pill badges (latest past show date, show count).
struct ArtistGridItemView: View {
  let tile: ArtistGrouping.Tile

  // Live MusicKit lookup for tiles saved without an official photo (e.g.
  // tickets created before ArtistSearchField existed) — a top-1 search by
  // artist name, cached in-memory only, never persisted onto the record.
  @State private var backfillImageUrl: String?
  private let appleMusicService = AppleMusicService()

  private var resolvedArtistImageUrl: String? {
    tile.artistImageUrl ?? backfillImageUrl
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        photo

        LinearGradient(
          colors: [Color.black.opacity(0.95), Color.black.opacity(0)],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: proxy.size.height * 0.62)
        .frame(maxHeight: .infinity, alignment: .bottom)

        VStack(alignment: .leading, spacing: 6) {
          Text(tile.name)
            .font(appFont.bold(14))
            .foregroundStyle(.white)
            .lineLimit(1)

          HStack(spacing: 6) {
            badge(tile.latestPastDateText.replacingOccurrences(of: ".", with: "/"))
            badge("\(tile.showCount)")
          }
        }
        .padding(12)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 6)
    .task(id: resolvedArtistImageUrl) {
      // ArtistDetailView のヒーローと同じ URL（800px 解決済み）なので、
      // ここで dominant モードの背景色を先読みしておくと詳細画面を
      // ラグなしで開ける。URL 未解決のタイルはまずバックフィル検索し、
      // URL が入ると task(id:) が再実行されて先読みに到達する。
      if let urlString = resolvedArtistImageUrl {
        DominantColorCache.shared.prewarm(urlString: urlString, mode: .dominant)
        return
      }
      guard let url = await appleMusicService.bestMatchArtistImageUrl(for: tile.name) else { return }
      backfillImageUrl = AppleMusicService.resolvedArtworkURL(url, size: 800)
    }
  }

  // Fallback chain: saved official artist photo, else a live MusicKit
  // backfill search (see .task above, for tickets saved before
  // ArtistSearchField existed), else the artist's own most recent ticket
  // cover photo, else a generic placeholder icon. AsyncImage's placeholder
  // closure covers both "still loading" and "failed to load" (its default
  // 2-closure initializer treats both phases the same), so a broken artist
  // photo URL correctly falls through to the cover photo rather than
  // showing nothing.
  @ViewBuilder
  private var photo: some View {
    if let urlString = resolvedArtistImageUrl, let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        coverOrPlaceholder
      }
    } else {
      coverOrPlaceholder
    }
  }

  @ViewBuilder
  private var coverOrPlaceholder: some View {
    if let data = tile.coverImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color(.tertiarySystemBackground)
        HugeIconView(icon: HugeIcons.user, size: 40)
          .foregroundStyle(Color(white: 0.77))
      }
    }
  }

  private func badge(_ text: String) -> some View {
    Text(text)
      .font(appFont.bold(11))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Color(red: 0.604, green: 0.486, blue: 0.973))
      .clipShape(Capsule())
  }
}
