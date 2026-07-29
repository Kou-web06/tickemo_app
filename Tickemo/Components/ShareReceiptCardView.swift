import SwiftUI

/// Ports the "Receipt" shareable card (`renderReceiptCard` in
/// ShareImageGenerator.tsx) — a cash-register-receipt-styled composite.
/// Premium-gated (see ShareSheetView's lock overlay). Fixed 826x2044
/// canvas, matching `ShareCapture.receiptCanvasSize`. Uses the built-in
/// `.monospaced` font design (SF Mono) rather than bundling RN's Roboto
/// Mono font file — same layout, different letterforms, zero extra
/// asset/licensing overhead for a secondary premium-gated card.
struct ShareReceiptCardView: View {
  let record: CD_ChekiRecord
  let username: String?

  private let width: CGFloat = 826
  private let height: CGFloat = 2044
  private let receiptTextColor = Color(red: 0.2, green: 0.2, blue: 0.2)

  private var rows: [ShareCardData.ReceiptRow] {
    ShareCardData.receiptRows(setlistItems: record.sortedSetlistItems)
  }

  private var totalTracks: Int {
    record.sortedSetlistItems.filter { $0.kind == "song" }.count
  }

  private var artistLabel: String {
    ShareCardData.receiptArtistLabel(setlistItems: record.sortedSetlistItems, fallbackArtist: record.artist)
  }

  var body: some View {
    ZStack {
      Image("ShareReceiptBackground")
        .resizable()
        .frame(width: width, height: height)

      VStack(spacing: 0) {
        Text("TICKEMO")
          .font(.system(size: 92, weight: .heavy, design: .monospaced))
          .tracking(1)
          .foregroundStyle(receiptTextColor)
          .padding(.bottom, 24)

        VStack(alignment: .leading, spacing: 4) {
          infoLine("VENUE: \(record.venue?.isEmpty == false ? record.venue! : "-")")
          infoLine("DATE : \(record.date?.isEmpty == false ? record.date! : "-")")
          infoLine("EVENT: \(record.liveName?.isEmpty == false ? record.liveName! : "-")")
          infoLine("ARTIST: \(artistLabel)")
        }
        .padding(.top, 54)
        .frame(maxWidth: .infinity, alignment: .leading)

        divider.padding(.top, 10).padding(.bottom, 8)

        HStack {
          HStack(spacing: 50) {
            headerText("QTY")
            headerText("ITEM")
          }
          Spacer()
          headerText("AMT")
        }

        divider.padding(.top, 10).padding(.bottom, 8)

        VStack(spacing: 2) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            receiptRow(row)
          }
        }

        divider.padding(.top, 10).padding(.bottom, 8)

        summaryRow(label: "SUBTOTAL:", value: "\(totalTracks)")
        summaryRow(label: "TAX:", value: "0%")

        divider.padding(.top, 10).padding(.bottom, 8)

        summaryRow(label: "TOTAL:", value: "\(totalTracks) ITEMS", weight: .heavy)

        divider.padding(.top, 10).padding(.bottom, 8)

        VStack(alignment: .leading, spacing: 4) {
          infoLine("PAID WITH: PASSION & TEARS")
          infoLine("AUTH CODE: VDY-20260214")
          infoLine("HOLDER: \(ShareCardData.shareCreditHandle(username: username))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Spacer(minLength: 16)

        VStack(spacing: 18) {
          Text("THANK YOU FOR VISITING!")
            .font(.system(size: 26, weight: .bold, design: .monospaced))
            .foregroundStyle(receiptTextColor)
          Image("ShareTickemoQR")
            .resizable()
            .frame(width: 160, height: 160)
          Text("NO REFUNDS ON LIVE MEMORIES.")
            .font(.system(size: 26, weight: .bold, design: .monospaced))
            .foregroundStyle(receiptTextColor)
            .multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 68)
      .padding(.top, 92)
      .padding(.bottom, 54)
      .frame(width: width, height: height, alignment: .top)
    }
    .frame(width: width, height: height)
    .clipped()
  }

  private func infoLine(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 26, weight: .bold, design: .monospaced))
      .foregroundStyle(receiptTextColor)
      .lineLimit(1)
  }

  private func headerText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 26, weight: .bold, design: .monospaced))
      .foregroundStyle(receiptTextColor)
  }

  private var divider: some View {
    Text(ShareCardData.receiptDashedDivider)
      .font(.system(size: 26, design: .monospaced))
      .foregroundStyle(receiptTextColor)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  }

  private func summaryRow(label: String, value: String, weight: Font.Weight = .bold) -> some View {
    HStack {
      Text(label).font(.system(size: 26, weight: weight, design: .monospaced)).foregroundStyle(receiptTextColor)
      Spacer()
      Text(value).font(.system(size: 26, weight: weight, design: .monospaced)).foregroundStyle(receiptTextColor)
    }
  }

  @ViewBuilder
  private func receiptRow(_ row: ShareCardData.ReceiptRow) -> some View {
    switch row {
    case .song(let quantityLabel, let name, let amount):
      HStack {
        Text(quantityLabel)
          .font(.system(size: 26, weight: .bold, design: .monospaced))
          .foregroundStyle(receiptTextColor)
          .frame(width: 76, alignment: .leading)
        Text(name)
          .font(.system(size: 26, weight: .bold, design: .monospaced))
          .foregroundStyle(receiptTextColor)
          .lineLimit(1)
        Spacer()
        Text(amount)
          .font(.system(size: 26, weight: .bold, design: .monospaced))
          .foregroundStyle(receiptTextColor)
          .frame(width: 104, alignment: .trailing)
      }
    case .encoreMarker:
      Text(ShareCardData.receiptEncoreMarkerLine)
        .font(.system(size: 26, weight: .bold, design: .monospaced))
        .foregroundStyle(receiptTextColor)
        .frame(maxWidth: .infinity, alignment: .center)
    case .ellipsis:
      Text("...")
        .font(.system(size: 26, weight: .bold, design: .monospaced))
        .foregroundStyle(receiptTextColor)
    }
  }
}
