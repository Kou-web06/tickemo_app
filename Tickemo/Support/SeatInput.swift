import Foundation

/// `CD_ChekiRecord.seat` など自由記述の座席文字列を構造化した結果。
/// 未検出の項目は nil。レンダラー非依存。
struct SeatInput: Equatable {
  enum TierHint: String, Equatable {
    case stand1
    case stand2
    case balcony
    case arena
  }

  enum SideHint: String, Equatable {
    case firstBase
    case thirdBase
    case home
    case center
  }

  var raw: String
  var tierHint: TierHint?
  var sideHint: SideHint?
  var aisle: Int?
  var gate: Int?
  var row: Int?
  var number: Int?
  /// アリーナの「B3」など細ブロック表記。常設図には無い。
  var arenaBlockLabel: String?
}

/// 座席文字列 → レイアウト上の位置。ブロック ID まで（列・番の 3D 座標は将来）。
enum SeatResolution: Equatable {
  case resolved(ResolvedSeat)
  /// 階+通路が取れない、または曖昧でユーザーに選ばせる必要がある。
  case needsPicker
  /// 現行レイアウトで表現できない（例: 公演別アリーナ細ブロック）。
  case unsupported

  /// ブロックまで解決した座席。後で `position3D` を足せるよう分離してある。
  struct ResolvedSeat: Equatable {
    let layoutId: String
    let tierId: String
    let blockId: String
    let input: SeatInput
    /// 将来の 3D 配置用。v1 では常に nil。
    var position3D: SeatPosition3D? = nil
  }
}

/// メートル座標系の 3D 位置プレースホルダ（未使用）。
struct SeatPosition3D: Equatable {
  var x: Double
  var y: Double
  var z: Double
}
