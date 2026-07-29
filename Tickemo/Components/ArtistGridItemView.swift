import SwiftUI

/// Ports components/ArtistGridItem.tsx: a square tile with a cover photo
/// (or a person-icon placeholder), a bottom gradient for legibility, the
/// artist name, and two pill badges (latest past show date, show count).
struct ArtistGridItemView: View {
  let tile: ArtistGrouping.Tile

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
            .font(.system(size: 14, weight: .heavy))
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
  }

  @ViewBuilder
  private var photo: some View {
    if let data = tile.coverImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color(.tertiarySystemBackground)
        Image(systemName: "person.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 40, height: 40)
          .foregroundStyle(Color(white: 0.77))
      }
    }
  }

  private func badge(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Color(red: 0.604, green: 0.486, blue: 0.973))
      .clipShape(Capsule())
  }
}
