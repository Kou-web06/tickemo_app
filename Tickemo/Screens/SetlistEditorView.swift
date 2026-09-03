import SwiftUI
import CoreData

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
  /// 音源のアーティスト（Apple Music の検索結果由来、自動入力）。
  /// 「その公演で実際に演奏した出演者」は `performerName` の方なので、
  /// 交互演奏の判定にこちらを使わないこと — 詳細は SetlistPerformers。
  var artistName: String?
  var albumName: String?
  var artworkUrl: String?
  /// この曲を演奏した出演者。対バン／フェスでのみ意味を持ち、単独公演では
  /// 常に nil のまま（全行に同じ名前を書いても情報が増えないため）。
  var performerName: String?
  /// Encore label text, or the editable MC talk text. Non-optional so it can
  /// bind directly to a TextField.
  var title: String = ""
}

extension SetlistDraftItem {
  /// 保存済みセトリをドラフトへ読み出す。出演者は保存値が無い行を
  /// `SetlistPerformers.resolve` で埋めるので、`performerName` を持たない
  /// 旧データ（このフィールド追加以前に保存されたもの）を開いても、
  /// 音源アーティストの一致と直前の行からの引き継ぎで復元される。
  static func drafts(from record: CD_ChekiRecord, artistNames: [String]) -> [SetlistDraftItem] {
    let items = record.sortedSetlistItems
    var drafts = items.map { cdItem in
      SetlistDraftItem(
        id: cdItem.id ?? UUID(),
        kind: Kind(rawValue: cdItem.kind ?? "song") ?? .song,
        songId: cdItem.songId,
        songName: cdItem.songName,
        artistName: cdItem.artistName,
        albumName: cdItem.albumName,
        artworkUrl: cdItem.artworkUrl,
        performerName: cdItem.performerName,
        title: cdItem.title ?? ""
      )
    }
    let resolved = SetlistPerformers.resolve(
      stored: drafts.map(\.performerName),
      songArtists: drafts.map(\.artistName),
      artistNames: artistNames
    )
    for index in drafts.indices {
      drafts[index].performerName = resolved[index]
    }
    return drafts
  }

  /// 保存前に出演者タグを整える。登録アーティストに無い名前を落としたうえで、
  /// 出演者が1組しかいない公演では未指定の曲にその1組を入れる。後者が
  /// あるおかげで、ワンマンのカバー曲も「原曲のアーティスト」ではなく
  /// 「実際に歌った人」として表示・検索されるようになる。
  /// 区切り行（MC / アンコール）は表示に出ないので自動補完はしない。
  static func normalizingPerformers(
    _ drafts: [SetlistDraftItem],
    artistNames: [String]
  ) -> [SetlistDraftItem] {
    let fallback = SetlistPerformers.soleArtist(in: artistNames)
    return drafts.map { draft in
      var copy = draft
      let canonical = SetlistPerformers.canonical(draft.performerName, artistNames: artistNames)
      copy.performerName = canonical ?? (draft.kind == .song ? fallback : nil)
      return copy
    }
  }

  /// ドラフトを Core Data へ書き戻す（既存行は全消しして作り直す）。
  /// RecordFormView のインライン編集と SetlistEditorView シートの両方から
  /// 呼ぶ — `performerName` の書き漏らしを片方だけで起こさないよう、
  /// 保存経路をここに一本化してある。
  static func apply(
    _ drafts: [SetlistDraftItem],
    to record: CD_ChekiRecord,
    in context: NSManagedObjectContext
  ) {
    for existing in record.sortedSetlistItems {
      context.delete(existing)
    }
    for (index, draft) in drafts.enumerated() {
      let cdItem = CD_SetlistItem(context: context)
      cdItem.id = draft.id
      cdItem.orderIndex = Int32(index)
      cdItem.kind = draft.kind.rawValue
      cdItem.performerName = SetlistPerformers.normalized(draft.performerName)
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
  }
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

  private let performerChoices: [String]

  init(record: CD_ChekiRecord) {
    self.record = record
    let artistNames = ArtistGrouping.names(for: record)
    self.performerChoices = artistNames
    _items = State(initialValue: SetlistDraftItem.drafts(from: record, artistNames: artistNames))
  }

  var body: some View {
    NavigationStack {
      List {
        // Not OCR-enabled here — RN's bulk-register only exists on
        // LiveEditScreen's inline single-artist setlist field, never on a
        // standalone post-creation editor.
        SetlistDraftEditorView(items: $items, performerChoices: performerChoices)
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
    let normalized = SetlistDraftItem.normalizingPerformers(items, artistNames: performerChoices)
    SetlistDraftItem.apply(normalized, to: record, in: viewContext)
    try? viewContext.save()
    dismiss()
  }
}
