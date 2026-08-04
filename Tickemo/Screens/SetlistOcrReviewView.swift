import SwiftUI

/// Ports LiveEditScreen.tsx's full-screen OCR review UI: a reorderable,
/// inline-editable list of cleaned-up text lines, with suspicious lines
/// (see SetlistOcrCleanup.isSuspicious) flagged in red rather than dropped
/// — recomputed live on every edit, matching RN's own re-check-on-change
/// behavior. Reordering uses drag handles (always-active edit mode); deletion
/// uses a single-tap trash button in each row instead of swipe-to-delete to
/// reduce interaction steps. Confirming re-cleans the (possibly hand-edited)
/// text one more time before handing it back — matching RN's
/// `handleConfirmOcrDraft`, which re-runs `formatSetlistText` right before merging.
struct SetlistOcrReviewView: View {
  var onConfirm: ([String]) -> Void
  var onCancel: () -> Void

  @State private var items: [SetlistOcrCleanup.ReviewItem]
  @State private var showingEmptyAlert = false
  @Environment(\.dismiss) private var dismiss

  init(lines: [String], onConfirm: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    _items = State(initialValue: SetlistOcrCleanup.reviewItems(from: lines))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: 2) {
          Text("\(items.count)曲を認識しました")
            .font(.system(size: 14, weight: .semibold))
          Text("タップして編集できます")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)

        List {
          ForEach($items) { $item in
            row(for: $item)
          }
          .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
      }
      .navigationTitle("認識結果を確認")
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

  private func row(for item: Binding<SetlistOcrCleanup.ReviewItem>) -> some View {
    let isSuspicious = SetlistOcrCleanup.isSuspicious(item.wrappedValue.text)
    return HStack(spacing: 8) {
      TextField("曲名", text: item.text)
        .font(.system(size: 16))
        .foregroundStyle(isSuspicious ? Color.red : Color.primary)
      if isSuspicious {
        HugeIconView(icon: HugeIcons.alert01, size: 16)
          .foregroundStyle(.red)
      }
      Spacer(minLength: 4)
      Button(role: .destructive) {
        let id = item.wrappedValue.id
        items.removeAll { $0.id == id }
      } label: {
        HugeIconView(icon: HugeIcons.delete02, size: 16)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 6)
    .listRowBackground(isSuspicious ? Color.red.opacity(0.08) : Color.clear)
  }

  private func confirm() {
    let finalLines = SetlistOcrCleanup.cleanedLines(from: items.map(\.text).joined(separator: "\n"))
    guard !finalLines.isEmpty else {
      showingEmptyAlert = true
      return
    }
    onConfirm(finalLines)
    dismiss()
  }
}
