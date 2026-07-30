import SwiftUI

/// Exact port of StatisticsScreen.tsx's ALL ARTISTS card (`ArtistArchiveCard`):
/// the artist's official MusicKit photo, full-bleed clipped to the scalloped
/// `ArtistArchiveShape`, with a flat `black.opacity(0.2)` scrim (not a
/// gradient — RN fills the same clip path with `rgba(0,0,0,0.2)`) and the
/// name/date overlay on top. RN never falls back to the user's own ticket
/// cover photo here — only the artist's official photo or a generic
/// placeholder — so `entry.artistImageUrl` is the only photo source.
struct ArtistArchiveCardView: View {
  let entry: ArtistArchiveEntry

  private let cardWidth: CGFloat = 118
  private let cardHeight: CGFloat = 121

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      photo
        .clipShape(ArtistArchiveShape())

      ArtistArchiveShape()
        .fill(Color.black.opacity(0.2))

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.name)
          .font(.system(size: 15, weight: .black))
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(entry.lastLiveDateText)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white.opacity(0.95))
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 12)
    }
    .frame(width: cardWidth, height: cardHeight)
  }

  @ViewBuilder
  private var photo: some View {
    if let urlString = entry.artistImageUrl, let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        placeholder
      }
      .frame(width: cardWidth, height: cardHeight)
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    ZStack {
      Color(.tertiarySystemBackground)
      Image(systemName: "person.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 32, height: 32)
        .foregroundStyle(Color(white: 0.77))
    }
    .frame(width: cardWidth, height: cardHeight)
  }
}
