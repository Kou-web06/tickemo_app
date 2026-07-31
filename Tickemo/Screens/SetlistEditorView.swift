import SwiftUI

/// Local draft of one setlist row, decoupled from Core Data until Save
/// (same convention as RecordFormView) so Cancel never touches the context.
struct SetlistDraftItem: Identifiable, Equatable {
  enum Kind: String {
    case song, encore, mc
  }

  let id: UUID
  var kind: Kind
  var songId: String?
  var songName: String?
  var artistName: String?
  var albumName: String?
  var artworkUrl: String?
  /// Encore label text, or the editable MC talk text. Non-optional so it can
  /// bind directly to a TextField.
  var title: String = ""
}

/// Ports components/SetlistEditor.tsx's structure to SwiftUI: Apple-Music-
/// backed song search (native MusicKit via AppleMusicService.searchSongs,
/// not RN's REST API), explicit Add Encore/Add MC buttons instead of RN's
/// keyword-detection-while-typing, and idiomatic List reordering/deletion
/// (.onMove/.onDelete/EditButton) instead of a custom drag-handle gesture.
/// OCR photo-to-setlist import is explicitly out of scope.
struct SetlistEditorView: View {
  @ObservedObject var record: CD_ChekiRecord

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  private let appleMusicService = AppleMusicService()

  @State private var items: [SetlistDraftItem]
  @State private var searchText = ""
  @State private var searchResults: [AppleMusicService.SongResult] = []
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?

  init(record: CD_ChekiRecord) {
    self.record = record
    _items = State(initialValue: record.sortedSetlistItems.map { cdItem in
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
    })
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchSection

        List {
          ForEach($items) { $item in
            row(for: $item)
          }
          .onMove { items.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { items.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
      }
      .navigationTitle("Setlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          EditButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
        }
      }
      .onChange(of: searchText) { _, newValue in
        scheduleSearch(term: newValue)
      }
    }
  }

  // MARK: - Search

  private var searchSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search a song", text: $searchText)
          .textFieldStyle(.roundedBorder)

        Menu {
          Button("Add Encore") { addEncore() }
          Button("Add MC") { addMC() }
        } label: {
          HugeIconView(icon: HugeIcons.plusSignCircle, size: 22)
        }
      }
      .padding(.horizontal)
      .padding(.top, 8)

      if isSearching {
        ProgressView()
          .padding(.horizontal)
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
    .padding(.bottom, 8)
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
    .padding(.horizontal)
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

  @ViewBuilder
  private func row(for item: Binding<SetlistDraftItem>) -> some View {
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

  // MARK: - Save

  private func save() {
    for existing in record.sortedSetlistItems {
      viewContext.delete(existing)
    }
    for (index, draft) in items.enumerated() {
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
      cdItem.record = record
    }
    try? viewContext.save()
    dismiss()
  }
}
