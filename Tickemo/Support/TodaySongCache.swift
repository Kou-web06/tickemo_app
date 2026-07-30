import Foundation

/// Ports screens/CollectionScreen.tsx's `fetchTodaySongForArtist` — a
/// deterministic "song of the day" for the Next Live card's back face,
/// searched via MusicKit, cached per artist+calendar-day in `UserDefaults`
/// (RN's AsyncStorage equivalent), with a rolling history so the same song
/// doesn't repeat too soon.
struct TodaySongResult: Codable, Equatable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let genre: String
  let durationSeconds: Double?
  let releaseDate: Date?
  let artworkUrl: String?
  let appleMusicUrl: String?
}

enum TodaySongCache {
  private static let maxHistory = 20

  /// RN's `seededRandom`: `Math.sin(seed) * 10000`'s fractional part. Any
  /// deterministic per-day pick would satisfy the actual user-facing
  /// requirement, but this exact formula is trivial to port and keeps the
  /// day-to-day song choice identical to what RN would have picked.
  static func seededRandom(_ seed: Double) -> Double {
    let x = sin(seed) * 10000
    return x - x.rounded(.down)
  }

  static func normalizeArtistName(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "[\\s・･·•]", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
  }

  private static func historyKey(for artistName: String) -> String {
    "todaySongHistory:\(normalizeArtistName(artistName))"
  }

  private static func dailyPickKey(for artistName: String, dateKey: String) -> String {
    "todaySongPick:\(normalizeArtistName(artistName)):\(dateKey)"
  }

  // A real local calendar day (like "today's date" shown to the user, not
  // one of CD_ChekiRecord's UTC-anchored wall-clock strings) — Calendar
  // .current is the correct choice here, matching the same
  // real-instant-vs-wall-clock-string distinction already established for
  // joinedAt/plusStartedAt elsewhere in this app.
  private static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
  }

  static func fetchTodaySong(
    for artistName: String,
    now: Date = Date(),
    service: AppleMusicService = AppleMusicService(),
    defaults: UserDefaults = .standard
  ) async -> TodaySongResult? {
    let trimmedArtist = artistName.trimmingCharacters(in: .whitespaces)
    guard !trimmedArtist.isEmpty else { return nil }

    let key = dateKey(for: now)
    let pickKey = dailyPickKey(for: trimmedArtist, dateKey: key)

    if let cached = defaults.data(forKey: pickKey),
       let decoded = try? JSONDecoder().decode(TodaySongResult.self, from: cached) {
      return decoded
    }

    guard let songs = try? await service.searchSongs(term: trimmedArtist, limit: 20), !songs.isEmpty else {
      return nil
    }

    let historyForArtist = defaults.stringArray(forKey: historyKey(for: trimmedArtist)) ?? []
    guard let selectedSong = pickSong(from: songs, matching: trimmedArtist, excluding: historyForArtist, dateKey: key) else {
      return nil
    }

    let nextHistory = Array(([selectedSong.id] + historyForArtist.filter { $0 != selectedSong.id }).prefix(maxHistory))
    defaults.set(nextHistory, forKey: historyKey(for: trimmedArtist))

    let result = TodaySongResult(
      id: selectedSong.id,
      title: selectedSong.title.isEmpty ? "Unknown song" : selectedSong.title,
      artist: selectedSong.artistName.isEmpty ? trimmedArtist : selectedSong.artistName,
      album: selectedSong.albumName.isEmpty ? "-" : selectedSong.albumName,
      genre: selectedSong.genreName ?? "-",
      durationSeconds: selectedSong.durationSeconds,
      releaseDate: selectedSong.releaseDate,
      artworkUrl: selectedSong.artworkUrl.isEmpty ? nil : selectedSong.artworkUrl,
      appleMusicUrl: selectedSong.appleMusicUrl
    )

    if let encoded = try? JSONEncoder().encode(result) {
      defaults.set(encoded, forKey: pickKey)
    }

    return result
  }

  /// Pure selection logic (no I/O), split out from `fetchTodaySong` so it's
  /// unit-testable: prefer songs whose artist name matches `artistName`
  /// (falling back to the full unfiltered list if none match), then prefer
  /// songs not in `excluding` (falling back to the full filtered list if
  /// all have been shown before), then deterministically shuffle by
  /// `dateKey`-seeded score and take the first.
  static func pickSong(
    from songs: [AppleMusicService.SongResult],
    matching artistName: String,
    excluding history: [String],
    dateKey: String
  ) -> AppleMusicService.SongResult? {
    guard !songs.isEmpty else { return nil }

    let normalizedTarget = normalizeArtistName(artistName)
    let artistMatched = songs.filter {
      let normalized = normalizeArtistName($0.artistName)
      return normalized.contains(normalizedTarget) || normalizedTarget.contains(normalized)
    }
    let filteredSongs = artistMatched.isEmpty ? songs : artistMatched

    let freshCandidates = filteredSongs.filter { !history.contains($0.id) }
    let candidates = freshCandidates.isEmpty ? filteredSongs : freshCandidates

    let seed = Double(dateKey.replacingOccurrences(of: "-", with: "")) ?? 0
    let shuffled = candidates.enumerated()
      .map { (item: $0.element, score: seededRandom(seed + Double($0.offset) * 13)) }
      .sorted { $0.score < $1.score }
    return shuffled.first?.item ?? candidates.first
  }
}
