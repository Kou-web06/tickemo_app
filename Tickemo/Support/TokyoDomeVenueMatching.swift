import Foundation

/// 会場名が東京ドーム（常設席図の対象）かどうかを判定する。
/// 「東京ドームシティホール」など別施設は除外する。
enum TokyoDomeVenueMatching {
  static func matches(_ venue: String?) -> Bool {
    guard let venue else { return false }
    let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let compact = trimmed
      .replacingOccurrences(of: "　", with: "")
      .replacingOccurrences(of: " ", with: "")
      .lowercased()

    // 別館・周辺施設は対象外
    if compact.contains("東京ドームシティ") { return false }
    if compact.contains("tokyodomecity") { return false }
    if compact.contains("東京ドームホテル") { return false }
    if compact.contains("tokyodomehotel") { return false }

    if compact.contains("東京ドーム") { return true }
    if compact.contains("tokyodome") { return true }
    return false
  }
}
