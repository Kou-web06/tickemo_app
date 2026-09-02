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

/// 出演者が切り替わる位置に挟む見出し行。対バン／フェスで A→B→A と
/// 交互に演奏したことを一目で分かるようにするためのもので、通し番号
/// （01, 02, …）は跨いで連続したままにする — 番号は「その日の何曲目か」
/// であって、バンドごとの曲順ではないため。
///
/// MC / アンコールの `SetlistMarkerDivider`（中央寄せ・破線で挟む）とは
/// 意図的に別の見た目にしてある。あちらは進行の区切り、こちらは演者の
/// 切り替わりという別レイヤーの情報なので、同じ体裁だと混同される。
struct SetlistPerformerHeader: View {
  let name: String

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    HStack(spacing: 10) {
      Text(name)
        .font(appFont.bold(13))
        .tracking(0.6)
        .foregroundStyle(Color(white: 0.22))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.8)))
        .overlay(Capsule().stroke(Color(white: 0.78), lineWidth: 1))

      Rectangle()
        .fill(Color(white: 0.78))
        .frame(height: 1)
    }
    .padding(.top, 4)
    .padding(.bottom, 2)
  }
}
