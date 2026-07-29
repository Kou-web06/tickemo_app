import Foundation

struct StatisticsSummary {
  let totalLives: Int
  let totalArtists: Int
  let totalVenues: Int
}

struct RankedArtist: Identifiable {
  let id: String
  let rank: Int
  let name: String
  let count: Int
  let coverImageData: Data?
}

struct ArtistArchiveEntry: Identifiable {
  let id: String
  let name: String
  let lastLiveDateText: String
  let coverImageData: Data?
}

struct MonthlyBucket: Identifiable {
  let id: Int
  let label: String
  let count: Int
}

struct RankedVenue: Identifiable {
  let id: String
  let rank: Int
  let name: String
  let count: Int
}

struct RankedSong: Identifiable {
  let id: String
  let rank: Int
  let name: String
  let count: Int
  let artworkUrl: String?
}

/// Ports the section-by-section grouping/sorting logic of
/// screens/StatisticsScreen.tsx as pure functions over `[CD_ChekiRecord]`, so
/// it can be unit tested without SwiftUI or a live Core Data fetch. Deviates
/// deliberately from the RN source in one place: artist grouping is
/// case-insensitive everywhere (via ArtistGrouping), matching the convention
/// already established for the rest of this app, rather than RN's
/// case-sensitive Statistics-screen grouping (confirmed to be an RN-side
/// inconsistency, not a deliberate design choice, during migration research).
enum StatisticsData {
  private static let monthAbbreviations = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  // MARK: - Filter pipeline

