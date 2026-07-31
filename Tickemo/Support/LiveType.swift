import Foundation

/// Ports the 6-key live-type taxonomy from `utils/liveType.ts`
/// (`LIVE_TYPE_KEYS`/`LIVE_TYPE_ICON_MAP`). `CD_ChekiRecord.liveType` stores
/// the raw key string; this enum is a display-layer convenience only.
enum LiveType: String, CaseIterable, Identifiable {
  case oneMan = "one-man"
  case twoMan = "two-man"
  case festival
  case fcOnly = "fc-only"
  case streaming
  case sports

  var id: String { rawValue }

  var label: String {
    switch self {
    case .oneMan: "One-man"
    case .twoMan: "Two-man"
    case .festival: "Festival"
    case .fcOnly: "FC Only"
    case .streaming: "Streaming"
    case .sports: "Sports"
    }
  }

  var hugeIcon: HugeIcon {
    switch self {
    case .oneMan: HugeIcons.user
    case .twoMan: HugeIcons.userMultiple02
    case .festival: HugeIcons.userGroup03
    case .fcOnly: HugeIcons.starCircle
    case .streaming: HugeIcons.radio
    case .sports: HugeIcons.football
    }
  }

  static func normalized(_ raw: String?) -> LiveType {
    guard let raw else { return .oneMan }
    return LiveType(rawValue: raw) ?? .oneMan
  }
}
