import SwiftUI

/// OCR後の確認・編集画面。認識済み曲名を1行1曲のプレーンテキストで表示し、
/// ユーザーが自由に編集・並び替え・ENCORE/MC挿入できる。
/// MusicKit検索は行わず、テキストをそのまま SetlistDraftItem に変換して返す。
struct SetlistOcrReviewView: View {
  var onConfirm: ([String]) -> Void
  var onCancel: () -> Void

  @State private var text: String
  @State private var showingEmptyAlert = false
  @FocusState private var isEditorFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(lines: [String], onConfirm: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    _text = State(initialValue: lines.joined(separator: "\n"))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if #available(iOS 18.0, *) {
          CursorMarkerEditor(text: $text, focus: $isEditorFocused)
        } else {
          // iOS 17 は TextEditor からカーソル位置を取得できないため従来どおり末尾に追加
          TextEditor(text: $text)
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .focused($isEditorFocused)

          Divider()

          MarkerInsertionBar { appendMarker($0) }
        }
      }
      .navigationTitle("セットリストを確認")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            onCancel()
            dismiss()
          } label: {
            HugeIconView(icon: HugeIcons.cancel01, size: 17)
          }
        }
        ToolbarItem(placement: .keyboard) {
          Button("完了") { isEditorFocused = false }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button(action: confirm) {
          Text("この内容で追加")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(hex: "#A226D9"))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
      }
      .alert("追加できる曲名がありません。", isPresented: $showingEmptyAlert) {
        Button("OK", role: .cancel) {}
      }
    }
  }

  // 末尾に改行してマーカーを追加（iOS 17 フォールバック）
  private func appendMarker(_ marker: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    text = trimmed.isEmpty ? marker : trimmed + "\n" + marker
  }

  private func confirm() {
    let lines = text
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !lines.isEmpty else {
      showingEmptyAlert = true
      return
    }
    onConfirm(lines)
    dismiss()
  }
}

// MARK: - 挿入バー（ENCORE / MC）

private struct MarkerInsertionBar: View {
  var onInsert: (String) -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text("挿入：")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      Button("ENCORE") { onInsert("ENCORE") }
        .buttonStyle(.bordered)
        .font(.system(size: 13, weight: .bold))
      Button("MC") { onInsert("MC") }
        .buttonStyle(.bordered)
        .font(.system(size: 13, weight: .bold))
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(.systemGroupedBackground))
  }
}

/// iOS 18 の TextEditor(text:selection:) でカーソル位置を追跡し、
/// ENCORE/MC マーカーをカーソルのある行の直後に独立した行として挿入する。
@available(iOS 18.0, *)
private struct CursorMarkerEditor: View {
  @Binding var text: String
  var focus: FocusState<Bool>.Binding

  @State private var selection: TextSelection?

  var body: some View {
    TextEditor(text: $text, selection: $selection)
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .focused(focus)

    Divider()

    MarkerInsertionBar { insertMarker($0) }
  }

  private func insertMarker(_ marker: String) {
    guard !text.isEmpty else {
      text = marker
      selection = TextSelection(insertionPoint: text.endIndex)
      return
    }

    // カーソル位置（範囲選択中はその末尾側）。未フォーカスなどで選択が
    // 取れない場合は従来どおり文末扱いにする。
    var cursor = text.endIndex
    if let indices = selection?.indices {
      switch indices {
      case .selection(let range):
        cursor = min(range.upperBound, text.endIndex)
      case .multiSelection(let ranges):
        cursor = ranges.ranges.last.map { min($0.upperBound, text.endIndex) } ?? text.endIndex
      @unknown default:
        break
      }
    }

    // 曲名の行を分断しないよう、カーソルのある行の末尾に「改行 + マーカー」を挿入
    let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
    let lineEndOffset = text.distance(from: text.startIndex, to: lineEnd)
    let insertion = "\n" + marker
    text.insert(contentsOf: insertion, at: lineEnd)

    // 連続タップで下に積んでいけるよう、カーソルを挿入したマーカーの末尾へ移す
    selection = TextSelection(
      insertionPoint: text.index(text.startIndex, offsetBy: lineEndOffset + insertion.count)
    )
  }
}
