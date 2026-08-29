import SwiftUI

enum ShareCDTextColor: Equatable {
  case white
  case black

  var color: Color {
    switch self {
    case .white: .white
    case .black: Color(red: 0.109, green: 0.109, blue: 0.109)
    }
  }

  var subColor: Color {
    switch self {
    case .white: .white.opacity(0.85)
    case .black: .black.opacity(0.65)
    }
  }
}

/// Ports the "CD" shareable card (`renderCDCard` in ShareImageGenerator.tsx)
/// — a jewel-case-style composite. Premium-gated (see ShareSheetView's lock
/// overlay). Fixed 1480x1200 canvas, matching `ShareCapture.cdCanvasSize`
/// (same dimensions as the Ticket card, different content). All layer
/// positions below are literal pixel offsets transcribed from the RN
/// source's absolute-positioned layout, not percentages.
struct ShareCDCardView: View {
  let record: CD_ChekiRecord
  let textColor: ShareCDTextColor
  let username: String?

  private let width: CGFloat = 1480
  private let height: CGFloat = 1200

  private var fgColor: Color { textColor.color }
  private var fgColorSub: Color { textColor.subColor }
  private var fgShadow: Color? { textColor == .white ? .black.opacity(0.4) : nil }
  private var creditShadow: Color? { textColor == .white ? .black.opacity(0.15) : nil }

  private var setlistLines: [ShareCardData.SetlistLine] {
    ShareCardData.cdSetlistLines(items: record.sortedSetlistItems)
  }

  private var businessCode: String {
    let songCount = record.sortedSetlistItems.filter { $0.kind == "song" }.count
    return ShareCardData.cdBusinessCode(date: record.date, startTime: record.startTime, songCount: songCount)
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image("ShareCDFrame")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: width, height: height)

      jacket
        .offset(x: 180, y: 75)

      setlistColumns
        .offset(x: 200, y: 120)

      liveInfo
        .offset(x: width - 200 - 600, y: 160)

      Text(businessCode)
        .font(appFont.bold(28))
        .tracking(1)
        .foregroundStyle(fgColor)
        .shadow(color: fgShadow ?? .clear, radius: fgShadow == nil ? 0 : 8)
        .frame(width: 430, alignment: .trailing)
        .offset(x: width - 180 - 430, y: height - 355 - 40)

      ShareBarcodeView(color: fgColor)
        .frame(width: 430, height: 140)
        .offset(x: width - 180 - 430, y: height - 200 - 140)

      credit
        .offset(x: width - 180 - 550, y: height - 90 - 110)

      filmLayerOverlay
        .offset(x: 65, y: 65)
    }
    .frame(width: width, height: height)
    .clipped()
  }

  private var jacket: some View {
    ZStack(alignment: .topLeading) {
      Group {
        if let data = record.coverImageData, let uiImage = UIImage(data: data) {
          Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
          Color(red: 0.533, green: 0.133, blue: 0.067)
        }
      }
      .frame(width: (width - 180 - 62) * 0.95, height: (height - 75) * 0.95)
      .clipped()

      if textColor == .white {
        Color.black.opacity(0.15)
          .frame(width: (width - 180 - 62) * 0.95, height: (height - 75) * 0.95)
      }
    }
    .frame(width: width - 180 - 62, height: height - 75, alignment: .topLeading)
    .clipped()
  }

  private var setlistColumns: some View {
    let column1 = Array(setlistLines.prefix(28))
    let column2 = Array(setlistLines.dropFirst(28))

    return HStack(alignment: .top, spacing: 16) {
      if setlistLines.isEmpty {
        Text("No setlist")
          .font(appFont.regular(25))
          .foregroundStyle(fgColor)
      } else {
        setlistColumn(column1)
        if !column2.isEmpty {
          setlistColumn(column2)
        }
      }
    }
    .frame(width: 460, height: height - 120 - 90, alignment: .topLeading)
  }

  private func setlistColumn(_ lines: [ShareCardData.SetlistLine]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        switch line.kind {
        case .song(let index, let name):
          Text("\(index).\(name)")
            .font(appFont.regular(25))
            .foregroundStyle(fgColor)
            .lineLimit(1)
        case .encoreSpacer:
          Text(" ").font(appFont.regular(25)).foregroundStyle(.clear)
        case .encoreLabel:
          Text("[ENCORE]")
            .font(appFont.regular(22))
            .tracking(2)
            .foregroundStyle(fgColor)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var liveInfo: some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(record.liveName?.isEmpty == false ? record.liveName! : "-")
        .font(appFont.bold(56))
        .foregroundStyle(fgColor)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)

      Text(record.date?.isEmpty == false ? record.date! : "-")
        .font(appFont.bold(42))
        .foregroundStyle(fgColor)
        .padding(.top, 50)

      if let venue = record.venue, !venue.isEmpty {
        Text(venue)
          .font(appFont.bold(38))
          .foregroundStyle(fgColorSub)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
          .padding(.top, 10)
      }
    }
    .frame(width: 600, alignment: .trailing)
  }

  private var credit: some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text("This share card was created")
        .font(appFont.regular(38))
        .foregroundStyle(fgColor)
      Text("by \(ShareCardData.shareCreditHandle(username: username)) with Tickemo")
        .font(appFont.regular(38))
        .foregroundStyle(fgColor)
    }
    .frame(width: 550, alignment: .trailing)
  }

  private var filmLayerOverlay: some View {
    LinearGradient(
      stops: [
        .init(color: .white.opacity(0), location: 0),
        .init(color: .white.opacity(0.32), location: 0.25),
        .init(color: .white.opacity(0), location: 0.5),
        .init(color: .white.opacity(0.39), location: 0.75),
        .init(color: .white.opacity(0.13), location: 0.875),
        .init(color: .white.opacity(0.02), location: 1),
      ],
      startPoint: .topTrailing,
      endPoint: .bottomLeading
    )
    .frame(width: width * 0.9, height: height * 0.9)
    .allowsHitTesting(false)
  }
}
