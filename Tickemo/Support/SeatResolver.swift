import Foundation

/// `SeatInput` と `VenueLayout` を突き合わせ、ブロック ID まで解決する。
enum SeatResolver {
  static func resolve(rawSeat: String, layout: VenueLayout) -> SeatResolution {
    resolve(input: SeatInputParser.parse(rawSeat), layout: layout)
  }

  static func resolve(input: SeatInput, layout: VenueLayout) -> SeatResolution {
    let trimmed = input.raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .needsPicker }

    if input.tierHint == .arena {
      return resolveArena(input: input, layout: layout)
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

    // 通路番号は側ヒントより優先（チケットの通路が位置の本情報）
    if let aisle = input.aisle,
       let block = tier.blocks.first(where: { $0.aisle == aisle }) {
      return .resolved(.init(
        layoutId: layout.id,
        tierId: tier.id,
        blockId: block.id,
        input: input
      ))
    }

    // 通路が無いときは側ヒントで粗い帯へ（バルコニー / スタンド）
    if let side = input.sideHint,
       let block = coarseBlock(in: tier, side: side, tierHint: tierHint) {
      return .resolved(.init(
        layoutId: layout.id,
        tierId: tier.id,
        blockId: block.id,
        input: input
      ))
    }

    return .needsPicker
  }

  /// 常設図はアリーナ概位置 1 領域のみ。細ブロック表記は概位置へフォールバック。
  private static func resolveArena(
    input: SeatInput,
    layout: VenueLayout
  ) -> SeatResolution {
    guard let overview = arenaOverview(in: layout) else {
      return .needsPicker
    }
    let seat = SeatResolution.ResolvedSeat(
      layoutId: layout.id,
      tierId: overview.tier.id,
      blockId: overview.block.id,
      input: input
    )
    if input.arenaBlockLabel != nil {
      return .approximate(seat)
    }
    return .resolved(seat)
  }

  static func arenaOverview(in layout: VenueLayout) -> (tier: VenueTier, block: VenueBlock)? {
    guard let tier = layout.tier(id: "arena"),
          let block = tier.blocks.first else {
      return nil
    }
    return (tier, block)
  }

  private static func coarseBlock(
    in tier: VenueTier,
    side: SeatInput.SideHint,
    tierHint: SeatInput.TierHint
  ) -> VenueBlock? {
    if tierHint == .balcony {
      return balconyBlock(in: tier, side: side)
    }

    let matched = blocksMatchingSide(in: tier, side: side)
    guard !matched.isEmpty else { return nil }
    // 側の中央付近を代表ブロックにする
    return matched[matched.count / 2]
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

  private static func blocksMatchingSide(
    in tier: VenueTier,
    side: SeatInput.SideHint
  ) -> [VenueBlock] {
    let needles: [String]
    switch side {
    case .firstBase:
      needles = ["1塁"]
    case .thirdBase:
      needles = ["3塁"]
    case .home:
      needles = ["正面"]
    case .center:
      needles = ["中央", "正面"]
    }
    return tier.blocks.filter { block in
      guard let blockSide = block.side else { return false }
      return needles.contains { blockSide.contains($0) }
    }
  }
}
