import SwiftUI
import Lottie

struct SetlistDraftEditorView: View {
  @Binding var items: [SetlistDraftItem]
  var showsOcrButton: Bool = false
  /// 対バン／フェスで登録済みの出演者名。2組以上あるときだけ各曲行に
  /// 出演者ピッカーと、出演者が切り替わる位置の見出しを出す。
  var performerChoices: [String] = []
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
              LottieView(animation: .named("edit"))
                .playing(loopMode: .loop)
                .frame(width: 24, height: 24)
                .grayscale(1.0)
                .opacity(0.4)
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
      artworkUrl: result.artworkUrl,
      performerName: performerForNewSong
    ))
    searchText = ""
    searchResults = []
  }

  // MARK: - Performers

  private var namedPerformerChoices: [String] {
    performerChoices.compactMap(SetlistPerformers.normalized)
  }

  private var showsPerformerPicker: Bool { namedPerformerChoices.count > 1 }

  /// 新しく追加する曲の出演者は直前の曲から引き継ぐ。A→A→A→B→B→A の
  /// ように上から順に入力していく場合、切り替わる行でだけピッカーを
  /// 触れば済む。
  private var performerForNewSong: String? {
    guard showsPerformerPicker else { return nil }
    let carried = items.reversed().compactMap { SetlistPerformers.normalized($0.performerName) }.first
    return carried ?? namedPerformerChoices.first
  }

  /// 曲 ID をキーにした「この行の上に出す出演者見出し」。行ごとに
  /// 引き直すと O(n^2) になるので、`songRows` で一度だけ組み立てて配る。
  private var performerHeaders: [UUID: String] {
    let labels = SetlistPerformers.sectionHeaders(for: items.map(\.performerName))
    var map: [UUID: String] = [:]
    for (index, label) in labels.enumerated() {
      if let label { map[items[index].id] = label }
    }
    return map
  }

  /// 入力済みのセトリに後から出演者を割り当てるとき、1行ずつ選び直すのは
  /// 現実的でないので「ここから下をまとめて」を用意する。対象は曲行のみ
  /// （MC / アンコールは直前のブロックに従うので触らない）。
  private func applyPerformer(_ name: String, from itemID: UUID) {
    guard let start = items.firstIndex(where: { $0.id == itemID }) else { return }
    for index in start..<items.count where items[index].kind == .song {
      items[index].performerName = name
    }
  }

  private func performerMenu(_ item: Binding<SetlistDraftItem>) -> some View {
    let current = SetlistPerformers.normalized(item.wrappedValue.performerName)
    return Menu {
      ForEach(namedPerformerChoices, id: \.self) { choice in
        Button {
          item.wrappedValue.performerName = choice
        } label: {
          if choice.caseInsensitiveCompare(current ?? "") == .orderedSame {
            Label(choice, systemImage: "checkmark")
          } else {
            Text(choice)
          }
        }
      }
      Divider()
      Menu("ここから下をまとめて変更") {
        ForEach(namedPerformerChoices, id: \.self) { choice in
          Button(choice) {
            applyPerformer(choice, from: item.wrappedValue.id)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        HugeIconView(icon: HugeIcons.userGroup03, size: 11)
        Text(current ?? "出演者を選択")
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(current == nil ? Color.accentColor : Color(white: 0.35))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule().fill(Color(white: 0.94)))
    }
    .buttonStyle(.plain)
  }

  private func addEncore() {
    items.append(SetlistDraftItem(id: UUID(), kind: .encore, title: "ENCORE"))
  }

  private func addMC() {
    items.append(SetlistDraftItem(id: UUID(), kind: .mc, title: ""))
  }

  // MARK: - Rows

  private var songRows: some View {
    let headers = performerHeaders
    return ForEach($items) { $item in
      row(for: $item, headerLabel: headers[item.id])
    }
    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
  }

  private func row(for item: Binding<SetlistDraftItem>, headerLabel: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if let headerLabel {
        SetlistPerformerHeader(name: headerLabel)
      }
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
  }

  @ViewBuilder
  private func rowContent(for item: Binding<SetlistDraftItem>) -> some View {
    switch item.wrappedValue.kind {
    case .song:
      songRow(item)
    case .encore:
      SetlistMarkerDivider(text: item.wrappedValue.title)
    case .mc:
      mcRow(item)
    }
  }

  private func songRow(_ item: Binding<SetlistDraftItem>) -> some View {
    HStack(spacing: 10) {
      Text("\((songIndex(of: item.wrappedValue) ?? 0) + 1)")
        .font(appFont.bold(13))
        .foregroundStyle(Color(white: 0.4))
        .frame(width: 28, height: 28)
        .background(Color(white: 0.94))
        .clipShape(Circle())

      AsyncImage(url: URL(string: item.wrappedValue.artworkUrl ?? "")) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color(.tertiarySystemBackground)
      }
      .frame(width: 50, height: 50)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(item.wrappedValue.songName ?? "-").font(.subheadline.weight(.semibold)).lineLimit(1)
        if let artistName = item.wrappedValue.artistName, !artistName.isEmpty {
          Text(artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        if showsPerformerPicker {
          performerMenu(item)
            .padding(.top, 2)
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
