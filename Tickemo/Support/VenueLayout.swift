import Foundation

/// 会場レイアウトのルート。レンダラー非依存の幾何・階層データ。
///
/// 座標系（メートル / 度）:
/// - 原点 = フィールド中心
/// - 角度 0° = 外野中央（ステージ側）
/// - 反時計回り
/// - 本塁 ≈ 180°
struct VenueLayout: Codable, Equatable, Identifiable {
  let id: String
  let name: String
  let coordinateSystem: VenueCoordinateSystem
  let tiers: [VenueTier]

  struct VenueCoordinateSystem: Codable, Equatable {
    let origin: String
    let angleZero: String
    let angleDirection: String
    let homePlateApproxDegrees: Double
    let radiusUnit: String
    let notes: [String]
  }
}

/// 階・リング。`baseHeight` / `rake` は 3D 透視（`VenueSeatMap3DProjection`）で高さに使う。2D 描画では使わない。
struct VenueTier: Codable, Equatable, Identifiable {
  let id: String
  let name: String
  let baseHeight: Double
  let rake: Double
  let innerRadius: Double
  let outerRadius: Double
  let blocks: [VenueBlock]
}

/// ハイライト単位のブロック（通路 / 粗い帯 / 概位置）。
struct VenueBlock: Codable, Equatable, Identifiable {
  let id: String
  let name: String
  let aisle: Int?
  let side: String?
  /// 開始角（度）。外野中央 = 0、反時計回り。`endAngle` より大きい場合は
  /// 本塁側へ角度が減るリング帯（東京ドーム常設席の仮配分）を表す。
  let startAngle: Double
  let endAngle: Double
}

extension VenueLayout {
  /// バンドル内の仮 JSON を読む。テストからもアプリ本体バンドルを参照する。
  static func load(resource name: String, bundle: Bundle = .venueLayoutBundle) throws -> VenueLayout {
    guard let url = bundle.url(
      forResource: name,
      withExtension: "json",
      subdirectory: "VenueLayouts"
    ) ?? bundle.url(forResource: name, withExtension: "json") else {
      throw VenueLayoutError.resourceNotFound(name)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(VenueLayout.self, from: data)
  }

  static func tokyoDome(bundle: Bundle = .venueLayoutBundle) throws -> VenueLayout {
    try load(resource: "tokyo-dome", bundle: bundle)
  }

  func tier(id: String) -> VenueTier? {
    tiers.first { $0.id == id }
  }

  func block(id: String) -> (tier: VenueTier, block: VenueBlock)? {
    for tier in tiers {
      if let block = tier.blocks.first(where: { $0.id == id }) {
        return (tier, block)
      }
    }
    return nil
  }
}

enum VenueLayoutError: Error, Equatable {
  case resourceNotFound(String)
}

private final class VenueLayoutBundleToken {}

extension Bundle {
  /// Tickemo アプリターゲットのバンドル（ユニットテストの Bundle.main 差し替え対策）。
  static var venueLayoutBundle: Bundle {
    Bundle(for: VenueLayoutBundleToken.self)
  }
}
