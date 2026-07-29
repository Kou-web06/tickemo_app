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
  static func names(for record: CD_ChekiRecord) -> [String] {
    let raw = (record.artistsArray?.isEmpty == false) ? record.artistsArray! : [record.artist ?? ""]
    return raw
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
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
  }

  /// Groups `records` by artist name (case-insensitive/trimmed), sorted by
  /// show count descending, tie-broken by name ascending for a
  /// deterministic order (RN only sorts by count, leaving ties unspecified).
  static func tiles(from records: [CD_ChekiRecord]) -> [Tile] {
    var order: [String] = []
    var buckets: [String: (name: String, records: [CD_ChekiRecord])] = [:]

    for record in records {
      for name in names(for: record) {
        let key = name.lowercased()
        if buckets[key] == nil {
          buckets[key] = (name, [])
          order.append(key)
        }
        buckets[key]!.records.append(record)
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
          coverImageData: bucket.records.first(where: { $0.coverImageData != nil })?.coverImageData
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
