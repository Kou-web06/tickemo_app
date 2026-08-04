import SwiftUI

struct SetlistDraftEditorView: View {
  @Binding var items: [SetlistDraftItem]
  var showsOcrButton: Bool = false

  @State private var searchText = ""
  @State private var searchResults: [AppleMusicService.SongResult] = []
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?

  @State private var showingSourceDialog = false
  // Camera uses fullScreenCover — sheet clips the viewfinder and hides the shutter button.
  @State private var showingCameraPicker = false
  @State private var activeSheet: ActiveSheet?
  @State private var isRecognizing = false
  @State private var showingCameraUnavailableAlert = false
  @State private var showingOcrErrorAlert = false
  @State private var showingNoTextAlert = false

  private let appleMusicService = AppleMusicService()

  private struct OcrLinesWrapper: Identifiable {
    let id = UUID()
    let lines: [String]
  }

  private enum ActiveSheet: Identifiable {
    case library
    case ocrReview(OcrLinesWrapper)

    var id: String {
      switch self {
      case .library: return "library"
      case .ocrReview(let w): return "review-\(w.id.uuidString)"
      }
    }
  }

  var body: some View {
    Group {
      searchSection
      songRows
    }
    .onChange(of: searchText) { _, newValue in
      scheduleSearch(term: newValue)
    }
    // Camera must be fullScreenCover: UIImagePickerController needs the full
    // screen to render the viewfinder and shutter button correctly.
    .fullScreenCover(isPresented: $showingCameraPicker) {
      ImagePickerRepresentable(sourceType: .camera, allowsEditing: false) { data in
        runOcr(on: data)
      }
      .ignoresSafeArea()
    }
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .library:
        ImagePickerRepresentable(sourceType: .photoLibrary, allowsEditing: false) { data in
          runOcr(on: data)
        }
        .ignoresSafeArea()
      case .ocrReview(let wrapper):
        SetlistOcrReviewView(lines: wrapper.lines) { confirmedLines in
          Task { await addWithMusicKit(lines: confirmedLines) }
        } onCancel: {}
      }
    }
    .alert("カメラを起動できませんでした。もう一度お試しください。", isPresented: $showingCameraUnavailableAlert) {
      Button("OK", role: .cancel) {}
    }
    .alert("画像からテキストを取得できませんでした。もう一度お試しください。", isPresented: $showingOcrErrorAlert) {
      Button("OK", role: .cancel) {}
    }
    .alert("テキストを検出できませんでした。別の画像をお試しください。", isPresented: $showingNoTextAlert) {
      Button("OK", role: .cancel) {}
    }
  }

  // MARK: - Search + OCR trigger

  private var searchSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search a song", text: $searchText)
          .textFieldStyle(.roundedBorder)

        if showsOcrButton {
          Button {
            guard !isRecognizing else { return }
            showingSourceDialog = true
          } label: {
            if isRecognizing {
              ProgressView()
            } else {
              Image("edit ai")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color(white: 0.6))
            }
          }
          .disabled(isRecognizing)
          .confirmationDialog("まとめて追加", isPresented: $showingSourceDialog, titleVisibility: .visible) {
            Button("カメラで撮影") {
              if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showingCameraPicker = true
              } else {
                showingCameraUnavailableAlert = true
              }
            }
            Button("アルバムから選ぶ") { activeSheet = .library }
            Button("キャンセル", role: .cancel) {}
          }
        }

        Menu {
          Button("Add Encore") { addEncore() }
          Button("Add MC") { addMC() }
        } label: {
          HugeIconView(icon: HugeIcons.plusSignCircle, size: 22)
        }
      }

      if isSearching {
        ProgressView()
      } else if !searchResults.isEmpty {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(searchResults, id: \.id) { result in
              Button {
                addSong(result)
              } label: {
                searchResultRow(result)
              }
              .buttonStyle(.plain)
              Divider()
            }
          }
        }
        .frame(maxHeight: 220)
      }
    }
  }

  private func searchResultRow(_ result: AppleMusicService.SongResult) -> some View {
    HStack(spacing: 10) {
      AsyncImage(url: URL(string: result.artworkUrl)) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color(.tertiarySystemBackground)
      }
      .frame(width: 40, height: 40)
      .clipShape(RoundedRectangle(cornerRadius: 6))

      VStack(alignment: .leading, spacing: 2) {
        Text(result.title).font(.subheadline).lineLimit(1)
        Text(result.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }

  private func scheduleSearch(term: String) {
    searchTask?.cancel()
    let trimmed = term.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      searchResults = []
      isSearching = false
      return
    }
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard !Task.isCancelled else { return }
      isSearching = true
      let results = (try? await appleMusicService.searchSongs(term: trimmed)) ?? []
      guard !Task.isCancelled else { return }
      searchResults = results
      isSearching = false
    }
  }

  // MARK: - OCR → MusicKit enrichment

  // Searches each confirmed line via MusicKit in parallel (preserving order).
  // Songs found get artwork/metadata; unmatched songs fall back to text-only.
  private func addWithMusicKit(lines: [String]) async {
    isRecognizing = true
    defer { isRecognizing = false }

    let enriched: [SetlistDraftItem] = await withTaskGroup(of: (Int, SetlistDraftItem).self) { group in
      for (i, line) in lines.enumerated() {
        group.addTask {
          if let result = try? await AppleMusicService().searchSongs(term: line).first {
            return (i, SetlistDraftItem(
              id: UUID(), kind: .song,
              songId: result.id, songName: result.title,
              artistName: result.artistName, albumName: result.albumName,
              artworkUrl: result.artworkUrl
            ))
          }
          return (i, SetlistDraftItem(id: UUID(), kind: .song, songName: line))
        }
      }
      var pairs: [(Int, SetlistDraftItem)] = []
      for await pair in group { pairs.append(pair) }
      return pairs.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    items.append(contentsOf: enriched)
  }

  // MARK: - OCR pipeline

  private func runOcr(on imageData: Data) {
    isRecognizing = true
    Task {
      defer { isRecognizing = false }
      do {
        let rawText = try await SetlistOcrRecognizer.recognizeText(in: imageData)
        let lines = SetlistOcrCleanup.cleanedLines(from: rawText)
        guard !lines.isEmpty else {
          showingNoTextAlert = true
          return
        }
        activeSheet = .ocrReview(OcrLinesWrapper(lines: lines))
      } catch {
        showingOcrErrorAlert = true
      }
    }
  }

  // MARK: - Adding rows

  private func addSong(_ result: AppleMusicService.SongResult) {
    items.append(SetlistDraftItem(
      id: UUID(),
      kind: .song,
      songId: result.id,
      songName: result.title,
      artistName: result.artistName,
      albumName: result.albumName,
      artworkUrl: result.artworkUrl
    ))
    searchText = ""
    searchResults = []
  }

  private func addEncore() {
    items.append(SetlistDraftItem(id: UUID(), kind: .encore, title: "ENCORE"))
  }

  private func addMC() {
    items.append(SetlistDraftItem(id: UUID(), kind: .mc, title: ""))
  }

  // MARK: - Rows

  private var songRows: some View {
    ForEach($items) { $item in
      row(for: $item)
    }
    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
  }

  private func row(for item: Binding<SetlistDraftItem>) -> some View {
    HStack(spacing: 8) {
      rowContent(for: item)
      Spacer(minLength: 8)
      Button(role: .destructive) {
        let id = item.wrappedValue.id
        items.removeAll { $0.id == id }
      } label: {
        HugeIconView(icon: HugeIcons.delete02, size: 14)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func rowContent(for item: Binding<SetlistDraftItem>) -> some View {
    switch item.wrappedValue.kind {
    case .song:
      songRow(item.wrappedValue)
    case .encore:
      SetlistMarkerDivider(text: item.wrappedValue.title)
    case .mc:
      mcRow(item)
    }
  }

  private func songRow(_ item: SetlistDraftItem) -> some View {
    HStack(spacing: 10) {
      Text("\((songIndex(of: item) ?? 0) + 1)")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color(white: 0.4))
        .frame(width: 28, height: 28)
        .background(Color(white: 0.94))
        .clipShape(Circle())

      AsyncImage(url: URL(string: item.artworkUrl ?? "")) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color(.tertiarySystemBackground)
      }
      .frame(width: 50, height: 50)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(item.songName ?? "-").font(.subheadline.weight(.semibold)).lineLimit(1)
        if let artistName = item.artistName, !artistName.isEmpty {
          Text(artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    }
  }

  private func songIndex(of item: SetlistDraftItem) -> Int? {
    items.filter { $0.kind == .song }.firstIndex(where: { $0.id == item.id })
  }

  private func mcRow(_ item: Binding<SetlistDraftItem>) -> some View {
    HStack(spacing: 10) {
      HugeIconView(icon: HugeIcons.mic01, size: 17)
        .foregroundStyle(Color(white: 0.5))
      TextField("MC talk", text: item.title)
    }
  }
}
