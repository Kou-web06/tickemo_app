import SwiftUI

struct SetlistDraftEditorView: View {
  @Binding var items: [SetlistDraftItem]
  var showsOcrButton: Bool = false
  /// OCR 一括登録フローとの受け渡し口。`showsOcrButton` が true のとき必須。
  /// 呈示系（カメラ／アルバム／レビュー）は Form セル内に置くと親シートごと
  /// 閉じてしまうため、`RecordFormView` 側の `.setlistOcrImport(...)` が持つ。
  /// 詳細は SetlistOcrImport.swift のコメント参照。
  var ocr: SetlistOcrBridge? = nil

  @State private var searchText = ""
  @State private var searchResults: [AppleMusicService.SongResult] = []
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?

  private let appleMusicService = AppleMusicService()

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    Group {
      searchSection
      songRows
    }
    .onChange(of: searchText) { _, newValue in
      scheduleSearch(term: newValue)
    }
  }

  // MARK: - Search + OCR trigger

  private var searchSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        HugeIconView(icon: HugeIcons.search01, size: 18)
          .foregroundStyle(Color(white: 0.6))

        TextField("曲名を検索", text: $searchText)
          .autocorrectionDisabled()

        if isSearching {
          ProgressView()
        }

        if showsOcrButton, let ocr {
          Button {
            guard !ocr.isRecognizing else { return }
            ocr.showingSourceDialog = true
          } label: {
            if ocr.isRecognizing {
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
          .disabled(ocr.isRecognizing)
        }

        Menu {
          Button("📣 アンコール区切りを追加") { addEncore() }
          Button("🎙️ MC / トークを追加") { addMC() }
        } label: {
          HugeIconView(icon: HugeIcons.plusSignCircle, size: 22)
        }
      }

      if !isSearching && !searchResults.isEmpty {
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
        .font(appFont.bold(13))
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
      TextField("MCの内容を入力", text: item.title)
    }
  }
}
