import Foundation

/// 日本語の座席自由記述を `SeatInput` に分解する。完全一致は求めず、取れた項目だけ埋める。
enum SeatInputParser {
  static func parse(_ raw: String) -> SeatInput {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var input = SeatInput(raw: trimmed)
    guard !trimmed.isEmpty else { return input }

    let normalized = normalize(trimmed)
    let labeled = extractLabeledInts(from: normalized)

    input.tierHint = detectTier(normalized)
    input.sideHint = detectSide(normalized)
    input.aisle = labeled[.aisle]
    input.gate = labeled[.gate]
    input.row = labeled[.row]
    input.number = labeled[.number]
    input.arenaBlockLabel = detectArenaBlockLabel(normalized)
    return input
  }

  /// NFKC・全角空白・区切り記号をならし、比較しやすい形にする。
  /// カタカナ長音「ー」は ゲート/アリーナ 等に必要なので区切りにしない。
  static func normalize(_ raw: String) -> String {
    var text = raw.precomposedStringWithCompatibilityMapping
    text = text.replacingOccurrences(of: "　", with: " ")
    // U+30FC 長音は除外。ハイフン類・中黒・スラッシュのみ空白化。
    for separator in ["-", "−", "–", "—", "‐", "・", "/", "／", "|", "｜", ",", "、"] {
      text = text.replacingOccurrences(of: separator, with: " ")
    }
    while text.contains("  ") {
      text = text.replacingOccurrences(of: "  ", with: " ")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private enum LabeledField: Hashable {
    case aisle, gate, row, number
  }

  /// `20通路` / `通路20` を一つの走査で左から非重複抽出する。
  private static func extractLabeledInts(from text: String) -> [LabeledField: Int] {
    let labelToField: [String: LabeledField] = [
      "通路": .aisle, "aisle": .aisle,
      "ゲート": .gate, "gate": .gate,
      "列": .row, "row": .row,
      "番": .number, "座席": .number, "seat": .number, "no": .number,
    ]
    let labelAlternation = labelToField.keys
      .sorted { $0.count > $1.count }
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")

    var result: [LabeledField: Int] = [:]

    func field(forLabel rawLabel: String) -> LabeledField? {
      labelToField[rawLabel] ?? labelToField[rawLabel.lowercased()]
    }

    // 数字→ラベルを先に試し、だめならラベル→数字。matches は重ならないよう進む。
    let pattern = #"(\d+)\s*("# + labelAlternation + #")|("# + labelAlternation + #")\s*(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return [:]
    }
    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, range: fullRange) {
      let value: Int?
      let label: String?
      if match.range(at: 1).location != NSNotFound {
        let numRange = Range(match.range(at: 1), in: text)
        let labelRange = Range(match.range(at: 2), in: text)
        value = numRange.flatMap { Int(text[$0]) }
        label = labelRange.map { String(text[$0]) }
      } else {
        let labelRange = Range(match.range(at: 3), in: text)
        let numRange = Range(match.range(at: 4), in: text)
        value = numRange.flatMap { Int(text[$0]) }
        label = labelRange.map { String(text[$0]) }
      }
      guard let value, let label, let field = field(forLabel: label) else { continue }
      if result[field] == nil {
        result[field] = value
      }
    }

    return result
  }

  private static func detectTier(_ text: String) -> SeatInput.TierHint? {
    let lower = text.lowercased()
    if text.contains("アリーナ") || lower.contains("arena") {
      return .arena
    }
    if text.contains("バルコニー") || lower.contains("balcony") {
      return .balcony
    }
    // 2階系を先に見る
    if text.contains("2階") || text.contains("二階")
      || lower.contains("2f") || lower.contains("stand2") || lower.contains("スタンド2") {
      return .stand2
    }
    if text.contains("1階") || text.contains("一階")
      || lower.contains("1f") || lower.contains("stand1") || lower.contains("スタンド1") {
      return .stand1
    }
    return nil
  }

  private static func detectSide(_ text: String) -> SeatInput.SideHint? {
    let lower = text.lowercased()
    if text.contains("1塁") || text.contains("一塁")
      || lower.contains("1b") || text.contains("ファースト") {
      return .firstBase
    }
    if text.contains("3塁") || text.contains("三塁")
      || lower.contains("3b") || text.contains("サード") {
      return .thirdBase
    }
    if text.contains("正面") || text.contains("バックネット") || text.contains("ホーム") {
      return .home
    }
    if text.contains("中央") || text.contains("センター") {
      return .center
    }
    return nil
  }

  private static func detectArenaBlockLabel(_ text: String) -> String? {
    let patterns = [
      #"([A-Za-z]\d+)\s*ブロック"#,
      #"ブロック\s*([A-Za-z]\d+)"#,
    ]
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        continue
      }
      guard let match = regex.firstMatch(in: text, range: range),
            let labelRange = Range(match.range(at: 1), in: text) else {
        continue
      }
      return String(text[labelRange]).uppercased()
    }
    return nil
  }
}
