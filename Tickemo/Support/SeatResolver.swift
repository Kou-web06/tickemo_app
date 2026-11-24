import Foundation

/// `SeatInput` と `VenueLayout` を突き合わせ、ブロック ID まで解決する。
enum SeatResolver {
  static func resolve(rawSeat: String, layout: VenueLayout) -> SeatResolution {
    resolve(input: SeatInputParser.parse(rawSeat), layout: layout)
  }

  static func resolve(input: SeatInput, layout: VenueLayout) -> SeatResolution {
    let trimmed = input.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .needsPicker }

    // アリーナの細ブロック（B3 など）は常設図に無い
    if input.tierHint == .arena, input.arenaBlockLabel != nil {
      return .unsupported
    }
    if input.tierHint == .arena {
      guard let tier = layout.tier(id: "arena"),
            let block = tier.blocks.first else {
        return .needsPicker
      }
      return .resolved(.init(
        layoutId: layout.id,
        tierId: tier.id,
        blockId: block.id,
        input: input
      ))
    }

    guard let tierHint = input.tierHint else {
      return .needsPicker
    }

    let tierId: String
    switch tierHint {
    case .stand1: tierId = "stand1"
    case .stand2: tierId = "stand2"
    case .balcony: tierId = "balcony"
    case .arena: tierId = "arena"
    }

    guard let tier = layout.tier(id: tierId) else {
      return .needsPicker
    }

    if let aisle = input.aisle,
       let block = tier.blocks.first(where: { $0.aisle == aisle }) {
      return .resolved(.init(
        layoutId: layout.id,
        tierId: tier.id,
        blockId: block.id,
        input: input
      ))
    }

    // バルコニーは通路番号が無いので側ヒントだけで粗い帯へ
    if tierHint == .balcony, let side = input.sideHint {
      if let block = balconyBlock(in: tier, side: side) {
        return .resolved(.init(
          layoutId: layout.id,
          tierId: tier.id,
          blockId: block.id,
          input: input
        ))
      }
    }

    return .needsPicker
  }

  private static func balconyBlock(in tier: VenueTier, side: SeatInput.SideHint) -> VenueBlock? {
    switch side {
    case .firstBase:
      return tier.blocks.first { $0.id == "balcony-1b" }
    case .thirdBase:
      return tier.blocks.first { $0.id == "balcony-3b" }
    case .home, .center:
      return tier.blocks.first { $0.id == "balcony-home-1b" }
    }
  }
}
