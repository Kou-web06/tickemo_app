import SwiftUI
import PhotosUI

private let ticketPricePresets: [Int] = [3000, 5000, 8000, 10000, 15000]

/// Ports screens/LiveEditScreen.tsx (RN's single shared create/edit form).
/// Artist handling matches RN's ArtistInput/`performances` design exactly:
/// - `sports` bypasses Apple Music search entirely (free-text player/team
///   name, no photo requirement).
/// - `two-man`/`festival` render one independent ArtistSearchField per
///   artist (`artistEntries`), add/remove via a "+ Add artist" row, minimum
///   1 entry — mirrors RN's `performances[]`.
/// - every other type shows exactly one ArtistSearchField.
/// Save is blocked (button disabled) unless every named, non-sports artist
/// has a photo picked from search — RN enforces the same "must select from
/// the catalog, no free-typed artist" rule via `hasDictionaryRegistered`.
/// Sports lives get RN's dual photo treatment: the single cover-image slot
/// (orderIndex 0) doubles as "Player / Team Photo", just relabeled, and a
/// separate up-to-6 "Game Photos" gallery (orderIndex 1...6) ports
/// `LiveEditScreen.tsx`'s sports-only `imageUrls` grid — both ride the same
/// `CD_LiveImage`/CloudKit CKAsset sync path, no schema change needed.
struct RecordFormView: View {
  private let record: CD_ChekiRecord?

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  struct ArtistEntry: Identifiable {
    let id = UUID()
    var name: String
    var imageUrl: String?
    var setlistItems: [SetlistDraftItem] = []
  }

  @State private var liveName: String
  @State private var liveType: LiveType
  @State private var date: Date
  @State private var venue: String
  @State private var seat: String
  @State private var ticketPriceText: String
  @State private var startTime: String
  @State private var endTime: String
  @State private var artistEntries: [ArtistEntry]
  @State private var setlistItems: [SetlistDraftItem]
  @State private var memo: String
  @State private var qrCode: String

  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var coverImageData: Data?
  @State private var selectedGamePhotoItem: PhotosPickerItem?
  @State private var gamePhotosData: [Data]
  @State private var showingDiscardConfirmation = false

  init(record: CD_ChekiRecord?) {
    self.record = record
    _liveName = State(initialValue: record?.liveName ?? "")
    _liveType = State(initialValue: LiveType.normalized(record?.liveType))
    _date = State(initialValue: DateFormatting.date(from: record?.date) ?? Date())
    _venue = State(initialValue: record?.venue ?? "")
    _seat = State(initialValue: record?.seat ?? "")
    _ticketPriceText = State(initialValue: record.map { String(Int($0.ticketPrice)) } ?? "")
    _startTime = State(initialValue: record?.startTime ?? "18:00")
    _endTime = State(initialValue: record?.endTime ?? "20:00")
    _artistEntries = State(initialValue: Self.initialArtistEntries(for: record))
    let liveType = LiveType.normalized(record?.liveType)
    let isMulti = liveType == .twoMan || liveType == .festival
    _setlistItems = State(initialValue: isMulti ? [] : Self.setlistDraftItems(from: record))
    _memo = State(initialValue: record?.memo ?? "")
    _qrCode = State(initialValue: record?.qrCode ?? "")
    _coverImageData = State(initialValue: record?.coverImageData)
    _gamePhotosData = State(initialValue: record?.galleryImages.compactMap(\.data) ?? [])
  }

  private static let maxGamePhotos = 6

  private static func setlistDraftItems(from record: CD_ChekiRecord?) -> [SetlistDraftItem] {
    guard let record else { return [] }
    return record.sortedSetlistItems.map { cdItem in
      SetlistDraftItem(
        id: cdItem.id ?? UUID(),
        kind: SetlistDraftItem.Kind(rawValue: cdItem.kind ?? "song") ?? .song,
        songId: cdItem.songId,
        songName: cdItem.songName,
        artistName: cdItem.artistName,
        albumName: cdItem.albumName,
        artworkUrl: cdItem.artworkUrl,
        title: cdItem.title ?? ""
      )
    }
  }

