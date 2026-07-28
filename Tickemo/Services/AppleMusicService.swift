import MusicKit
import Foundation

final class AppleMusicService {
  private var musicPlayer = ApplicationMusicPlayer.shared
  private var developerToken: String?

  func configure(token: String) {
    developerToken = token
  }

  func authorize() async -> Bool {
    let status = await MusicAuthorization.request()
    return status == .authorized
  }

  func play(songId: String) async throws {
    guard developerToken != nil else {
      throw NSError(domain: "AppleMusicService", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Developer token not set"])
    }

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

  struct ArtistResult {
    let id: String
    let name: String
    let imageUrl: String
  }

  func searchArtists(term: String) async throws -> [ArtistResult] {
    guard !term.isEmpty else {
      return []
    }

    var request = MusicCatalogSearchRequest(term: term, types: [Artist.self])
    request.limit = 10

    let response = try await request.response()

    return response.artists.map { artist in
      let imageUrl = artist.artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
      return ArtistResult(id: artist.id.rawValue, name: artist.name, imageUrl: imageUrl)
    }
  }
}
