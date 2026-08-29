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
/// The actual search/list/OCR UI lives in SetlistDraftEditorView (shared
/// with RecordFormView's inline setlist section) — this view is now just
/// that component wrapped in its own sheet chrome plus the Core Data
/// read/write RecordFormView's inline copy doesn't need (this is reached
/// post-creation, from RecordDetailView's "Add Setlist"/"Edit").
struct SetlistEditorView: View {
  @ObservedObject var record: CD_ChekiRecord

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss
  @Environment(\.appBgColor) private var bgColor
  @Environment(\.appCardBgColor) private var cardBgColor

  @State private var items: [SetlistDraftItem]

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
      List {
        // Not OCR-enabled here — RN's bulk-register only exists on
        // LiveEditScreen's inline single-artist setlist field, never on a
        // standalone post-creation editor.
        SetlistDraftEditorView(items: $items)
          .listRowBackground(cardBgColor ?? Color(.systemBackground))
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background((bgColor ?? Color(.systemBackground)).ignoresSafeArea())
      .navigationTitle("Setlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: {
            Image("Close remove")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 17, height: 17)
          }
        }
        ToolbarItem(placement: .primaryAction) {
          EditButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
        }
      }
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
