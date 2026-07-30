import Foundation

/// Shared "which artist name(s) does this record belong to" logic, used by
/// both the artist grid builder (RecordListView) and ArtistDetailView's
/// filter, so the "prefer the multi-artist array, trim, drop empties" rule
/// isn't duplicated. Matches the case-insensitive convention already used
/// by ArtistDisplay/DataMigrationImporter elsewhere in this codebase — not
/// the RN Statistics screen's case-sensitive grouping, which the migration
/// research concluded looks like an RN-side inconsistency, not a deliberate
/// design choice worth replicating.
enum ArtistGrouping {
  /// One (name, officialImageUrl) pair per non-empty artist on `record`,
  /// index-aligned with `artistsArray`/`artist` the same way RN's
  /// `getRecordArtistEntries` aligns `artists[]` with `artistImageUrls[]` —
  /// `artistImageUrls[index]`, falling back to the single `artistImageUrl`
  /// only for index 0 (the single-artist-field case).
  static func entries(for record: CD_ChekiRecord) -> [(name: String, imageUrl: String?)] {
    let rawNames = (record.artistsArray?.isEmpty == false) ? record.artistsArray! : [record.artist ?? ""]
    // artistImageUrls is stored as NSArray (via StringArrayTransformer); mirror
    // artistsArray's two-step cast to handle both the native-Swift and
    // NSSecureUnarchiveFromData runtime representations.
    let urls = (record.artistImageUrls as? [String])
      ?? record.artistImageUrls?.compactMap { $0 as? String }
      ?? []
    return rawNames.enumerated().compactMap { index, rawName in
      let name = rawName.trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty else { return nil }
      let rawUrl = index < urls.count ? urls[index] : (index == 0 ? record.artistImageUrl : nil)
      let trimmedUrl = rawUrl?.trimmingCharacters(in: .whitespaces)
      guard let trimmedUrl, !trimmedUrl.isEmpty else { return (name, nil) }
      // RN stored MusicKit artwork as template URLs (e.g. …/{w}x{h}bb.jpg).
      // Resolve them so AsyncImage can load them; the native app always writes
      // resolved URLs, so non-template URLs pass through unchanged.
      return (name, resolveArtworkTemplate(trimmedUrl))
    }
  }

  /// Replaces MusicKit JS template placeholders `{w}` / `{h}` with a
  /// concrete resolution. Returns the URL unchanged if it contains neither.
  private static func resolveArtworkTemplate(_ url: String, size: Int = 800) -> String {
    guard url.contains("{w}") || url.contains("{h}") else { return url }
    return url
      .replacingOccurrences(of: "{w}", with: "\(size)")
      .replacingOccurrences(of: "{h}", with: "\(size)")
  }

  static func names(for record: CD_ChekiRecord) -> [String] {
    entries(for: record).map(\.name)
  }

  static func matches(_ record: CD_ChekiRecord, artistName: String) -> Bool {
    let target = artistName.lowercased()
    return names(for: record).contains { $0.lowercased() == target }
  }

  struct Tile: Identifiable {
    let id: String // lowercased grouping key
    let name: String // first-seen display casing
    let showCount: Int
    let latestPastDateText: String // "-" if no past show
    let coverImageData: Data?
    let artistImageUrl: String?
  }

  /// Groups `records` by artist name (case-insensitive/trimmed), sorted by
  /// show count descending, tie-broken by name ascending for a
  /// deterministic order (RN only sorts by count, leaving ties unspecified).
  static func tiles(from records: [CD_ChekiRecord]) -> [Tile] {
    var order: [String] = []
    var buckets: [String: (name: String, records: [CD_ChekiRecord], imageUrl: String?)] = [:]

    for record in records {
      for entry in entries(for: record) {
        let key = entry.name.lowercased()
        if buckets[key] == nil {
          buckets[key] = (entry.name, [], nil)
          order.append(key)
        }
        buckets[key]!.records.append(record)
        if buckets[key]!.imageUrl == nil, let url = entry.imageUrl {
          buckets[key]!.imageUrl = url
        }
      }
    }

    return order
      .map { key -> Tile in
        let bucket = buckets[key]!
        return Tile(
          id: key,
          name: bucket.name,
          showCount: bucket.records.count,
          latestPastDateText: latestPastDate(in: bucket.records),
          coverImageData: bucket.records.first(where: { $0.coverImageData != nil })?.coverImageData,
          artistImageUrl: bucket.imageUrl
        )
      }
      .sorted {
        $0.showCount == $1.showCount ? $0.name < $1.name : $0.showCount > $1.showCount
      }
  }

  static func latestPastDate(in records: [CD_ChekiRecord]) -> String {
    let today = utcCalendar.startOfDay(for: Date())
    let past = records.compactMap { record -> (String, Date)? in
      guard let dateString = record.date, let date = DateFormatting.date(from: dateString), date < today else {
        return nil
      }
      return (dateString, date)
    }
    return past.max { $0.1 < $1.1 }?.0 ?? "-"
  }

  static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = DateFormatting.timeZone
    return calendar
  }
}

/// Navigation value for pushing into ArtistDetailView from a grid tile — a
/// dedicated Hashable wrapper rather than a raw String, so it can't collide
/// with any other String-valued navigationDestination in the same stack.
struct ArtistRoute: Hashable {
  let name: String
}
