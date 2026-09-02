import SwiftUI

/// Shared "── ENCORE ──" / "── MC ──"-style divider row, used both by
/// SetlistEditorView's encore rows and RecordDetailView's read-only
/// encore/mc display — ports components/SetlistEditor.tsx's `encoreCard`
/// styling (dashed lines flanking centered bold letter-spaced text).
struct SetlistMarkerDivider: View {
  let text: String

  private var dashedLine: some View {
    Rectangle()
      .fill(Color.clear)
      .frame(height: 1)
      .overlay(
        Rectangle()
          .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          .foregroundStyle(Color(white: 0.82))
      )
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    HStack(spacing: 12) {
      dashedLine
      Text(text.isEmpty ? "MC" : text)
        .font(appFont.bold(14))
        .tracking(1.2)
        .foregroundStyle(Color(white: 0.4))
        .fixedSize()
      dashedLine
    }
    .padding(.vertical, 6)
  }
}
