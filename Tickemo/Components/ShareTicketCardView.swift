import SwiftUI

/// Ports the "Ticket" shareable card from `EditableTicketPreviewCard.tsx`,
/// stripped of everything the share flow never actually exposes: RN always
/// calls this with `selectedSticker: 'none'`, `backgroundColor: '#FFFFFF'`,
/// `selectedFilterId: 'normal'` (stickers are fully stubbed on the RN side
/// too — `STICKER_IMAGES = {}` — and the color-filter picker UI is never
/// shown in the share modal), so this view has no customization surface:
/// always a white ticket, always dark text, no filter, no sticker. Fixed
/// 1480x1200 canvas, matching `ShareCapture.ticketCanvasSize`.
struct ShareTicketCardView: View {
  let record: CD_ChekiRecord
  let showsBlurredBackground: Bool

  private let width: CGFloat = 1480
  private let height: CGFloat = 1200

  private var imageSize: CGFloat { height * 0.32 }
  private var qrSize: CGFloat { imageSize * 0.3 }
  private var qrPadding: CGFloat { qrSize * 0.1 }
  private var qrContainerSize: CGFloat { qrSize + qrPadding * 2 }
  private var textLeft: CGFloat { width * 0.1 + imageSize + width * 0.08 }

  private var liveName: String { record.liveName?.isEmpty == false ? record.liveName! : "-" }
  private var isShortLiveName: Bool { liveName.count <= 8 }

  private var artistText: String {
    let names = ArtistGrouping.names(for: record)
    return names.isEmpty ? "-" : names.joined(separator: " / ")
  }

  private var startText: String {
    if let endTime = record.endTime, !endTime.isEmpty { return endTime }
    if let startTime = record.startTime, !startTime.isEmpty { return startTime }
    return "18:00"
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      if showsBlurredBackground {
        blurredBackground
      }

      ShareTicketShape()
        .fill(Color.white)
        .shadow(color: .black.opacity(0.3), radius: 7.5, x: 0, y: 0)
        .frame(width: width, height: height)

      coverPhoto
        .offset(x: width * 0.07, y: height * 0.5 - imageSize / 2)

      liveNameText
        .frame(width: width - textLeft - width * 0.13, alignment: .leading)
        .offset(x: textLeft, y: height * 0.33)

      Text(artistText)
        .font(.system(size: height * 0.03, weight: .heavy))
        .foregroundStyle(Color.black.opacity(0.62))
        .lineLimit(2)
        .frame(width: width - textLeft - width * 0.13, alignment: .leading)
        .offset(x: textLeft, y: isShortLiveName ? height * 0.42 : height * 0.455)

      labelValueRow(label: "DATE", value: record.date?.isEmpty == false ? record.date! : "-")
        .offset(x: textLeft, y: height * 0.5)

      labelValueRow(label: "START", value: startText)
        .offset(x: textLeft, y: height * 0.55)

      labelValueRow(label: "VENUE", value: record.venue?.isEmpty == false ? record.venue! : "-", lineLimit: 1)
        .frame(width: width - textLeft - width * 0.25, alignment: .leading)
        .offset(x: textLeft, y: height * 0.6)

      qrCode
        .offset(x: width - width * 0.09 - qrContainerSize, y: height - height * 0.31 - qrContainerSize)

      Text("TICKEMO")
        .font(.system(size: height * 0.02, weight: .heavy))
        .foregroundStyle(Color.black.opacity(0.3))
        .offset(x: width * 0.08, y: height - height * 0.3 - height * 0.024)
    }
    .frame(width: width, height: height)
    .clipped()
  }

  @ViewBuilder
  private var liveNameText: some View {
    if isShortLiveName {
      Text(liveName)
        .font(.system(size: height * 0.06, weight: .black))
        .foregroundStyle(Color.black.opacity(0.87))
        .lineLimit(1)
    } else {
      Text(liveName)
        .font(.system(size: height * 0.04, weight: .black))
        .foregroundStyle(Color.black.opacity(0.87))
        .lineLimit(2)
        .lineSpacing(height * 0.015)
    }
  }

  private func labelValueRow(label: String, value: String, lineLimit: Int = 1) -> some View {
    HStack(spacing: width * 0.02) {
      Text(label)
        .font(.system(size: height * 0.04, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.46))
      Text(value)
        .font(.system(size: height * 0.04, weight: .heavy))
        .foregroundStyle(Color.black.opacity(0.87))
        .lineLimit(lineLimit)
    }
  }

  @ViewBuilder
  private var coverPhoto: some View {
    Group {
      if let data = record.coverImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
      } else {
        placeholderJacket
      }
    }
    .frame(width: imageSize, height: imageSize)
    .clipShape(RoundedRectangle(cornerRadius: 40))
    .shadow(color: .black.opacity(0.3), radius: 12, x: 10, y: 10)
  }

  /// RN's `DummyJacket` placeholder — a distinct violet 2-color convention
  /// (not this app's other gray/person.fill placeholder used elsewhere).
  private var placeholderJacket: some View {
    ZStack {
      Color(red: 0.953, green: 0.851, blue: 1.0)
      HugeIconView(icon: HugeIcons.image01, size: imageSize * 0.34)
        .foregroundStyle(Color(red: 0.718, green: 0.557, blue: 0.812))
    }
  }

  @ViewBuilder
  private var qrCode: some View {
    Group {
      if let value = record.qrCode, !value.isEmpty, let uiImage = QRCodeImage.image(for: value) {
        Image(uiImage: uiImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(width: qrSize, height: qrSize)
      } else {
        HugeIconView(icon: HugeIcons.qrCode, size: qrSize)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(qrPadding)
    .frame(width: qrContainerSize, height: qrContainerSize)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  @ViewBuilder
  private var blurredBackground: some View {
    Group {
      if let data = record.coverImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
      } else {
        placeholderJacket
      }
    }
    .frame(width: width, height: height)
    .clipped()
    .blur(radius: 60)
  }
}
