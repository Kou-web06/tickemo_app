import MusicKit
import Foundation

final class MusicKitService {
  func play(songId: String) async throws {
    let status = await MusicAuthorization.request()
    if status != .authorized {
      throw NSError(domain: "MusicKit", code: 401, userInfo: [NSLocalizedDescriptionKey: "Apple Musicへのアクセス権限がありません"])
    }

    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songId))
    let response = try await request.response()

    guard let song = response.items.first else {
      throw NSError(domain: "MusicKit", code: 404, userInfo: [NSLocalizedDescriptionKey: "曲が見つかりませんでした"])
    }

    SystemMusicPlayer.shared.queue = [song]
    try await SystemMusicPlayer.shared.play()
  }

  func stop() {
    SystemMusicPlayer.shared.stop()
  }
}
