import SwiftUI

struct RecordDetailView: View {
  @ObservedObject var record: CD_ChekiRecord

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  @State private var showingEditSheet = false
  @State private var showingDeleteConfirmation = false

  private var liveType: LiveType { LiveType.normalized(record.liveType) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header

        Text(record.liveName ?? "")
          .font(.title2.bold())

        if let artist = record.artist, !artist.isEmpty {
          Text(artist)
            .font(.headline)
            .foregroundStyle(.secondary)
        }

        Label(liveType.label, systemImage: liveType.systemImage)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          detailRow(icon: "yensign.circle", label: "Price", value: priceText)
          detailRow(icon: "calendar", label: "Date", value: dateText)
          detailRow(icon: "clock", label: "Time", value: timeText)
          detailRow(icon: "mappin.and.ellipse", label: "Venue", value: record.venue)
          if let seat = record.seat, !seat.isEmpty {
            detailRow(icon: "chair", label: "Seat", value: seat)
          }
        }

        if let memo = record.memo, !memo.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 4) {
            Text("Memo").font(.caption).foregroundStyle(.secondary)
            Text(memo)
          }
        }

        if let qrCode = record.qrCode, !qrCode.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 4) {
            Text("URL").font(.caption).foregroundStyle(.secondary)
            if let url = URL(string: qrCode), let scheme = url.scheme, scheme.hasPrefix("http") {
              Link(qrCode, destination: url)
            } else {
              Text(qrCode)
                .textSelection(.enabled)
            }
          }
        }
      }
      .padding()
    }
    .navigationTitle(record.liveName ?? "Ticket")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showingEditSheet = true
        } label: {
          Image(systemName: "pencil")
        }
      }
      ToolbarItem(placement: .destructiveAction) {
        Button(role: .destructive) {
          showingDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
        }
      }
    }
    .sheet(isPresented: $showingEditSheet) {
      RecordFormView(record: record)
    }
    .alert("Delete this ticket?", isPresented: $showingDeleteConfirmation) {
      Button("Delete", role: .destructive) { deleteRecord() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This cannot be undone.")
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      Group {
        if let data = record.coverImageData, let uiImage = UIImage(data: data) {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
        } else {
          Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .padding(24)
            .foregroundStyle(.tertiary)
            .background(Color(.tertiarySystemBackground))
        }
      }
      .frame(width: 140, height: 140)
      .clipShape(RoundedRectangle(cornerRadius: 12))

      QRCodeView(value: record.qrCode)
        .frame(width: 100, height: 100)
    }
    .frame(maxWidth: .infinity)
  }

  private var priceText: String {
    record.ticketPrice.formatted(.currency(code: "JPY").precision(.fractionLength(0)))
  }

  private var dateText: String {
    guard let date = DateFormatting.date(from: record.date) else { return record.date ?? "-" }
    return date.formatted(date: .long, time: .omitted) + " (" + date.formatted(.dateTime.weekday(.wide)) + ")"
  }

  private var timeText: String {
    let start = record.startTime ?? "-"
    let end = record.endTime ?? "-"
    return "\(start) - \(end)"
  }

  private func detailRow(icon: String, label: String, value: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(.secondary)
        .frame(width: 20)
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 50, alignment: .leading)
      Text(value?.isEmpty == false ? value! : "-")
    }
  }

  private func deleteRecord() {
    viewContext.delete(record)
    try? viewContext.save()
    dismiss()
  }
}
