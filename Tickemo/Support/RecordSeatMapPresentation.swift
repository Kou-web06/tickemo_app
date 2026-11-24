import Foundation

/// RecordDetail の座席図セクション用の表示モデル。View はこれを消費するだけ。
enum RecordSeatMapPresentation {
  struct Model: Equatable {
    let seatRaw: String
    let resolution: SeatResolution
    /// 初回表示のステータス文言（日本語）。
    let statusText: String
    /// パース成功時の初期ハイライト。失敗時は nil（タップ選択可）。
    let initialBlockId: String?
    /// needsPicker / unsupported 相当で、ユーザーにタップ選択を促すか。
    let encouragesPicker: Bool
  }

  /// 東京ドーム系会場かつ座席文字列があるときだけモデルを返す。
  static func make(
    venue: String?,
    seat: String?,
    layout: VenueLayout
  ) -> Model? {
    guard TokyoDomeVenueMatching.matches(venue) else { return nil }
    guard layout.id == "tokyo-dome" else { return nil }

    let trimmedSeat = seat?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedSeat.isEmpty else { return nil }

    let resolution = SeatResolver.resolve(rawSeat: trimmedSeat, layout: layout)
    switch resolution {
    case .resolved(let resolved):
      let name = blockDisplayName(blockId: resolved.blockId, layout: layout)
      return Model(
        seatRaw: trimmedSeat,
        resolution: resolution,
        statusText: "推定位置: \(name)",
        initialBlockId: resolved.blockId,
        encouragesPicker: false
      )
    case .approximate(let resolved):
      let name = blockDisplayName(blockId: resolved.blockId, layout: layout)
      let fine = resolved.input.arenaBlockLabel.map { "（\($0)は公演別細ブロック）" } ?? ""
      return Model(
        seatRaw: trimmedSeat,
        resolution: resolution,
        statusText: "常設図では細かく表せないため、概位置を表示: \(name)\(fine)",
        initialBlockId: resolved.blockId,
        encouragesPicker: false
      )
    case .needsPicker:
      return Model(
        seatRaw: trimmedSeat,
        resolution: resolution,
        statusText: "座席を特定できませんでした。図のブロックをタップして選択できます。",
        initialBlockId: nil,
        encouragesPicker: true
      )
    case .unsupported:
      return Model(
        seatRaw: trimmedSeat,
        resolution: resolution,
        statusText: "この座席表記は常設図では表せません。概位置をタップして確認できます。",
        initialBlockId: nil,
        encouragesPicker: true
      )
    }
  }

  /// ユーザーがブロックをタップしたあとのステータス文言。
  static func selectionStatusText(blockId: String, layout: VenueLayout) -> String {
    "選択: \(blockDisplayName(blockId: blockId, layout: layout))"
  }

  static func blockDisplayName(blockId: String, layout: VenueLayout) -> String {
    layout.block(id: blockId)?.block.name ?? blockId
  }
}
