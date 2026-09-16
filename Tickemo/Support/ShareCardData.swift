import Foundation
import CoreGraphics

/// Pure, unit-testable data-prep for the three shareable card designs
/// (Ticket/CD/Receipt), ported from components/ShareImageGenerator.tsx and
/// components/EditableTicketPreviewCard.tsx. No SwiftUI/UIKit dependency —
/// the card views (ShareTicketCardView/ShareCDCardView/ShareReceiptCardView)
/// consume this, and ShareCardDataTests exercises it directly.
enum ShareCardData {

  // MARK: - Shared

  /// "@" + trimmed username with any leading "@" stripped, defaulting to
  /// "@tickemo_user" when empty/nil — matches ShareImageGenerator.tsx's
  /// shareCreditHandle.
  static func shareCreditHandle(username: String?) -> String {
    guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return "@tickemo_user"
    }
    var handle = trimmed
    while handle.hasPrefix("@") {
      handle.removeFirst()
    }
    return "@\(handle)"
  }

  /// System-share caption text. Uses the singular `artist` field (not the
  /// joined multi-artist list shown on the card itself) — matches RN's
  /// handleSystemShare exactly, including the trailing " \n #Tickemo".
  static func systemShareCaptionText(date: String?, artist: String?, liveName: String?) -> String {
    "\(date ?? "") \(artist ?? "") - \(liveName ?? "") \n #Tickemo"
  }

  // MARK: - CD card

  /// Strips all non-digit characters from `raw`, then truncates to
  /// exactly `length` characters or right-pads with '0' if shorter.
  static func digitsPaddedOrTruncated(_ raw: String?, length: Int) -> String {
    let digitScalars = CharacterSet.decimalDigits
    let digits = (raw ?? "").unicodeScalars.filter { digitScalars.contains($0) }.map(String.init).joined()
    if digits.count >= length {
      return String(digits.prefix(length))
    }
    return digits + String(repeating: "0", count: length - digits.count)
  }

  /// "No. {8-digit date}-{4-digit time}-{2-digit song count}"
  static func cdBusinessCode(date: String?, startTime: String?, songCount: Int) -> String {
    let datePart = digitsPaddedOrTruncated(date, length: 8)
    let timePart = digitsPaddedOrTruncated(startTime, length: 4)
    let countPart = String(format: "%02d", songCount)
    return "No. \(datePart)-\(timePart)-\(countPart)"
  }

  /// Exact bar list transcribed from ShareImageGenerator.tsx's BARCODE_SVG
  /// (viewBox 315x101): each bar is a full-height vertical rectangle whose
  /// RIGHT edge sits at `rightEdgeX` in that 315-wide coordinate space
  /// (left edge = rightEdgeX - thickness). Purely decorative, encodes no
  /// real data — ShareBarcodeView scales this whole group to fit its
  /// target frame.
  static let cdBarcodeSourceSize = CGSize(width: 315, height: 101)
  static let cdBarcodeBars: [(thickness: CGFloat, rightEdgeX: CGFloat)] = [
    (13.2036, 39.6108), (13.2036, 92.4248), (1.88623, 20.7485), (1.88623, 56.5869),
    (1.88623, 64.1318), (1.88623, 135.808), (3.77246, 13.2036), (3.77246, 73.563),
    (3.77246, 145.239), (3.77246, 154.67), (3.77246, 115.06), (7.54491, 105.629),
    (7.54491, 128.263), (3.77246, 49.0415), (3.77246, 3.77246), (13.2036, 199.94),
    (13.2036, 252.754), (1.88623, 181.078), (1.88623, 216.916), (1.88623, 224.461),
    (1.88623, 296.138), (3.77246, 173.533), (3.77246, 233.892), (3.77246, 305.569),
    (3.77246, 315), (3.77246, 275.389), (7.54491, 265.958), (7.54491, 288.593),
    (3.77246, 209.371), (3.77246, 164.102),
  ]

  // MARK: - CD setlist columns

  enum SetlistLineKind: Equatable {
    case song(index: Int, name: String)
    case encoreSpacer
    case encoreLabel
  }

  struct SetlistLine: Equatable {
    let kind: SetlistLineKind
  }

  /// Builds the flat line sequence for the CD card's setlist columns:
  /// song lines get an incrementing 1-based index (encore doesn't
  /// increment it), encore items become a blank spacer line + "[ENCORE]"
  /// label line. No column-splitting/truncation here — the view splits
  /// into column 1 (first 28 lines) / column 2 (remainder), with no cap
  /// beyond that, matching RN.
  static func cdSetlistLines(items: [CD_SetlistItem]) -> [SetlistLine] {
    var lines: [SetlistLine] = []
    var songIndex = 0
    for item in items where item.kind == "song" || item.kind == "encore" {
      if item.kind == "encore" {
        lines.append(SetlistLine(kind: .encoreSpacer))
        lines.append(SetlistLine(kind: .encoreLabel))
      } else {
        songIndex += 1
        let name = item.songName?.trimmingCharacters(in: .whitespaces) ?? ""
        lines.append(SetlistLine(kind: .song(index: songIndex, name: name)))
      }
    }
    return lines
  }

  // MARK: - Receipt card

  /// その曲を「実際に歌った人」。優先順は 1) 対バン／フェスで設定された
  /// 出演者 (`performerName`)、2) 出演者が1組しかいない公演ではその1組
  /// （`SetlistPerformers.soleArtist` と同じ規則 — ワンマンのカバー曲を
  /// 原曲アーティスト名で出さないため）、3) 音源のアーティスト
  /// (`artistName`)。2) が無いと、`performerName` 未タグの旧データ
  /// （`SetlistDraftItem.normalizingPerformers` は保存時にしか効かない
  /// ので、一度も編集保存されていないレガシー移行データはこれに該当）を
  /// 一度も編集せずに共有した場合、ワンマンのカバー曲が原曲側の
  /// アーティスト名で出てしまう。`artistNames` は呼び出し側が渡す
  /// その公演の登録アーティスト一覧（未指定なら 2) は素通りする）。
  static func songPerformerName(_ item: CD_SetlistItem, artistNames: [String] = []) -> String? {
    SetlistPerformers.normalized(item.performerName)
      ?? SetlistPerformers.soleArtist(in: artistNames)
      ?? SetlistPerformers.normalized(item.artistName)
  }

  private static func distinctSongArtistNames(_ items: [CD_SetlistItem], artistNames: [String]) -> [String] {
    var seen = Set<String>()
    var order: [String] = []
    for item in items where item.kind == "song" {
      guard let name = songPerformerName(item, artistNames: artistNames) else { continue }
      if seen.insert(name).inserted {
        order.append(name)
      }
    }
    return order
  }

  static func hasMultipleDistinctSongArtists(setlistItems: [CD_SetlistItem], artistNames: [String] = []) -> Bool {
    distinctSongArtistNames(setlistItems, artistNames: artistNames).count > 1
  }

  /// Distinct (first-seen order) per-song performer names joined " / "
  /// (see `songPerformerName` — actual performer, cover-song aware),
  /// falling back to `fallbackArtist` when the setlist has no performer
  /// names at all. Callers pass the record's full artist list as both
  /// `fallbackArtist` (joined, many-artist show without a tagged setlist
  /// still lists everyone) and `artistNames` (the same list, unjoined —
  /// used for the sole-artist cover-song fallback above).
  static func receiptArtistLabel(setlistItems: [CD_SetlistItem], fallbackArtist: String?, artistNames: [String] = []) -> String {
    let names = distinctSongArtistNames(setlistItems, artistNames: artistNames)
    if !names.isEmpty {
      return names.joined(separator: " / ")
    }
    return (fallbackArtist?.isEmpty == false) ? fallbackArtist! : "-"
  }

  private static let encoreMarkerStripSet = CharacterSet(charactersIn: " \t\n\u{3000}-－—–―ー_＊*[]【】()（）")

  private static func normalizedForEncoreComparison(_ raw: String) -> String {
    raw.lowercased().unicodeScalars.filter { !encoreMarkerStripSet.contains($0) }.map(String.init).joined()
  }

  private static let encoreMarkerTargets: Set<String> = Set(["encore", "アンコール"].map(normalizedForEncoreComparison))

  static func isEncoreMarkerText(_ raw: String?) -> Bool {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    return encoreMarkerTargets.contains(normalizedForEncoreComparison(raw))
  }

  enum ReceiptRow {
    case song(quantityLabel: String, name: String, amount: String)
    case encoreMarker
    case ellipsis
  }

  static let receiptDashedDivider = String(repeating: "-", count: 60)
  static let receiptEncoreMarkerLine = "----------- ENCORE -----------"

  /// Full row-building + compression pipeline. `setlistItems` is expected
  /// already orderIndex-sorted (record.sortedSetlistItems).
  ///
  /// 1. Map each item to a song entry (1-based running index, only for
  ///    genuine songs) or an encore-marker entry: "encore"-kind items
  ///    always mark; "mc"-kind items mark only if isEncoreMarkerText(title);
  ///    "song"-kind items with an encore-marker-looking name also mark
  ///    (and don't consume a song index); everything else is skipped.
  ///    A song's display name gets " - {performer}" appended when the
  ///    setlist has multiple distinct performers (the actual performer
  ///    per `songPerformerName`, not the source `artistName` — so a cover
  ///    is credited to whoever played it, not the original artist).
  /// 2. If total song count <= 20: return every entry as a row, no ellipsis.
  /// 3. If total song count > 20: walk forward keeping entries until 10
  ///    songs have been consumed (stopping BEFORE any entry once 10 is
  ///    reached, so a marker immediately after the 10th song is dropped,
  ///    not kept), walk backward the same way for the trailing 10 songs,
  ///    and join head + [.ellipsis] + tail.
  static func receiptRows(setlistItems: [CD_SetlistItem], artistNames: [String] = []) -> [ReceiptRow] {
    enum Entry { case song(number: Int, name: String), encore }

    let multiArtist = hasMultipleDistinctSongArtists(setlistItems: setlistItems, artistNames: artistNames)
    var entries: [Entry] = []
    var songNumber = 0

    for item in setlistItems {
      switch item.kind {
      case "encore":
        entries.append(.encore)
      case "mc":
        if isEncoreMarkerText(item.title) {
          entries.append(.encore)
        }
      case "song":
        guard let rawName = item.songName?.trimmingCharacters(in: .whitespaces), !rawName.isEmpty else { continue }
        if isEncoreMarkerText(rawName) {
          entries.append(.encore)
        } else {
          songNumber += 1
          let artistSuffix = songPerformerName(item, artistNames: artistNames)
          let displayName = (multiArtist && artistSuffix?.isEmpty == false) ? "\(rawName) - \(artistSuffix!)" : rawName
          entries.append(.song(number: songNumber, name: displayName))
        }
      default:
        continue
      }
    }

    func toRow(_ entry: Entry) -> ReceiptRow {
      switch entry {
      case .encore:
        return .encoreMarker
      case .song(let number, let name):
        return .song(quantityLabel: String(format: "%02d", number), name: name, amount: "1.00")
      }
    }

    guard songNumber > 20 else {
      return entries.map(toRow)
    }

    var head: [Entry] = []
    var headSongs = 0
    for entry in entries {
      if headSongs >= 10 { break }
      head.append(entry)
      if case .song = entry { headSongs += 1 }
    }

    var tail: [Entry] = []
    var tailSongs = 0
    for entry in entries.reversed() {
      if tailSongs >= 10 { break }
      tail.insert(entry, at: 0)
      if case .song = entry { tailSongs += 1 }
    }

    return head.map(toRow) + [.ellipsis] + tail.map(toRow)
  }
}