  private static func initialArtistEntries(for record: CD_ChekiRecord?) -> [ArtistEntry] {
    guard let record else { return [ArtistEntry(name: "", imageUrl: nil)] }
    let names = record.artistsArray?.isEmpty == false ? record.artistsArray! : [record.artist ?? ""]
    let urls = record.artistImageUrlsArray ?? []
    var entries = names.enumerated().map { index, name in
      ArtistEntry(name: name, imageUrl: index < urls.count ? urls[index] : (index == 0 ? record.artistImageUrl : nil))
    }
    if entries.isEmpty { entries = [ArtistEntry(name: "", imageUrl: nil)] }

    let liveType = LiveType.normalized(record.liveType)
    guard liveType == .twoMan || liveType == .festival else { return entries }

    // Best-effort split of the flat, artistName-tagged setlist back into
    // per-performance buckets when re-opening a multi-artist record for
    // edit — RN faces the identical reconstruction ambiguity (its own
    // persisted setlist is just as flat, artistName-per-song), so this
    // isn't meant to be authoritative, just a reasonable starting point.
    // Marker rows (encore/mc) have no artistName to match on, so they fall
    // into whichever performance the preceding song matched.
    var lastIndex = 0
    for draft in setlistDraftItems(from: record) {
      let matchIndex = entries.firstIndex { entry in
        !entry.name.isEmpty && entry.name.caseInsensitiveCompare(draft.artistName ?? "") == .orderedSame
      }
      let targetIndex = matchIndex ?? lastIndex
      entries[targetIndex].setlistItems.append(draft)
      lastIndex = targetIndex
    }
    return entries
  }

  private var isSportsLive: Bool { liveType == .sports }
  private var isMultiArtistLive: Bool { liveType == .twoMan || liveType == .festival }

  private var isValid: Bool {
    RecordFormValidation.isValid(
      liveName: liveName,
      venue: venue,
      liveType: liveType,
      artistEntries: artistEntries.map { RecordFormValidation.ArtistInput(name: $0.name, imageUrl: $0.imageUrl) }
    )
  }

  private var venuePlaceholder: String {
    switch liveType {
    case .streaming: "Platform / URL"
    case .sports: "Stadium / Arena"
    default: "Venue name"
    }
  }

  private var coverImageSectionTitle: String {
    isSportsLive ? "Player / Team Photo" : "Cover Image"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Live name", text: $liveName)
          Picker("Live type", selection: $liveType) {
            ForEach(LiveType.allCases) { type in
              Label {
                Text(type.label)
              } icon: {
                Image(type.imageName).renderingMode(.template)
              }
              .tag(type)
            }
          }
          .onChange(of: liveType) { _, newValue in
            let stillMulti = newValue == .twoMan || newValue == .festival
            if !stillMulti && artistEntries.count > 1 {
              let keep = artistEntries.first { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } ?? artistEntries[0]
              artistEntries = [keep]
            }
            if newValue != .sports {
              gamePhotosData = []
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
          TimeWheelPickerField(label: "Doors open", value: $startTime)
          TimeWheelPickerField(label: "Show start", value: $endTime)
        }

        Section("Artist") {
          artistSection
        }

        if !isSportsLive && !isMultiArtistLive {
          Section("Setlist") {
            SetlistDraftEditorView(
              items: $setlistItems,
              showsOcrButton: true,
              artistHint: artistEntries.first {
                !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
              }?.name
            )
          }
        }

        Section(coverImageSectionTitle) {
          coverImagePreview
          PhotosPicker("Choose Photo", selection: $selectedPhotoItem, matching: .images)
          if coverImageData != nil {
            Button("Remove Photo", role: .destructive) { coverImageData = nil }
          }
        }

        if isSportsLive {
          Section("Game Photos") {
            gamePhotosGrid
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
          Button { showingDiscardConfirmation = true } label: {
            HugeIconView(icon: HugeIcons.cancel01, size: 17)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!isValid)
        }
      }
      .alert("変更を破棄しますか？", isPresented: $showingDiscardConfirmation) {
        Button("編集を続ける", role: .cancel) {}
        Button("破棄", role: .destructive) { dismiss() }
      } message: {
        Text("変更内容は失われます。")
      }
      .onChange(of: selectedPhotoItem) { _, newItem in
        Task {
          guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
          coverImageData = ImageCropping.squareCroppedJPEGData(from: data) ?? data
        }
      }
      .onChange(of: selectedGamePhotoItem) { _, newItem in
        Task {
          guard let newItem, gamePhotosData.count < Self.maxGamePhotos,
                let data = try? await newItem.loadTransferable(type: Data.self)
          else { return }
          gamePhotosData.append(ImageCropping.downsizedJPEGData(from: data) ?? data)
          selectedGamePhotoItem = nil
        }
      }
    }
    // CD_ChekiRecord.date is a wall-clock string formatted in UTC (see
    // DateFormatting), not a real timezone-aware instant. Without this,
    // DatePicker interprets/produces its Date value using the device's local
    // timezone: picking "Aug 15" in any timezone ahead of UTC (e.g. JST,
    // UTC+9) yields a Date whose UTC calendar day is still Aug 14, which
    // DateFormatting.string(from:) would then save as "2026-08-14" — one day
    // off from what was actually picked. Pinning the whole form's timezone
    // to UTC keeps what's shown on screen and what gets stored in sync
    // regardless of the device's timezone. startTime/endTime are plain
    // "HH:mm" strings edited via TimeWheelPickerField, so they need no such
    // pinning.
    .environment(\.timeZone, DateFormatting.timeZone)
  }

