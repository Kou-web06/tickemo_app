import SwiftUI
import PhotosUI
import CoreLocation

private let ticketPricePresets: [Int] = [3000, 5000, 8000, 10000, 15000]

/// Ports screens/LiveEditScreen.tsx (RN's single shared create/edit form).
/// Artist handling matches RN's ArtistInput/`performances` design exactly:
/// - `sports` bypasses Apple Music search entirely (free-text player/team
///   name, no photo requirement).
/// - `two-man`/`festival` render one independent ArtistSearchField per
///   artist (`artistEntries`), add/remove via a "+ Add artist" row, minimum
///   1 entry — mirrors RN's `performances[]`. Note that unlike RN, the
///   setlist is NOT nested per artist: it is a single flat list in actual
///   performance order, with a per-song performer picker (see
///   SetlistPerformers for why).
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
  @Environment(\.requestReview) private var requestReview

  struct ArtistEntry: Identifiable {
    let id = UUID()
    var name: String
    var imageUrl: String?
  }

  @State private var liveName: String
  @State private var liveType: LiveType
  @State private var date: Date
  @State private var venue: String
  @State private var venueCoordinate: CLLocationCoordinate2D?
  @State private var venueAddress: String?
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

  // セットリスト OCR「まとめて追加」の呈示は Form レベルにアンカーする。
  // SetlistDraftEditorView（Section セル内）から呈示すると、行の再評価で
  // セルごと破棄されて親シート（このフォーム）まで閉じてしまうため。
  @State private var showingSetlistOcrDialog = false
  @State private var isRecognizingSetlistOcr = false

  init(record: CD_ChekiRecord?) {
    self.record = record
    _liveName = State(initialValue: record?.liveName ?? "")
    _liveType = State(initialValue: LiveType.normalized(record?.liveType))
    _date = State(initialValue: DateFormatting.date(from: record?.date) ?? Date())
    _venue = State(initialValue: record?.venue ?? "")
    _venueCoordinate = State(initialValue: record?.venueCoordinate)
    _venueAddress = State(initialValue: record?.venueAddress)
    _seat = State(initialValue: record?.seat ?? "")
    _ticketPriceText = State(initialValue: record.map { String(Int($0.ticketPrice)) } ?? "")
    _startTime = State(initialValue: record?.startTime ?? "18:00")
    _endTime = State(initialValue: record?.endTime ?? "20:00")
    let entries = Self.initialArtistEntries(for: record)
    _artistEntries = State(initialValue: entries)
    _setlistItems = State(initialValue: record.map {
      SetlistDraftItem.drafts(from: $0, artistNames: entries.map(\.name))
    } ?? [])
    _memo = State(initialValue: record?.memo ?? "")
    _qrCode = State(initialValue: record?.qrCode ?? "")
    _coverImageData = State(initialValue: record?.coverImageData)
    _gamePhotosData = State(initialValue: record?.galleryImages.compactMap(\.data) ?? [])
  }

  private static let maxGamePhotos = 6

  private static func initialArtistEntries(for record: CD_ChekiRecord?) -> [ArtistEntry] {
    guard let record else { return [ArtistEntry(name: "", imageUrl: nil)] }
    let names = record.artistsArray?.isEmpty == false ? record.artistsArray! : [record.artist ?? ""]
    let urls = record.artistImageUrlsArray ?? []
    let entries = names.enumerated().map { index, name in
      ArtistEntry(name: name, imageUrl: index < urls.count ? urls[index] : (index == 0 ? record.artistImageUrl : nil))
    }
    return entries.isEmpty ? [ArtistEntry(name: "", imageUrl: nil)] : entries
  }

  /// OCR メタデータ補完のヒントに使う先頭アーティスト名（未入力なら nil）。
  private var primaryArtistName: String? {
    artistEntries.first { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }?.name
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

  private var isArtistFulfilled: Bool {
    if liveType == .sports {
      return !(artistEntries.first?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }
    let named = artistEntries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    return !named.isEmpty && named.allSatisfy { !($0.imageUrl ?? "").isEmpty }
  }

  private var requiredTag: some View {
    Text("必須")
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(Color.purple.opacity(0.85))
      .clipShape(Capsule())
  }

  private func sectionHeader(_ title: String, isFulfilled: Bool) -> some View {
    HStack(spacing: 6) {
      Text(title)
      if !isFulfilled {
        requiredTag
      }
    }
    .textCase(nil)
  }

  private var venuePlaceholder: String {
    switch liveType {
    case .streaming: "プラットフォーム / URL"
    case .sports: "スタジアム / アリーナ"
    default: "会場名"
    }
  }

  private var coverImageSectionTitle: String {
    isSportsLive ? "選手 / 球団の写真" : "カバーアート（表紙）"
  }

  @Environment(\.appFontChoice) private var appFont
  @Environment(\.appBgColor) private var bgColor
  @Environment(\.appCardBgColor) private var cardBgColor

  private var rowBg: Color { cardBgColor ?? Color(.secondarySystemGroupedBackground) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent {
            TextField("入力してください", text: $liveName)
              .multilineTextAlignment(.trailing)
          } label: {
            HStack(spacing: 6) {
              Text("ライブ名")
              if liveName.trimmingCharacters(in: .whitespaces).isEmpty {
                requiredTag
              }
            }
          }
          Picker("ライブの種類", selection: $liveType) {
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
          DatePicker("日付", selection: $date, displayedComponents: .date)
        }
        .listRowBackground(rowBg)

        Section {
          VenueSearchField(name: $venue, coordinate: $venueCoordinate, address: $venueAddress, placeholder: venuePlaceholder)
          TextField("座席（任意）", text: $seat)
        } header: {
          sectionHeader("会場", isFulfilled: !venue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .listRowBackground(rowBg)

        Section("チケット料金") {
          TextField("金額", text: $ticketPriceText)
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
        .listRowBackground(rowBg)

        Section("時間") {
          TimeWheelPickerField(label: "開場", value: $startTime)
          TimeWheelPickerField(label: "開演", value: $endTime)
        }
        .listRowBackground(rowBg)

        Section {
          artistSection
        } header: {
          sectionHeader("アーティスト", isFulfilled: isArtistFulfilled)
        }
        .listRowBackground(rowBg)

        // 対バン／フェスもここに含める。以前はアーティストごとに独立した
        // セトリ欄を出していたが、それだと交互演奏が表現できないため、
        // ライブ種別によらず「実際の演奏順の1本のリスト」に統一した。
        // OCR まとめて追加も種別を問わず使えるようになる。
        if !isSportsLive {
          Section("セットリスト") {
            SetlistDraftEditorView(
              items: $setlistItems,
              showsOcrButton: true,
              performerChoices: artistEntries.map(\.name),
              ocr: SetlistOcrBridge(
                showingSourceDialog: $showingSetlistOcrDialog,
                isRecognizing: $isRecognizingSetlistOcr
              )
            )
          }
          .listRowBackground(rowBg)
        }

        Section(coverImageSectionTitle) {
          coverImagePreview
          PhotosPicker("写真を選択", selection: $selectedPhotoItem, matching: .images)
          if coverImageData != nil {
            Button("写真を削除", role: .destructive) { coverImageData = nil }
          }
        }
        .listRowBackground(rowBg)

        if isSportsLive {
          Section("観戦写真") {
            gamePhotosGrid
          }
          .listRowBackground(rowBg)
        }

        Section {
          TextField("感想", text: $memo, axis: .vertical)
            .lineLimit(3...8)
        }
        .listRowBackground(rowBg)

        Section("QRコード") {
          TextField("https://...", text: $qrCode)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .listRowBackground(rowBg)
      }
      .scrollContentBackground(.hidden)
      .background((bgColor ?? Color(.systemGroupedBackground)).ignoresSafeArea())
      .navigationTitle(record == nil ? "チケットを追加" : "チケットを編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { showingDiscardConfirmation = true } label: {
            HugeIconView(icon: HugeIcons.cancel01, size: 17)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save() }
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
      // OCR「まとめて追加」の呈示系は Form 直付け（Section の外＝安定アンカー）。
      .setlistOcrImport(
        items: $setlistItems,
        artistHint: primaryArtistName,
        showingSourceDialog: $showingSetlistOcrDialog,
        isRecognizing: $isRecognizingSetlistOcr
      )
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
      TextField("選手 / チーム", text: artistNameBinding(0))
    } else if isMultiArtistLive {
      ForEach(Array(artistEntries.enumerated()), id: \.element.id) { index, _ in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("アーティスト\(index + 1)")
              .font(appFont.bold(12))
              .foregroundStyle(.secondary)
            Spacer()
            if artistEntries.count > 1 {
              Button(role: .destructive) {
                removeArtist(at: index)
              } label: {
                HugeIconView(icon: HugeIcons.delete02, size: 16)
              }
              .buttonStyle(.plain)
            }
          }
          ArtistSearchField(name: artistNameBinding(index), imageUrl: artistImageUrlBinding(index))
        }
        .padding(.vertical, 4)
      }
      Button {
        artistEntries.append(ArtistEntry(name: "", imageUrl: nil))
      } label: {
        HugeIconLabel(icon: HugeIcons.add01) { Text("アーティストを追加") }
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

  /// 出演者を消したら、その人に紐づいていた曲のタグも落とす。残したまま
  /// だと、もういない出演者の見出しがセトリに出続けてしまう。
  private func removeArtist(at index: Int) {
    guard artistEntries.indices.contains(index) else { return }
    let removed = SetlistPerformers.normalized(artistEntries[index].name)
    artistEntries.remove(at: index)
    guard let removed else { return }
    for itemIndex in setlistItems.indices
    where setlistItems[itemIndex].performerName?.caseInsensitiveCompare(removed) == .orderedSame {
      setlistItems[itemIndex].performerName = nil
    }
  }

  private var namedArtistNames: [String] {
    artistEntries.compactMap { SetlistPerformers.normalized($0.name) }
  }

  /// 保存時に出演者タグを現在のアーティスト欄と突き合わせる。ライブ種別を
  /// 単独公演に変えた／アーティストを消した／名前を選び直した後に、実在
  /// しない出演者名が残らないようにするための最終フィルタ。表記は
  /// アーティスト欄側に寄せる。
  private func canonicalPerformer(_ raw: String?) -> String? {
    guard namedArtistNames.count > 1, let name = SetlistPerformers.normalized(raw) else { return nil }
    return namedArtistNames.first { $0.caseInsensitiveCompare(name) == .orderedSame }
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
    target.venueAddress = venueAddress
    target.venueLatitude = venueCoordinate.map { NSNumber(value: $0.latitude) }
    target.venueLongitude = venueCoordinate.map { NSNumber(value: $0.longitude) }
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
    // Ports utils/appReview.ts's trackTicketSaveForReview cadence (every
    // other create/update) — the platform review sheet only, no custom
    // pre-screening UI (see AppReviewTracker's doc comment). Apple's
    // guidance is to call requestReview() only once the app is back in a
    // stable state, not mid-transition — StoreKit is free to silently drop
    // the request otherwise — so this fires after the dismiss animation
    // has had time to finish rather than in the same tick as `dismiss()`.
    let shouldPromptForReview = AppReviewTracker.shouldPromptAfterSave()
    dismiss()
    if shouldPromptForReview {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        requestReview()
      }
    }
  }

  // Sports never has a setlist (matches RN, which hides the whole section
  // for isSportsLive). それ以外は画面上の並び＝実際の演奏順なので、
  // 並べ替えずにそのまま保存する。
  private func applySetlist(to target: CD_ChekiRecord) {
    guard !isSportsLive else {
      SetlistDraftItem.apply([], to: target, in: viewContext)
      return
    }
    let sanitized = setlistItems.map { draft -> SetlistDraftItem in
      var copy = draft
      copy.performerName = canonicalPerformer(draft.performerName)
      return copy
    }
    SetlistDraftItem.apply(sanitized, to: target, in: viewContext)
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
