import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports StatisticsScreen.tsx's rank medal (`MedalFirstPlaceIcon` etc., from
/// HugeIcons) as a plain colored numbered circle instead — this app has no
/// HugeIcons dependency, and a single-screen icon import isn't worth adding
/// one for. Colors match RN's own rank-color choices.
struct RankBadge: View {
  let rank: Int

  private var fillColor: Color {
    switch rank {
    case 1: Color(red: 0.910, green: 0.831, blue: 0.565) // #E8D490 gold
    case 2: Color(red: 0.773, green: 0.820, blue: 0.847) // #C5D1D8 silver
    case 3: Color(red: 0.773, green: 0.541, blue: 0.416) // #C58A6A bronze
    default: Color(red: 0.718, green: 0.718, blue: 0.718) // #B7B7B7
    }
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    ZStack {
      Circle().fill(fillColor)
      Text("\(rank)")
        .font(appFont.bold(13))
        .foregroundStyle(.white)
    }
    .frame(width: 26, height: 26)
  }
}

/// How a StatisticsRankingRow shows artwork: TOP ARTISTS and TOP SONGS both
/// show a remote artwork URL (an official MusicKit artist photo or a
/// setlist song's artwork — RN never falls back to the user's own ticket
/// cover photo in either ranking), and TOP VENUES shows no image at all
/// (matching RN, which never renders an image slot for venues) rather than
/// a placeholder box.
enum StatisticsRowThumbnail {
  case artworkUrl(String?)
  case none
}

/// Shared row layout reused by TOP ARTISTS / TOP VENUES / TOP SONGS: a
/// RankBadge, an optional thumbnail, a name, and a trailing detail string
/// (e.g. "12 lives" / "5 plays"). `imageShape` matches RN's `RankingItem`
/// prop of the same name — TOP ARTISTS passes `.circle` (artist portraits),
/// everything else defaults to `.square` (album/venue-style artwork).
struct StatisticsRankingRow: View {
  enum ImageShape {
    case circle, square
  }

  let rank: Int
  let name: String
  let detail: String
  let thumbnail: StatisticsRowThumbnail
  var imageShape: ImageShape = .square

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    HStack(spacing: 12) {
      RankBadge(rank: rank)
      thumbnailView
      Text(name)
        .font(appFont.bold(15))
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(detail)
        .font(appFont.regular(13))
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var thumbnailView: some View {
    switch thumbnail {
    case .artworkUrl(let urlString):
      AsyncImage(url: URL(string: urlString ?? "")) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color(.tertiarySystemBackground)
      }
      .frame(width: 36, height: 36)
      .clipShape(clipShape)
    case .none:
      EmptyView()
    }
  }

  private var clipShape: AnyShape {
    switch imageShape {
    case .circle: AnyShape(Circle())
    case .square: AnyShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

/// TOP SONGS 専用の横スクロールカード。海外の音楽ストリーミングアプリ風に、順位メダルを
/// 廃止して（並び順で順位を表現）大きな正方形アートワークを主役にする — TOP ARTISTS/TOP
/// VENUES が使う `StatisticsRankingRow` とはレイアウトが根本的に異なるため共有しない。
struct TopSongCardView: View {
  let song: RankedSong
  let artworkUrl: String?          // 保存済み ?? バックフィル結果
  @Environment(\.appFontChoice) private var appFont
  private let side: CGFloat = 115

  var body: some View {
    VStack(alignment: .center, spacing: 8) {
      artwork
        .frame(width: side, height: side)
        .clipped()                                   // 角丸なし
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
      Text("\(song.count) plays")
        .font(appFont.bold(13))
        .foregroundStyle(accentPurple)
        .padding(.horizontal, 34)
        .padding(.vertical, 5)
        .background(Capsule().fill(accentPurple.opacity(0.14)))
      Text(song.name)
        .font(appFont.bold(14))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
      if let artist = song.artistName, !artist.isEmpty {
        Text(artist)
          .font(appFont.regular(12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(width: side, alignment: .leading)
  }

  @ViewBuilder
  private var artwork: some View {
    if let urlString = artworkUrl, let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        fallback
      }
    } else {
      fallback
    }
  }

  private var fallback: some View {
    ZStack {
      Color(.tertiarySystemBackground)
      HugeIconView(icon: HugeIcons.musicNote01, size: 34)
        .foregroundStyle(Color.secondary)
    }
  }
}