  // MARK: - Artist section

  @ViewBuilder
  private var artistSection: some View {
    if isSportsLive {
      TextField("Player / Team", text: artistNameBinding(0))
    } else if isMultiArtistLive {
      ForEach(Array(artistEntries.enumerated()), id: \.element.id) { index, _ in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Artist \(index + 1)")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)
            Spacer()
            if artistEntries.count > 1 {
              Button(role: .destructive) {
                artistEntries.remove(at: index)
              } label: {
                HugeIconView(icon: HugeIcons.delete02, size: 16)
              }
              .buttonStyle(.plain)
            }
          }
          ArtistSearchField(name: artistNameBinding(index), imageUrl: artistImageUrlBinding(index))

          // Each performance carries its own setlist, matching RN's
          // per-performance SetlistInputWithTags — no OCR trigger here,
          // RN's bulk-register only exists on the single-artist path.
          SetlistDraftEditorView(items: artistSetlistItemsBinding(index), showsOcrButton: false)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
      }
      Button {
        artistEntries.append(ArtistEntry(name: "", imageUrl: nil))
      } label: {
        HugeIconLabel(icon: HugeIcons.add01) { Text("Add artist") }
      }
    } else {
      ArtistSearchField(name: artistNameBinding(0), imageUrl: artistImageUrlBinding(0))
    }
  }

  private func artistNameBinding(_ index: Int) -> Binding<String> {
    Binding(
      get: { artistEntries.indices.contains(index) ? artistEntries[index].name : "" },
      set: { newValue in
        guard artistEntries.indices.contains(index) else { return }
        artistEntries[index].name = newValue
      }
    )
  }

  private func artistImageUrlBinding(_ index: Int) -> Binding<String?> {
    Binding(
      get: { artistEntries.indices.contains(index) ? artistEntries[index].imageUrl : nil },
      set: { newValue in
        guard artistEntries.indices.contains(index) else { return }
        artistEntries[index].imageUrl = newValue
      }
    )
  }

  private func artistSetlistItemsBinding(_ index: Int) -> Binding<[SetlistDraftItem]> {
    Binding(
      get: { artistEntries.indices.contains(index) ? artistEntries[index].setlistItems : [] },
      set: { newValue in
        guard artistEntries.indices.contains(index) else { return }
        artistEntries[index].setlistItems = newValue
      }
    )
  }

  // MARK: - Cover image

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

  // MARK: - Game photos (sports lives only, up to 6)

  private var gamePhotosGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 8)], spacing: 8) {
      ForEach(Array(gamePhotosData.enumerated()), id: \.offset) { index, data in
        if let uiImage = UIImage(data: data) {
          ZStack(alignment: .topTrailing) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFill()
              .frame(width: 88, height: 88)
              .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
              gamePhotosData.remove(at: index)
            } label: {
              HugeIconView(icon: HugeIcons.cancelCircle, size: 20)
                .foregroundStyle(.red)
                .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
          }
        }
      }

      if gamePhotosData.count < Self.maxGamePhotos {
        PhotosPicker(selection: $selectedGamePhotoItem, matching: .images) {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            .frame(width: 88, height: 88)
            .overlay {
              HugeIconView(icon: HugeIcons.add01, size: 22)
                .foregroundStyle(.secondary)
            }
        }
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Save

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
    target.startTime = startTime
    target.endTime = endTime

    applyArtists(to: target)
    applySetlist(to: target)

    target.memo = memo.isEmpty ? nil : memo
    target.qrCode = qrCode.isEmpty ? nil : qrCode

    applyCoverImage(to: target)
    applyGamePhotos(to: target)

    try? viewContext.save()
    HapticsPreferenceService.shared.notify(.success)
    dismiss()
  }

  // Sports never has a setlist (matches RN, which hides the whole section
  // for isSportsLive); multi-artist flattens each performance's own items
  // in order, matching RN's per-performance parse + flatMap at save time.
  private var flattenedSetlistItems: [SetlistDraftItem] {
    if isSportsLive { return [] }
    if isMultiArtistLive { return artistEntries.flatMap(\.setlistItems) }
    return setlistItems
  }

  private func applySetlist(to target: CD_ChekiRecord) {
    for existing in target.sortedSetlistItems {
      viewContext.delete(existing)
    }
    for (index, draft) in flattenedSetlistItems.enumerated() {
      let cdItem = CD_SetlistItem(context: viewContext)
      cdItem.id = draft.id
      cdItem.orderIndex = Int32(index)
      cdItem.kind = draft.kind.rawValue
      switch draft.kind {
      case .song:
        cdItem.songId = draft.songId
        cdItem.songName = draft.songName
        cdItem.artistName = draft.artistName
        cdItem.albumName = draft.albumName
        cdItem.artworkUrl = draft.artworkUrl
      case .encore, .mc:
        cdItem.title = draft.title
      }
      cdItem.record = target
    }
  }

  // Derives the singular `artist`/`artistImageUrl` as index-0 of the plural
  // arrays, exactly matching RN's LiveEditScreen save logic
  // (`filteredArtists[0]`/`filteredArtistImageUrls[0]`). Sports never
  // searches Apple Music, so it never has a photo to record.
  private func applyArtists(to target: CD_ChekiRecord) {
    if isSportsLive {
      let trimmed = artistEntries[0].name.trimmingCharacters(in: .whitespaces)
      target.artist = trimmed.isEmpty ? nil : trimmed
      target.artists = trimmed.isEmpty ? nil : NSArray(array: [trimmed])
      target.artistImageUrl = nil
      target.artistImageUrls = nil
      return
    }

    let named = artistEntries
      .map { (name: $0.name.trimmingCharacters(in: .whitespaces), url: $0.imageUrl ?? "") }
      .filter { !$0.name.isEmpty }

    target.artists = named.isEmpty ? nil : NSArray(array: named.map(\.name))
    target.artist = named.first?.name
    target.artistImageUrls = named.isEmpty ? nil : NSArray(array: named.map(\.url))
    target.artistImageUrl = (named.first?.url.isEmpty == false) ? named.first?.url : nil
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

  // Delete-then-recreate, matching applySetlist's approach to the same
  // to-many-relationship-as-ordered-list problem: simpler than diffing
  // against the previous set, and correct here because orderIndex is only
  // ever assigned from this array's current order.
  private func applyGamePhotos(to target: CD_ChekiRecord) {
    for existing in target.galleryImages {
      viewContext.delete(existing)
    }
    guard isSportsLive else { return }
    for (index, data) in gamePhotosData.enumerated() {
      let image = CD_LiveImage(context: viewContext)
      image.id = UUID()
      image.orderIndex = Int16(index + 1)
      image.data = data
      image.record = target
    }
  }
}
