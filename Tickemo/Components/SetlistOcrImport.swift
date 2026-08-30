import SwiftUI
import PhotosUI

/// OCR「まとめて追加」フローの呈示レイヤー。
///
/// カメラ／アルバムピッカーと OCR レビューシートは、以前は
/// `SetlistDraftEditorView` の内部（＝`Form` の Section セル内）から呈示していた。
/// SwiftUI は `Form`/`List` の行を遅延生成・再利用するため、行セルに紐づいた
/// `.sheet` / `.fullScreenCover` / `.photosPicker` は、その行が再評価された瞬間
/// （OCR 中のスピナー表示、`items` の変化、キーボード表示など）にセルごと
/// 破棄され、呈示が巻き戻る。UIKit 側は最寄りの presented controller を辿るため、
/// 巻き戻りが親シート（＝ホーム上に重ねた `RecordFormView`）まで波及して
/// フォーム自体が閉じてしまう。`.background { Color.clear.sheet(...) }` に
/// 逃がしても、その `Color.clear` は同じセルの子のままなので解決しない。
///
/// 対策として呈示系はすべてここへ集約し、`RecordFormView` の `Form`
/// （Section の外＝再利用されない安定したアンカー）に `.setlistOcrImport(...)`
/// として適用する。`SetlistDraftEditorView` 側はトリガー（ダイアログ表示要求）と
/// 進捗表示だけを `SetlistOcrBridge` 経由で受け渡す。
struct SetlistOcrLines: Identifiable {
  let id = UUID()
  let lines: [String]
}

/// `SetlistDraftEditorView`（Form セル内）と `setlistOcrImport` モディファイア
/// （Form レベル）を結ぶ最小の受け渡し口。
/// - `showingSourceDialog`: 子のボタン → モディファイアの confirmationDialog
/// - `isRecognizing`: モディファイアの OCR 進捗 → 子のスピナー／無効化
struct SetlistOcrBridge {
  @Binding var showingSourceDialog: Bool
  @Binding var isRecognizing: Bool
}

extension View {
  /// OCR 一括登録の呈示系をこのビューにアンカーする。
  /// `Form` など再利用されないコンテナに適用すること（Section セル内は不可）。
  func setlistOcrImport(
    items: Binding<[SetlistDraftItem]>,
    artistHint: String?,
    showingSourceDialog: Binding<Bool>,
    isRecognizing: Binding<Bool>
  ) -> some View {
    modifier(SetlistOcrImportModifier(
      items: items,
      artistHint: artistHint,
      showingSourceDialog: showingSourceDialog,
      isRecognizing: isRecognizing
    ))
  }
}

private struct SetlistOcrImportModifier: ViewModifier {
  @Binding var items: [SetlistDraftItem]
  var artistHint: String?
  @Binding var showingSourceDialog: Bool
  @Binding var isRecognizing: Bool

  // Camera uses fullScreenCover — a sheet clips the viewfinder and hides the shutter button.
  @State private var showingCameraPicker = false
  // Library uses PHPickerViewController via .photosPicker (SwiftUI-native).
  @State private var showingLibraryPicker = false
  @State private var photoPickerItem: PhotosPickerItem?
  @State private var reviewLines: SetlistOcrLines?
  @State private var showingCameraUnavailableAlert = false
  @State private var showingOcrErrorAlert = false
  @State private var showingNoTextAlert = false

  private let appleMusicService = AppleMusicService()

  func body(content: Content) -> some View {
    content
      .confirmationDialog("まとめて追加", isPresented: $showingSourceDialog, titleVisibility: .visible) {
        Button("カメラで撮影") {
          // Wait for the confirmation dialog to fully dismiss before presenting
          // the next sheet. Presenting while the UIAlertController is still
          // animating out causes a UIKit presentation conflict that propagates
          // up and dismisses the parent RecordFormView sheet.
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
              showingCameraPicker = true
            } else {
              showingCameraUnavailableAlert = true
            }
          }
        }
        Button("アルバムから選ぶ") {
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            showingLibraryPicker = true
          }
        }
        Button("キャンセル", role: .cancel) {}
      }
      .photosPicker(isPresented: $showingLibraryPicker, selection: $photoPickerItem, matching: .images)
      .onChange(of: photoPickerItem) { _, newItem in
        guard let newItem else { return }
        Task {
          photoPickerItem = nil
          if let data = try? await newItem.loadTransferable(type: Data.self) {
            runOcr(on: data)
          }
        }
      }
      .fullScreenCover(isPresented: $showingCameraPicker) {
        ImagePickerRepresentable(sourceType: .camera, allowsEditing: false) { data in
          runOcr(on: data)
        }
        .ignoresSafeArea()
      }
      .sheet(item: $reviewLines) { wrapper in
        SetlistOcrReviewView(lines: wrapper.lines) { confirmedLines in
          addOcrLines(confirmedLines)
        } onCancel: {}
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
        reviewLines = SetlistOcrLines(lines: lines)
      } catch {
        showingOcrErrorAlert = true
      }
    }
  }

  // MARK: - OCR confirm → plain-text parse

  // Converts confirmed text lines to SetlistDraftItems.
  // Lines starting with "ENCORE" → encore marker; "MC" → MC row; else → song (text only).
  private func addOcrLines(_ lines: [String]) {
    var addedSongIDs: [UUID] = []
    for line in lines {
      let upper = line.uppercased()
      if upper == "ENCORE" || upper.hasPrefix("ENCORE ") || upper.hasPrefix("ENCORE\t") {
        items.append(SetlistDraftItem(id: UUID(), kind: .encore, title: "ENCORE"))
      } else if upper == "MC" || upper.hasPrefix("MC ") || upper.hasPrefix("MC\t") {
        let talk = line.count > 2 ? String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) : ""
        items.append(SetlistDraftItem(id: UUID(), kind: .mc, title: talk))
      } else {
        let item = SetlistDraftItem(id: UUID(), kind: .song, songName: line)
        items.append(item)
        addedSongIDs.append(item.id)
      }
    }
    guard !addedSongIDs.isEmpty else { return }
    Task { await backfillSongMetadata(ids: addedSongIDs) }
  }

  /// OCR で追加した曲はテキストしか持たずジャケ写が空になるため、
  /// Apple Music 検索の先頭ヒットから artworkUrl などのメタデータを補完する。
  /// songName は OCR レビューでユーザーが確認したテキストなので上書きしない。
  private func backfillSongMetadata(ids: [UUID]) async {
    let hint = artistHint?.trimmingCharacters(in: .whitespaces) ?? ""
    for id in ids {
      guard let name = items.first(where: { $0.id == id })?.songName, !name.isEmpty else { continue }

      var match = hint.isEmpty
        ? nil
        : (try? await appleMusicService.searchSongs(term: "\(name) \(hint)", limit: 1))?.first
      if match == nil {
        // アーティスト名込みでヒットしない場合（表記ゆれ等）は曲名だけで再検索
        match = (try? await appleMusicService.searchSongs(term: name, limit: 1))?.first
      }
      guard let match else { continue }

      // 検索中に並べ替え・削除されている可能性があるので ID で引き直す
      guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
      items[index].songId = match.id
      items[index].artistName = match.artistName
      items[index].albumName = match.albumName
      items[index].artworkUrl = match.artworkUrl
    }
  }
}
