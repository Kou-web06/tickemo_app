import SwiftUI
import UIKit

/// OCR後の確認・編集画面。認識済み曲名を1行1曲のプレーンテキストで表示し、
/// ユーザーが自由に編集・並び替え・ENCORE/MC挿入できる。
/// MusicKit検索は行わず、テキストをそのまま SetlistDraftItem に変換して返す。
struct SetlistOcrReviewView: View {
  var onConfirm: ([String]) -> Void
  var onCancel: () -> Void

  @State private var text: String
  @State private var showingEmptyAlert = false
  @State private var editor = SetlistTextEditorController()
  @Environment(\.dismiss) private var dismiss

  init(lines: [String], onConfirm: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    _text = State(initialValue: lines.joined(separator: "\n"))
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // SwiftUI の TextEditor(text:selection:) は日本語入力の変換中にも
        // 選択範囲を書き戻して未確定文字を確定させてしまい、変換できなかった。
        // UITextView を直接包み、変換中は SwiftUI 側から一切書き戻さない。
        SetlistPlainTextEditor(text: $text, font: appFont.uiFont(15), controller: editor)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)

        Divider()

        MarkerInsertionBar { editor.insertMarker($0) }
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
      }
      .safeAreaInset(edge: .bottom) {
        Button(action: confirm) {
          Text("この内容で追加")
            .font(appFont.bold(16))
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

  private func confirm() {
    // 変換中の文字があれば確定させてから読む
    editor.commitComposition()
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

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    HStack(spacing: 10) {
      Text("挿入：")
        .font(appFont.regular(13))
        .foregroundStyle(.secondary)
      Button("ENCORE") { onInsert("ENCORE") }
        .buttonStyle(.bordered)
        .font(appFont.bold(13))
      Button("MC") { onInsert("MC") }
        .buttonStyle(.bordered)
        .font(appFont.bold(13))
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(.systemGroupedBackground))
  }
}

/// 確認画面の UITextView への操作口（ENCORE / MC の挿入、変換の確定）。
final class SetlistTextEditorController {
  fileprivate weak var textView: UITextView?

  /// カーソルのある行の直後にマーカーを独立した行として挿入する
  /// （位置の計算は SetlistMarkerInsertion）。変換中なら先に確定させる。
  func insertMarker(_ marker: String) {
    guard let textView else { return }
    textView.unmarkText()
    let current = textView.text ?? ""
    let cursor = textView.isFirstResponder ? textView.selectedRange.upperBound : (current as NSString).length
    let result = SetlistMarkerInsertion.inserting(marker, into: current, cursorUTF16: cursor)
    textView.text = result.text
    textView.selectedRange = NSRange(location: result.cursorUTF16, length: 0)
    textView.scrollRangeToVisible(textView.selectedRange)
    // プログラムからの変更では textViewDidChange が呼ばれないので明示的に通知する
    textView.delegate?.textViewDidChange?(textView)
  }

  func commitComposition() {
    guard let textView, textView.markedTextRange != nil else { return }
    textView.unmarkText()
    textView.delegate?.textViewDidChange?(textView)
  }
}

/// 日本語入力の変換を壊さない複数行テキスト入力。
/// - UITextView → SwiftUI へは `textViewDidChange` で毎回伝える
/// - SwiftUI → UITextView へは、内容が違い、かつ変換中（markedTextRange
///   あり）でないときだけ反映する。変換中に書き戻すと未確定文字が確定されて
///   しまうため
private struct SetlistPlainTextEditor: UIViewRepresentable {
  @Binding var text: String
  var font: UIFont
  let controller: SetlistTextEditorController

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.font = font
    textView.text = text
    textView.backgroundColor = .clear
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    textView.keyboardDismissMode = .interactive
    textView.alwaysBounceVertical = true
    textView.inputAccessoryView = Self.doneToolbar(for: textView)
    controller.textView = textView
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.text = $text
    controller.textView = textView
    if textView.font != font {
      textView.font = font
    }
    guard textView.markedTextRange == nil, textView.text != text else { return }
    let selection = textView.selectedRange
    textView.text = text
    let length = (text as NSString).length
    textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
  }

  /// キーボード上の「完了」。SwiftUI の `.toolbar(.keyboard)` は UIKit の
  /// 入力欄には出ないので UIKit 側で付ける
  private static func doneToolbar(for textView: UITextView) -> UIToolbar {
    let toolbar = UIToolbar()
    toolbar.items = [
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(title: "完了", primaryAction: UIAction { [weak textView] _ in
        textView?.resignFirstResponder()
      }),
    ]
    toolbar.sizeToFit()
    return toolbar
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func textViewDidChange(_ textView: UITextView) {
      let value = textView.text ?? ""
      if text.wrappedValue != value {
        text.wrappedValue = value
      }
    }
  }
}
