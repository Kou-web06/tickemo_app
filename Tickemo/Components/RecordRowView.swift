import SwiftUI

/// Faithful port of components/TicketCard.tsx's composition: a ticket-stub
/// shaped background (see TicketStubShape), a cover-photo "jacket" tile
/// stacked on top of a QR code tile in the perforated left stub area, and a
/// text info column (title/artist/DATE/VENUE/SEAT) in the right main area.
/// Built in the same 322x118 unit space as the original SVG so the RN
/// implementation's pixel offsets carry over directly under one uniform
/// scale factor, then laid out with SwiftUI's `.position()` instead of RN's
/// mix of flexbox + absolute positioning (marquee/ticker text for
/// long values is simplified to plain truncation).
struct RecordRowView: View {
  @ObservedObject var record: CD_ChekiRecord

  private static let baseSize = TicketStubShape.baseSize
  private static let imageSize: CGFloat = 73 // baseHeight(118) * 0.619, matches the RN comment "73/118"

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = width * (Self.baseSize.height / Self.baseSize.width)
      let scale = width / Self.baseSize.width

      ZStack(alignment: .topLeading) {
        TicketStubShape()
          .fill(Color.white, style: FillStyle(eoFill: true))
          .shadow(color: .black.opacity(0.18), radius: 8)

        qrTile
          .frame(width: Self.imageSize * 1.2 * scale, height: Self.imageSize * 1.2 * scale)
          .position(
            x: (16 + Self.imageSize * 1.2 / 2) * scale,
            y: height / 2
          )

        jacketTile
          .frame(width: Self.imageSize * 1.3 * scale, height: Self.imageSize * 1.3 * scale)
          .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
          .shadow(color: .black.opacity(0.18), radius: 8, x: 10 * scale, y: 10 * scale)
          .position(
            x: (-10 + Self.imageSize * 1.3 / 2) * scale,
            y: (8 + Self.imageSize * 1.3 / 2) * scale
          )

        infoColumn
          .frame(width: infoWidth * scale, height: height, alignment: .leading)
          .position(x: (infoX + infoWidth / 2) * scale, y: height / 2)
      }
      .frame(width: width, height: height)
    }
    .aspectRatio(Self.baseSize.width / Self.baseSize.height, contentMode: .fit)
  }

  // Right column starts just past the perforation notch (padding 16 + QR
  // width + its 16pt margin), matching contentContainer's flex flow in the
  // RN source.
  private var infoX: CGFloat { 16 + Self.imageSize * 1.2 + 16 }
  private var infoWidth: CGFloat { Self.baseSize.width - infoX - 16 }

  @ViewBuilder
  private var qrTile: some View {
    QRCodeView(value: record.qrCode)
      .padding(4)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 3))
  }

  @ViewBuilder
  private var jacketTile: some View {
    if let data = record.coverImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color(.tertiarySystemBackground)
        GeometryReader { proxy in
          HugeIconView(icon: HugeIcons.image01, size: min(proxy.size.width, proxy.size.height) - 36)
            .foregroundStyle(.tertiary)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
    }
  }

  private var artistDisplay: ArtistDisplayResult { record.artistDisplay }

  private var infoColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(record.liveName ?? "-")
        .font(.system(size: 16, weight: .heavy))
        .foregroundStyle(.black)
        .lineLimit(1)

      (
        Text(artistDisplay.mainText)
          + Text(artistDisplay.showAndMore ? " and more..." : "")
            .foregroundStyle(Color(.systemGray))
      )
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color(white: 0.4))
      .lineLimit(1)

      Spacer(minLength: 6)

      VStack(alignment: .leading, spacing: 2) {
        detailRow(label: "DATE", value: record.date)
        detailRow(label: "VENUE", value: record.venue)
        detailRow(label: "SEAT", value: record.seat)
      }

      Spacer(minLength: 0)
    }
  }

  private func detailRow(label: String, value: String?) -> some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(white: 0.6))
        .frame(minWidth: 40, alignment: .leading)
      Text(value?.isEmpty == false ? value! : "-")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.black)
        .lineLimit(1)
    }
  }
}
