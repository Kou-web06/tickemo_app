import Foundation

/// 日本語の座席自由記述を `SeatInput` に分解する。完全一致は求めず、取れた項目だけ埋める。
enum SeatInputParser {
  static func parse(_ raw: String) -> SeatInput {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var input = SeatInput(raw: trimmed)
    guard !trimmed.isEmpty else { return input }

    let normalized = trimmed
      .replacingOccurrences(of: "　", with: " ")
      .replacingOccurrences(of: "１", with: "1")
      .replacingOccurrences(of: "２", with: "2")
      .replacingOccurrences(of: "３", with: "3")
      .replacingOccurrences(of: "４", with: "4")
      .replacingOccurrences(of: "５", with: "5")
      .replacingOccurrences(of: "６", with: "6")
      .replacingOccurrences(of: "７", with: "7")
      .replacingOccurrences(of: "８", with: "8")
      .replacingOccurrences(of: "９", with: "9")
      .replacingOccurrences(of: "０", with: "0")

    input.tierHint = detectTier(normalized)
    input.sideHint = detectSide(normalized)
    input.aisle = firstInt(in: normalized, suffixes: ["通路"])
    input.gate = firstInt(in: normalized, suffixes: ["ゲート", "Gate", "gate"])
    input.row = firstInt(in: normalized, suffixes: ["列"])
    input.number = firstInt(in: normalized, suffixes: ["番"])
    input.arenaBlockLabel = detectArenaBlockLabel(normalized)
    return input
  }

  private static func detectTier(_ text: String) -> SeatInput.TierHint? {
    if text.contains("アリーナ") || text.localizedCaseInsensitiveContains("arena") {
      return .arena
    }
    if text.contains("バルコニー") || text.localizedCaseInsensitiveContains("balcony") {
      return .balcony
    }
    if text.contains("2階") || text.contains("２階") {
      return .stand2
    }
    if text.contains("1階") || text.contains("１階") {
      return .stand1
    }
    return nil
  }

  private static func detectSide(_ text: String) -> SeatInput.SideHint? {
    if text.contains("1塁") || text.contains("一塁") {
      return .firstBase
    }
    if text.contains("3塁") || text.contains("三塁") {
      return .thirdBase
    }
    if text.contains("正面") || text.contains("バックネット") {
      return .home
    }
    if text.contains("中央") {
      return .center
    }
    return nil
  }

  private static func firstInt(in text: String, suffixes: [String]) -> Int? {
    for suffix in suffixes {
      let pattern = #"(\d+)\s*"# + NSRegularExpression.escapedPattern(for: suffix)
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      guard let match = regex.firstMatch(in: text, range: range),
            let numRange = Range(match.range(at: 1), in: text) else { continue }
      return Int(text[numRange])
    }
    return nil
  }

  private static func detectArenaBlockLabel(_ text: String) -> String? {
    let pattern = #"([A-Za-z]\d+)\s*ブロック"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let labelRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[labelRange]).uppercased()
  }
}
