import Foundation

/// Ports LiveEditScreen.tsx's OCR line-cleanup pipeline exactly:
/// `formatSetlistText` (strip numbering/whitespace, drop MC/SE/ENCORE/
/// encore-marker lines) followed by `normalizeAndFilterOcrLines` (strip
/// bullet/marker prefixes, drop header/time/divider lines, case-insensitive
/// dedupe) — plus `isSuspiciousSetlistText`'s heuristic for flagging (not
/// dropping) lines the OCR likely mangled. Regex patterns and thresholds
/// are copied 1:1 from the RN source. The Japanese-script characters below
/// are built once as real Unicode characters (via Swift's own `\u{}`
/// escape) and interpolated as literal characters into the regex pattern
/// strings, rather than relying on ICU's own (different) `\uXXXX` escape
/// syntax — keeps this file's source text plain-ASCII without any
/// escape-syntax ambiguity.
enum SetlistOcrCleanup {
  struct ReviewItem: Identifiable {
    let id = UUID()
    var text: String
    var isSuspicious: Bool
  }

  private static let fullWidthSpace = "\u{3000}"           //
  private static let circledNumeralStart = "\u{2460}"      // ①
  private static let circledNumeralEnd = "\u{2473}"        // ⑳
  private static let fullWidthPeriod = "\u{FF0E}"          // ．
  private static let fullWidthColon = "\u{FF1A}"           // ：
  private static let fullWidthComma = "\u{3001}"           // 、
  private static let fullWidthCloseBracket = "\u{3011}"    // 】
  private static let katakanaMiddleDot = "\u{30FB}"        // ・
  private static let blackCircle = "\u{25CF}"               // ●
  private static let hiraganaKatakanaStart = "\u{3040}"
  private static let hiraganaKatakanaEnd = "\u{30FF}"
  private static let kanjiStart = "\u{4E00}"
  private static let kanjiEnd = "\u{9FFF}"
  private static let encoreWordJa = "\u{30A2}\u{30F3}\u{30B3}\u{30FC}\u{30EB}"           // アンコール
  private static let setlistWordJa = "\u{30BB}\u{30C3}\u{30C8}\u{30EA}\u{30B9}\u{30C8}"  // セットリスト

  // "MC" / "SE" / "ENCORE" / the Japanese "encore" word — RN drops any line
  // containing one of these as a substring.
  private static let blacklistWords = ["MC", "SE", "ENCORE", encoreWordJa]

