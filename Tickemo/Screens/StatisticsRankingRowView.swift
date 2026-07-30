import SwiftUI

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

  var body: some View {
    ZStack {
      Circle().fill(fillColor)
      Text("\(rank)")
        .font(.system(size: 13, weight: .heavy))
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

  var body: some View {
    HStack(spacing: 12) {
      RankBadge(rank: rank)
      thumbnailView
      Text(name)
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(detail)
        .font(.system(size: 13, weight: .medium))
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
