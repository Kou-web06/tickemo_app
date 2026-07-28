import SwiftUI
import PhotosUI

private let ticketPricePresets: [Int] = [3000, 5000, 8000, 10000, 15000]

struct RecordFormView: View {
  private let record: CD_ChekiRecord?

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  @State private var liveName: String
  @State private var liveType: LiveType
  @State private var date: Date
  @State private var venue: String
  @State private var seat: String
  @State private var ticketPriceText: String
  @State private var startTime: Date
  @State private var endTime: Date
  @State private var artistName: String
  @State private var memo: String
  @State private var qrCode: String

  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var coverImageData: Data?

  init(record: CD_ChekiRecord?) {
    self.record = record
    _liveName = State(initialValue: record?.liveName ?? "")
    _liveType = State(initialValue: LiveType.normalized(record?.liveType))
    _date = State(initialValue: DateFormatting.date(from: record?.date) ?? Date())
    _venue = State(initialValue: record?.venue ?? "")
    _seat = State(initialValue: record?.seat ?? "")
    _ticketPriceText = State(initialValue: record.map { String(Int($0.ticketPrice)) } ?? "")
    _startTime = State(initialValue: DateFormatting.time(from: record?.startTime) ?? Date())
    _endTime = State(initialValue: DateFormatting.time(from: record?.endTime) ?? Date())
    _artistName = State(initialValue: record?.artist ?? "")
    _memo = State(initialValue: record?.memo ?? "")
    _qrCode = State(initialValue: record?.qrCode ?? "")
    _coverImageData = State(initialValue: record?.coverImageData)
  }

  private var isValid: Bool {
    !liveName.trimmingCharacters(in: .whitespaces).isEmpty
      && !venue.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var venuePlaceholder: String {
    switch liveType {
    case .streaming: "Platform / URL"
    case .sports: "Stadium / Arena"
    default: "Venue name"
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Live name", text: $liveName)
          Picker("Live type", selection: $liveType) {
            ForEach(LiveType.allCases) { type in
              Label(type.label, systemImage: type.systemImage).tag(type)
            }
          }
          DatePicker("Date", selection: $date, displayedComponents: .date)
        }

        Section {
          TextField(venuePlaceholder, text: $venue)
          TextField("Seat (optional)", text: $seat)
        }

        Section("Ticket Price") {
          TextField("Price", text: $ticketPriceText)
            .keyboardType(.numberPad)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(ticketPricePresets, id: \.self) { preset in
                Button("¥\(preset)") { ticketPriceText = String(preset) }
                  .buttonStyle(.bordered)
              }
            }
          }
        }

        Section("Time") {
          DatePicker("Doors open", selection: $startTime, displayedComponents: .hourAndMinute)
          DatePicker("Show start", selection: $endTime, displayedComponents: .hourAndMinute)
        }

        Section("Artist") {
          TextField("Artist name", text: $artistName)
        }

        Section("Cover Image") {
          coverImagePreview
          PhotosPicker("Choose Photo", selection: $selectedPhotoItem, matching: .images)
          if coverImageData != nil {
            Button("Remove Photo", role: .destructive) { coverImageData = nil }
          }
        }

        Section {
          TextField("Memo", text: $memo, axis: .vertical)
            .lineLimit(3...8)
        }

        Section("URL") {
          TextField("https://...", text: $qrCode)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }
      .navigationTitle(record == nil ? "Add Ticket" : "Edit Ticket")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!isValid)
        }
      }
      .onChange(of: selectedPhotoItem) { _, newItem in
        Task {
          guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
          coverImageData = ImageCropping.squareCroppedJPEGData(from: data) ?? data
        }
      }
    }
  }

  @ViewBuilder
  private var coverImagePreview: some View {
    if let coverImageData, let uiImage = UIImage(data: coverImageData) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  private func save() {
    let target = record ?? CD_ChekiRecord(context: viewContext)
    if record == nil {
      target.id = UUID()
      target.createdAt = DateFormatting.isoNow()
    }

    target.liveName = liveName
    target.liveType = liveType.rawValue
    target.date = DateFormatting.string(from: date)
    target.venue = venue
    target.seat = seat.isEmpty ? nil : seat
    target.ticketPrice = Double(ticketPriceText) ?? 0
    target.startTime = DateFormatting.timeString(from: startTime)
    target.endTime = DateFormatting.timeString(from: endTime)

    let trimmedArtist = artistName.trimmingCharacters(in: .whitespaces)
    target.artist = trimmedArtist.isEmpty ? nil : trimmedArtist
    target.artists = trimmedArtist.isEmpty ? nil : NSArray(array: [trimmedArtist])

    target.memo = memo.isEmpty ? nil : memo
    target.qrCode = qrCode.isEmpty ? nil : qrCode

    applyCoverImage(to: target)

    try? viewContext.save()
    dismiss()
  }

  private func applyCoverImage(to target: CD_ChekiRecord) {
    guard let coverImageData else {
      // Explicit removal: drop the existing cover image row, if any.
      if let existing = target.coverImage {
        viewContext.delete(existing)
      }
      return
    }
    let image = target.coverImage ?? CD_LiveImage(context: viewContext)
    if image.id == nil {
      image.id = UUID()
    }
    image.orderIndex = 0
    image.data = coverImageData
    image.record = target
  }
}