  /// Combines `record.date` (yyyy-MM-dd) with `record.startTime` (HH:mm, UTC)
  /// into a single instant, defaulting to midnight when startTime is absent
  /// or unparseable — mirrors RN's `parseRecordDateTime(date, startTime)`.
  static func recordInstant(_ record: CD_ChekiRecord) -> Date? {
    guard let day = DateFormatting.date(from: record.date) else { return nil }
    guard let startTime = record.startTime, !startTime.isEmpty else { return day }
    let parts = startTime.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return day }
    return DateFormatting.utcCalendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
  }

  static func attendedRecords(_ records: [CD_ChekiRecord], now: Date) -> [CD_ChekiRecord] {
    records.filter { record in
      guard let instant = recordInstant(record) else { return false }
      return instant <= now
    }
  }

  static func availableYears(_ attended: [CD_ChekiRecord]) -> [Int] {
    let years = attended.compactMap { record -> Int? in
      guard let date = DateFormatting.date(from: record.date) else { return nil }
      return DateFormatting.utcCalendar.component(.year, from: date)
    }
    return Array(Set(years)).sorted(by: >)
  }

  static func yearFiltered(_ attended: [CD_ChekiRecord], year: Int?) -> [CD_ChekiRecord] {
    guard let year else { return attended }
    return attended.filter { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return DateFormatting.utcCalendar.component(.year, from: date) == year
    }
  }

  // MARK: - Stats strip

  static func summary(_ records: [CD_ChekiRecord]) -> StatisticsSummary {
    let artistKeys = Set(records.flatMap(ArtistGrouping.names(for:)).map { $0.lowercased() })
    let venues = Set(records.compactMap(\.venue))
    return StatisticsSummary(totalLives: records.count, totalArtists: artistKeys.count, totalVenues: venues.count)
  }

  // MARK: - Shared rank helper

  /// Ties share a rank number (e.g. two entries both at the top count both
  /// show rank 1); `counts` should already be the final, truncated/expanded
  /// list the caller is about to render — this never re-derives truncation.
  static func rank(for count: Int, among counts: [Int]) -> Int {
    let distinctDesc = Array(Set(counts)).sorted(by: >)
    return (distinctDesc.firstIndex(of: count) ?? 0) + 1
  }

  // MARK: - Top artists (tie-expansion to 3rd distinct count)

  static func topArtists(_ records: [CD_ChekiRecord]) -> [RankedArtist] {
    let tiles = ArtistGrouping.tiles(from: records)
    let distinctCountsDesc = Array(Set(tiles.map(\.showCount))).sorted(by: >)
    let kept: [ArtistGrouping.Tile]
    if distinctCountsDesc.count >= 3 {
      let threshold = distinctCountsDesc[2]
      kept = tiles.filter { $0.showCount >= threshold }
    } else {
      kept = tiles
    }
    let keptCounts = kept.map(\.showCount)
    return kept.map { tile in
      RankedArtist(
        id: tile.id,
        rank: rank(for: tile.showCount, among: keptCounts),
        name: tile.name,
        count: tile.showCount,
        coverImageData: tile.coverImageData
      )
    }
  }

  // MARK: - All artists (sorted by most recent show, not count)

  static func allArtists(_ records: [CD_ChekiRecord]) -> [ArtistArchiveEntry] {
    var order: [String] = []
    var latest: [String: (name: String, instant: Date, coverImageData: Data?)] = [:]

    for record in records {
      guard let instant = recordInstant(record) else { continue }
      for name in ArtistGrouping.names(for: record) {
        let key = name.lowercased()
        if let existing = latest[key] {
          if instant > existing.instant {
            latest[key] = (existing.name, instant, record.coverImageData ?? existing.coverImageData)
          } else if existing.coverImageData == nil, let cover = record.coverImageData {
            latest[key] = (existing.name, existing.instant, cover)
          }
        } else {
          latest[key] = (name, instant, record.coverImageData)
          order.append(key)
        }
      }
    }

    return order
      .map { key -> (entry: ArtistArchiveEntry, instant: Date) in
        let value = latest[key]!
        let entry = ArtistArchiveEntry(
          id: key,
          name: value.name,
          // Locale must be pinned to English — a bare .formatted(.dateTime...)
          // respects the device locale, which would silently reformat this
          // as e.g. "2024年5月10日" on a Japanese-locale device. This exact
          // bug class (locale-dependent date display) has already been hit
          // and fixed twice elsewhere in this migration.
          lastLiveDateText: value.instant.formatted(
            .dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US"))
          ),
          coverImageData: value.coverImageData
        )
        return (entry, value.instant)
      }
      .sorted { $0.instant > $1.instant }
      .map(\.entry)
  }

  // MARK: - Monthly lives (fixed Jan-Dec buckets, summed across all years present)

  static func monthlyBuckets(_ records: [CD_ChekiRecord]) -> [MonthlyBucket] {
    var counts = Array(repeating: 0, count: 12)
    for record in records {
      guard let date = DateFormatting.date(from: record.date) else { continue }
      let month = DateFormatting.utcCalendar.component(.month, from: date)
      counts[month - 1] += 1
    }
    return (1...12).map { MonthlyBucket(id: $0, label: monthAbbreviations[$0 - 1], count: counts[$0 - 1]) }
  }

  // MARK: - Top venues (hard top-3, no tie-expansion)

  static func topVenues(_ records: [CD_ChekiRecord]) -> [RankedVenue] {
    let counts = Dictionary(grouping: records.compactMap(\.venue), by: { $0 }).mapValues(\.count)
    let sorted = counts.sorted { lhs, rhs in
      lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }
    let top3 = Array(sorted.prefix(3))
    let topCounts = top3.map(\.value)
    return top3.map { entry in
      RankedVenue(id: entry.key, rank: rank(for: entry.value, among: topCounts), name: entry.key, count: entry.value)
    }
  }

  // MARK: - Top songs (hard top-5, no tie-expansion; songId else lowercased/trimmed name)

  static func topSongs(_ records: [CD_ChekiRecord]) -> [RankedSong] {
    struct Bucket {
      var name: String
      var count: Int
      var artworkUrl: String?
    }

    var buckets: [String: Bucket] = [:]
    var order: [String] = []

    for record in records {
      for item in record.sortedSetlistItems where item.kind == "song" {
        guard let rawName = item.songName?.trimmingCharacters(in: .whitespaces), !rawName.isEmpty else { continue }
        let key = item.songId ?? rawName.lowercased()
        if var existing = buckets[key] {
          existing.count += 1
          if existing.artworkUrl == nil, let artwork = item.artworkUrl {
            existing.artworkUrl = artwork
          }
          buckets[key] = existing
        } else {
          buckets[key] = Bucket(name: rawName, count: 1, artworkUrl: item.artworkUrl)
          order.append(key)
        }
      }
    }

    let sorted = order
      .map { (key: $0, bucket: buckets[$0]!) }
      .enumerated()
      .sorted { lhs, rhs in
        lhs.element.bucket.count == rhs.element.bucket.count
          ? lhs.offset < rhs.offset
          : lhs.element.bucket.count > rhs.element.bucket.count
      }
      .map(\.element)
    let top5 = Array(sorted.prefix(5))
    let topCounts = top5.map(\.bucket.count)
    return top5.map { entry in
      RankedSong(
        id: entry.key,
        rank: rank(for: entry.bucket.count, among: topCounts),
        name: entry.bucket.name,
        count: entry.bucket.count,
        artworkUrl: entry.bucket.artworkUrl
      )
    }
  }

  // MARK: - Total spending

  static func totalSpending(_ records: [CD_ChekiRecord]) -> Double {
    records.reduce(0.0) { $0 + $1.ticketPrice }
  }
}
