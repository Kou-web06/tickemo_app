import MusicKit
import Foundation

final class AppleMusicService {
  private var musicPlayer = ApplicationMusicPlayer.shared

  // Storefront hardcoded to "jp", matching RN's utils/appleMusicApi.ts exactly
  // (never derived from the device's region) — this app's userbase/content is
  // Japan-focused regardless of what a given device happens to be set to.
  private static let storefront = "jp"

  func authorize() async -> Bool {
    let status = await MusicAuthorization.request()
    return status == .authorized
  }

  func play(songId: String) async throws {
    await ensureAuthorized()
    let request = MusicCatalogResourceRequest<Song>(
      matching: \.id,
      equalTo: MusicItemID(songId)
    )
    let response = try await request.response()

    guard let song = response.items.first else {
      throw NSError(domain: "AppleMusicService", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Song not found"])
    }

    musicPlayer.queue = [song]
    try await musicPlayer.play()
  }

  func pause() {
    musicPlayer.pause()
  }

  func stop() {
    musicPlayer.stop()
  }

  func isAuthorized() -> Bool {
    MusicAuthorization.currentStatus == .authorized
  }

  // MusicCatalogSearchRequest silently throws MusicDataRequest.Error
  // .permissionDenied when the app hasn't been granted Apple Music access
  // yet — .notDetermined never auto-prompts on its own. Every catalog
  // search call site needs this, so it's centralized here rather than
  // pushed onto each caller (RecordFormView's ArtistSearchField,
  // StatisticsView's live backfill, SetlistEditorView's song search).
  private func ensureAuthorized() async {
    guard MusicAuthorization.currentStatus != .authorized else { return }
    _ = await MusicAuthorization.request()
  }

  // MARK: - Result types

  struct ArtistResult {
    let id: String
    let name: String
    let imageUrl: String
    // ArtistDetailView's genre stat column + editorial-notes section.
    // MusicKit's Artist type has no formation-year field, so that's not
    // sourced here.
    let genreNames: [String]
    let editorialNotes: EditorialNotes?

    struct EditorialNotes {
      let standard: String?
      let short: String?
    }
  }

  struct SongResult {
    let id: String
    let title: String
    let artistName: String
    let albumName: String
    let artworkUrl: String
    // Populated for TodaySongCache's back-of-card meta grid (Genre/Rel,
    // Album/Time) — unused by the existing SetlistEditor search callers,
    // which only need the fields above.
    let genreName: String?
    let durationSeconds: Double?
    let releaseDate: Date?
    let appleMusicUrl: String?
  }

  // MARK: - Language

  // MusicCatalogSearchRequest uses Locale.current internally, which reflects
  // the device language. Using MusicDataRequest with an explicit `l`
  // parameter keeps results in Japanese — the app dropped its language
  // setting and is Japanese-only now — even on non-Japanese devices.
  private func preferredLanguageCode() -> String {
    "ja"
  }

  // MARK: - Apple Music API Codable types

  private struct AMSearchResponse: Decodable {
    struct Results: Decodable {
      var artists: AMCollection<AMArtist>?
      var songs: AMCollection<AMSong>?
    }
    var results: Results
  }

  private struct AMCollection<T: Decodable>: Decodable {
    var data: [T]
  }

  private struct AMArtist: Decodable {
    var id: String
    var attributes: Attributes?
    struct Attributes: Decodable {
      var name: String
      var artwork: AMArtwork?
      var genreNames: [String]?
      var editorialNotes: AMEditorialNotes?
    }
  }

  private struct AMEditorialNotes: Decodable {
    var standard: String?
    var short: String?
  }

  private struct AMSong: Decodable {
    var id: String
    var attributes: Attributes?
    struct Attributes: Decodable {
      var name: String
      var artistName: String
      var albumTitle: String?
      var artwork: AMArtwork?
      var genreNames: [String]?
      var durationInMillis: Double?
      var releaseDate: String?
      var url: String?
    }
  }

  private struct AMArtwork: Decodable {
    var url: String
  }

  /// Apple Music API artwork URLs are templates like ".../{w}x{h}bb.jpg" —
  /// resolved at each display site to the size that site needs (matching
  /// RN's utils/appleMusicApi.ts `getArtworkUrl`), rather than baked into a
  /// single fixed size at fetch time. Non-template URLs pass through
  /// unchanged.
  static func resolvedArtworkURL(_ url: String, size: Int) -> String {
    guard url.contains("{w}") || url.contains("{h}") else { return url }
    return url
      .replacingOccurrences(of: "{w}", with: "\(size)")
      .replacingOccurrences(of: "{h}", with: "\(size)")
  }

  // Mirrors RN's appleMusicApi.ts module-level cache: 5-minute TTL, keyed by
  // normalized term+limit+storefront+locale, with in-flight de-duplication
  // so two concurrent identical searches share one network call. Actor-
  // isolated since AppleMusicService instances are created per-view (not a
  // shared singleton) but this cache is meant to be shared app-wide, same as
  // RN's module-scope Maps.
  private actor SearchCache {
    static let shared = SearchCache()
    private let ttl: TimeInterval = 5 * 60

    private struct Entry<T> {
      let value: T
      let expiresAt: Date
    }

    private var artistResults: [String: Entry<[ArtistResult]>] = [:]
    private var songResults: [String: Entry<[SongResult]>] = [:]
    private var artistInFlight: [String: Task<[ArtistResult], Error>] = [:]
    private var songInFlight: [String: Task<[SongResult], Error>] = [:]

    func artists(for key: String, fetch: @escaping () async throws -> [ArtistResult]) async throws -> [ArtistResult] {
      if let cached = artistResults[key], cached.expiresAt > Date() { return cached.value }
      if let inFlight = artistInFlight[key] { return try await inFlight.value }
      let task = Task { try await fetch() }
      artistInFlight[key] = task
      defer { artistInFlight[key] = nil }
      let value = try await task.value
      artistResults[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
      return value
    }

    func songs(for key: String, fetch: @escaping () async throws -> [SongResult]) async throws -> [SongResult] {
      if let cached = songResults[key], cached.expiresAt > Date() { return cached.value }
      if let inFlight = songInFlight[key] { return try await inFlight.value }
      let task = Task { try await fetch() }
      songInFlight[key] = task
      defer { songInFlight[key] = nil }
      let value = try await task.value
      songResults[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
      return value
    }
  }

  private func cacheKey(term: String, limit: Int) -> String {
    "\(term.trimmingCharacters(in: .whitespaces).lowercased())::\(limit)::\(Self.storefront)::\(preferredLanguageCode())"
  }

  private static let releaseDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }()

  private func catalogSearchURL(term: String, types: String, limit: Int) -> URL? {
    var comps = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(Self.storefront)/search")
    comps?.queryItems = [
      URLQueryItem(name: "term", value: term),
      URLQueryItem(name: "types", value: types),
      URLQueryItem(name: "l", value: preferredLanguageCode()),
      URLQueryItem(name: "limit", value: "\(limit)"),
    ]
    return comps?.url
  }

  // MARK: - Search

  /// Matches RN's StatisticsScreen.tsx backfill exactly: search with
  /// `limit=1` and take whatever comes back, no name-similarity scoring.
  func bestMatchArtistImageUrl(for name: String) async -> String? {
    let results = (try? await searchArtists(term: name, limit: 1)) ?? []
    guard let url = results.first?.imageUrl, !url.isEmpty else { return nil }
    return url
  }

  // ArtistDetailView's genre + editorial-notes lookup. Shares searchArtists'
  // cache/in-flight de-dup, so this costs no extra network call when
  // bestMatchArtistImageUrl already ran for the same name.
  func bestMatchArtist(for name: String) async -> ArtistResult? {
    let results = (try? await searchArtists(term: name, limit: 1)) ?? []
    return results.first
  }

  func searchArtists(term: String, limit: Int = 10) async throws -> [ArtistResult] {
    guard !term.isEmpty else { return [] }
    await ensureAuthorized()

    let key = cacheKey(term: term, limit: limit)
    return try await SearchCache.shared.artists(for: key) { [self] in
      guard let url = catalogSearchURL(term: term, types: "artists", limit: limit) else { return [] }
      let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
      let decoded = try JSONDecoder().decode(AMSearchResponse.self, from: response.data)

      return decoded.results.artists?.data.compactMap { item in
        guard let attrs = item.attributes else { return nil }
        // Raw template URL, unresolved — matches RN's ArtistInput, which
        // saves `artist.templateUrl` and resolves it per display site
        // (search dropdown/chip: 80px, Statistics/ArtistDetail: 800-900px)
        // rather than baking in one fixed size at fetch time.
        return ArtistResult(
          id: item.id,
          name: attrs.name,
          imageUrl: attrs.artwork?.url ?? "",
          genreNames: attrs.genreNames ?? [],
          editorialNotes: attrs.editorialNotes.map {
            ArtistResult.EditorialNotes(standard: $0.standard, short: $0.short)
          }
        )
      } ?? []
    }
  }

  func searchSongs(term: String, limit: Int = 10) async throws -> [SongResult] {
    guard !term.isEmpty else { return [] }
    await ensureAuthorized()

    let key = cacheKey(term: term, limit: limit)
    return try await SearchCache.shared.songs(for: key) { [self] in
      guard let url = catalogSearchURL(term: term, types: "songs", limit: limit) else { return [] }
      let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
      let decoded = try JSONDecoder().decode(AMSearchResponse.self, from: response.data)

      return decoded.results.songs?.data.compactMap { item in
        guard let attrs = item.attributes else { return nil }
        let releaseDate = attrs.releaseDate.flatMap { Self.releaseDateFormatter.date(from: $0) }
        return SongResult(
          id: item.id,
          title: attrs.name,
          artistName: attrs.artistName,
          albumName: attrs.albumTitle ?? "",
          artworkUrl: Self.resolvedArtworkURL(attrs.artwork?.url ?? "", size: 300),
          genreName: attrs.genreNames?.first,
          durationSeconds: attrs.durationInMillis.map { $0 / 1000 },
          releaseDate: releaseDate,
          appleMusicUrl: attrs.url
        )
      } ?? []
    }
  }
}
