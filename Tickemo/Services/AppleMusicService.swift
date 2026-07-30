import MusicKit
import Foundation

final class AppleMusicService {
  private var musicPlayer = ApplicationMusicPlayer.shared

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

  struct ArtistResult {
    let id: String
    let name: String
    let imageUrl: String
  }

  func searchArtists(term: String) async throws -> [ArtistResult] {
    guard !term.isEmpty else {
      return []
    }
    await ensureAuthorized()

    var request = MusicCatalogSearchRequest(term: term, types: [Artist.self])
    request.limit = 10

    let response = try await request.response()

    return response.artists.map { artist in
      // 1200x1200 comfortably clears the requested 800x800 floor; a single
      // high-resolution URL is stored (see ArtistSearchField/ArtistGrouping)
      // rather than RN's template-URL-resolved-per-call-site approach, since
      // MusicKit's Artwork.url(width:height:) already returns a fixed URL.
      let imageUrl = artist.artwork?.url(width: 1200, height: 1200)?.absoluteString ?? ""
      return ArtistResult(id: artist.id.rawValue, name: artist.name, imageUrl: imageUrl)
    }
  }

  struct SongResult {
    let id: String
    let title: String
    let artistName: String
    let albumName: String
    let artworkUrl: String
  }

  func searchSongs(term: String) async throws -> [SongResult] {
    guard !term.isEmpty else {
      return []
    }
    await ensureAuthorized()

    var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
    request.limit = 10

    let response = try await request.response()

    return response.songs.map { song in
      let imageUrl = song.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
      return SongResult(
        id: song.id.rawValue,
        title: song.title,
        artistName: song.artistName,
        albumName: song.albumTitle ?? "",
        artworkUrl: imageUrl
      )
    }
  }
}
