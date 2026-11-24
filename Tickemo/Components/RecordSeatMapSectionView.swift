import SwiftUI

/// RecordDetail 用の東京ドーム座席図セクション。ロジックは `RecordSeatMapPresentation`。
struct RecordSeatMapSectionView: View {
  let layout: VenueLayout
  let model: RecordSeatMapPresentation.Model
  let primaryTextColor: Color
  let secondaryTextColor: Color

  @State private var highlightedBlockId: String?
  @State private var statusText: String

  @Environment(\.appFontChoice) private var appFont

  init(
    layout: VenueLayout,
    model: RecordSeatMapPresentation.Model,
    primaryTextColor: Color,
    secondaryTextColor: Color
  ) {
    self.layout = layout
    self.model = model
    self.primaryTextColor = primaryTextColor
    self.secondaryTextColor = secondaryTextColor
    _highlightedBlockId = State(initialValue: model.initialBlockId)
    _statusText = State(initialValue: model.statusText)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("#seat")
        .font(appFont.bold(18))
        .foregroundStyle(primaryTextColor)

      Text(model.seatRaw)
        .font(appFont.bold(16))
        .foregroundStyle(primaryTextColor)

      Text(statusText)
        .font(appFont.regular(13))
        .foregroundStyle(secondaryTextColor)
        .fixedSize(horizontal: false, vertical: true)

      TokyoDomeSeatMapView(layout: layout, highlightedBlockId: $highlightedBlockId)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    .onChange(of: highlightedBlockId) { oldValue, newValue in
      guard let newValue else { return }
      // 初回の推定ハイライト反映では「推定位置」文言を保つ
      if oldValue == nil, newValue == model.initialBlockId { return }
      statusText = RecordSeatMapPresentation.selectionStatusText(
        blockId: newValue,
        layout: layout
      )
    }
  }
}
