import SwiftUI

struct RecordRowView: View {
  @ObservedObject var record: CD_ChekiRecord

  var body: some View {
    HStack(spacing: 12) {
      coverThumbnail
      QRCodeView(value: record.qrCode)
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 4) {
        Text(record.liveName ?? "")
          .font(.headline)
          .lineLimit(1)
        if let artist = record.artist, !artist.isEmpty {
          Text(artist)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        infoRow(label: "DATE", value: record.date)
        infoRow(label: "VENUE", value: record.venue)
        if let seat = record.seat, !seat.isEmpty {
          infoRow(label: "SEAT", value: seat)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
  }

  @ViewBuilder
  private var coverThumbnail: some View {
    Group {
      if let data = record.coverImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .resizable()
          .scaledToFit()
          .padding(12)
          .foregroundStyle(.tertiary)
          .background(Color(.tertiarySystemBackground))
      }
    }
    .frame(width: 60, height: 60)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func infoRow(label: String, value: String?) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value?.isEmpty == false ? value! : "-")
        .font(.caption)
        .lineLimit(1)
    }
  }
}
