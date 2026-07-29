import SwiftUI

/// Ports StatisticsScreen.tsx's ALL ARTISTS card (`ArtistArchiveCard`) as a
/// plain rounded-rect card instead of RN's hand-drawn SVG scalloped-bottom
/// clip path — same simplification precedent as Calendar's future-event dot
/// replacing RN's scribble decoration. Shares ArtistGridItemView's visual
/// language (cover photo or person-icon placeholder, bottom gradient, white
/// heavy name) at a smaller size, with a single "last live" date line
/// instead of ArtistGridItemView's two count/date badges.
struct ArtistArchiveCardView: View {
  let entry: ArtistArchiveEntry

  private let cardWidth: CGFloat = 118
  private let cardHeight: CGFloat = 148

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      photo

      LinearGradient(
        colors: [Color.black.opacity(0.85), Color.black.opacity(0)],
        startPoint: .bottom,
        endPoint: .top
      )
      .frame(height: cardHeight * 0.62)
      .frame(maxHeight: .infinity, alignment: .bottom)

      VStack(alignment: .leading, spacing: 3) {
        Text(entry.name)
          .font(.system(size: 13, weight: .heavy))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(entry.lastLiveDateText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.white.opacity(0.8))
      }
      .padding(10)
    }
    .frame(width: cardWidth, height: cardHeight)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
  }

  @ViewBuilder
  private var photo: some View {
    if let data = entry.coverImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
    } else {
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
}