  private static var dropLinePatterns: [(pattern: String, caseInsensitive: Bool)] {
    [
      ("^(set\\s*list|setlist|\(setlistWordJa))\\s*[:\(fullWidthColon)-]?\\s*$", true),
      ("^(date|open|start|door|time|venue|place|ticket|price)\\s*[:\(fullWidthColon)].*$", true),
      (#"^\d{1,2}:\d{2}(\s*[-~]\s*\d{1,2}:\d{2})?$"#, false),
      (#"^[-=_.~]{3,}$"#, false),
    ]
  }

  // MARK: - Regex helpers

  private static func regexReplace(_ pattern: String, in string: String, caseInsensitive: Bool = false) -> String {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return string }
    let range = NSRange(string.startIndex..., in: string)
    return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
  }

  private static func regexMatches(_ pattern: String, in string: String, caseInsensitive: Bool = false) -> Bool {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
    let range = NSRange(string.startIndex..., in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
  }

  private static func regexMatchCount(_ pattern: String, in string: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(string.startIndex..., in: string)
    return regex.numberOfMatches(in: string, options: [], range: range)
  }

  // MARK: - Layer 1: formatSetlistText

  static func formatSetlistLines(_ input: String) -> [String] {
    let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
    let rawLines = normalized.components(separatedBy: "\n")
    let trimPattern = "^[\\s\(fullWidthSpace)]+|[\\s\(fullWidthSpace)]+$"
    let enPrefixCharClass = "[\\s.\(fullWidthPeriod)\\-_:\(fullWidthColon),\(fullWidthComma))]"

    return rawLines
      .map { regexReplace(trimPattern, in: $0) }
      .map { regexReplace("^\\d+\\s*[.\(fullWidthPeriod)]\\s*", in: $0) }
      .map { regexReplace("^\\d+\\s*[,、\(fullWidthComma)]\\s*", in: $0) }
      .map { regexReplace("^\\d+[\(fullWidthSpace)]+", in: $0) }
      .map { regexReplace(#"^\d+\s+"#, in: $0) }
      .map { regexReplace("^en\(enPrefixCharClass)*\\d*\(enPrefixCharClass)*", in: $0, caseInsensitive: true) }
      .map { regexReplace(trimPattern, in: $0) }
      .filter { line in
        let lower = line.lowercased()
        return !blacklistWords.contains { lower.contains($0.lowercased()) }
      }
      .filter { !$0.isEmpty }
  }

  // MARK: - Layer 2: normalizeAndFilterOcrLines / normalizeOcrLine

  private static func normalizeOcrLine(_ line: String) -> String {
    var next = line.trimmingCharacters(in: .whitespacesAndNewlines)
    // Circled numerals U+2460 ("①") through U+2473 ("⑳").
    next = regexReplace("^\\s*[\(circledNumeralStart)-\(circledNumeralEnd)]\\s*", in: next)
    // "No.1" / "No 1" / "NO.1" etc.
    next = regexReplace("^\\s*[Nn][Oo]\\.?\\s*\\d*\\s*[.:\\-]?\\s*", in: next)
    next = regexReplace(
      "^\\s*(?:m|mc)?\\s*0*\\d{1,3}\\s*[.)\\]\(fullWidthCloseBracket)\\-:\(fullWidthColon)]\\s*",
      in: next, caseInsensitive: true
    )
    next = regexReplace(#"^\s*#?\d{1,3}\s+(?=\S)"#, in: next)
    // Bullet markers: "-", "*", katakana middle dot, black circle.
    next = regexReplace("^\\s*[-*\(katakanaMiddleDot)\(blackCircle)]\\s*", in: next)
    return next.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Full pipeline: raw OCR text in, cleaned/deduped song-title lines out.
  static func cleanedLines(from rawText: String) -> [String] {
    let formatted = formatSetlistLines(rawText)
    var seen = Set<String>()
    var cleaned: [String] = []

    for raw in formatted {
      let normalized = normalizeOcrLine(raw)
      guard !normalized.isEmpty else { continue }
      if dropLinePatterns.contains(where: { regexMatches($0.pattern, in: normalized, caseInsensitive: $0.caseInsensitive) }) {
        continue
      }
      let key = normalized.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      cleaned.append(normalized)
    }
    return cleaned
  }

  // MARK: - Suspicious-line flagging

  static func isSuspicious(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    if trimmed.count < 2 { return true }

    let kanaKanjiRange = "\(hiraganaKatakanaStart)-\(hiraganaKatakanaEnd)\(kanjiStart)-\(kanjiEnd)"
    let hasReadableChars = regexMatches("[A-Za-z\(kanaKanjiRange)]", in: trimmed)
    let symbolChars = regexMatchCount("[^A-Za-z0-9\(kanaKanjiRange)\\s]", in: trimmed)
    let symbolRatio = Double(symbolChars) / Double(max(trimmed.count, 1))
    let repeatedCharOnly = regexMatches("^([\\W_\(fullWidthSpace)\\s]|\\d)\\1+$", in: trimmed)
    let looksLikeMetaLine = regexMatches(#"^(open|start|door|time|venue|ticket|price|date)\b"#, in: trimmed, caseInsensitive: true)

    if !hasReadableChars { return true }
    if symbolRatio > 0.35 { return true }
    if repeatedCharOnly { return true }
    if looksLikeMetaLine { return true }
    return false
  }

  static func reviewItems(from lines: [String]) -> [ReviewItem] {
    lines.map { ReviewItem(text: $0, isSuspicious: isSuspicious($0)) }
  }
}
