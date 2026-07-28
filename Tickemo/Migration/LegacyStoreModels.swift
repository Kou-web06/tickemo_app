import Foundation

/// Mirrors `types/record.ts`'s `ChekiRecord`, minus `user_id` (confirmed dead:
/// always hardcoded `'local-user'` at every write site, never read anywhere).
/// `imagePath` is kept even though it looks legacy — it's still read as a
/// fallback in App.tsx and components/ShareImageGenerator.tsx.
struct LegacyChekiRecord: Decodable {
  let id: String
  let artists: [String]?
  let artist: String?
  let artistImageUrls: [String]?
  let artistImageUrl: String?
  let liveName: String
  let liveType: String?
  let date: String
  let venue: String?
  let seat: String?
  let ticketPrice: Double?
  let startTime: String?
  let endTime: String?
  let imagePath: String?
  let imageUrls: [String]?
  let imageAssetIds: [String?]?
  let memo: String
  let detail: String?
  let qrCode: String?
  let createdAt: String
}

/// Mirrors `types/setlist.ts`'s `SetlistItem` discriminated union (on `type`).
/// `Codable` has no native support for discriminated unions, so this uses a
/// hand-written `init(from:)` that switches on `type` after decoding it.
enum LegacySetlistItem: Decodable {
  case song(id: String, songId: String?, songName: String, artistName: String?, albumName: String?, artworkUrl: String?, orderIndex: Int)
  case encore(id: String, title: String, orderIndex: Int)
  case mc(id: String, title: String, note: String?, orderIndex: Int)

  private enum CodingKeys: String, CodingKey {
    case id, type, songId, songName, artistName, albumName, artworkUrl, orderIndex, title, note
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let orderIndex = try container.decode(Int.self, forKey: .orderIndex)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "song":
      self = .song(
        id: id,
        songId: try container.decodeIfPresent(String.self, forKey: .songId),
        songName: try container.decode(String.self, forKey: .songName),
        artistName: try container.decodeIfPresent(String.self, forKey: .artistName),
        albumName: try container.decodeIfPresent(String.self, forKey: .albumName),
        artworkUrl: try container.decodeIfPresent(String.self, forKey: .artworkUrl),
        orderIndex: orderIndex
      )
    case "encore":
      self = .encore(id: id, title: try container.decode(String.self, forKey: .title), orderIndex: orderIndex)
    case "mc":
      self = .mc(
        id: id,
        title: try container.decode(String.self, forKey: .title),
        note: try container.decodeIfPresent(String.self, forKey: .note),
        orderIndex: orderIndex
      )
    default:
      throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown SetlistItem type: \(type)")
    }
  }

  var id: String {
    switch self {
    case .song(let id, _, _, _, _, _, _): return id
    case .encore(let id, _, _): return id
    case .mc(let id, _, _, _): return id
    }
  }

  var orderIndex: Int {
    switch self {
    case .song(_, _, _, _, _, _, let orderIndex): return orderIndex
    case .encore(_, _, let orderIndex): return orderIndex
    case .mc(_, _, _, let orderIndex): return orderIndex
    }
  }
}

/// Mirrors `store/useAppStore.ts`'s `UserProfile`.
struct LegacyUserProfile: Decodable {
  let name: String
  let username: String
  let avatarUri: String?
  let joinedAt: String
  let plusStartedAt: String?
}

/// The subset of Zustand's `AppState` worth carrying into Core Data.
/// RevenueCat-derived fields (`isPremium`, `membershipType`,
/// `activeEntitlementIds`, `revenueCatInitialized`) and persist-middleware
/// bookkeeping (`hasHydrated`) are deliberately not declared here — they're
/// local/session-only state, not sync data, and JSONDecoder silently ignores
/// unknown keys.
struct PersistedAppState: Decodable {
  let lives: [LegacyChekiRecord]
  let setlists: [String: [LegacySetlistItem]]
  let userProfile: LegacyUserProfile?
  let hasOnboarded: Bool
}

/// Zustand's `persist` middleware envelope, exactly as written to AsyncStorage
/// at key `"tickemo-store"` (no explicit `version` option was passed on the
/// JS side, so it defaults to `0`).
struct ZustandEnvelope: Decodable {
  let state: PersistedAppState
  let version: Int
}

/// `hooks/useCloudSync.ts`'s `/tickemo_data.json` — the only iCloud sync
/// variant actually wired up in the app (confirmed: `useICloudKvsSync` is
/// never imported anywhere).
struct ICloudDataJSON: Decodable {
  let lives: [LegacyChekiRecord]
  let setlists: [String: [LegacySetlistItem]]
  let userProfile: LegacyUserProfile?
  let hasOnboarded: Bool
  let updatedAt: String
}

/// `hooks/useCloudSync.ts`'s dead-but-cheap-to-read `/tickemo_kvs.json`
/// variant (`useICloudKvsSync`, never actually invoked by the RN app, but a
/// prior app version could conceivably have left this file behind).
struct ICloudKvsJSON: Decodable {
  let schemaVersion: Int
  let updatedAt: String
  let lives: [LegacyChekiRecord]
  let setlists: [String: [LegacySetlistItem]]
  let userProfile: LegacyUserProfile?
  let hasOnboarded: Bool
}
