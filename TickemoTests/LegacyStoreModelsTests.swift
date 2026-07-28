import XCTest
@testable import Tickemo

final class LegacyStoreModelsTests: XCTestCase {
  func testDecodesSongEncoreAndMCVariants() throws {
    let json = """
    [
      {"id":"a1","type":"song","songId":"123","songName":"Song A","artistName":"Artist A","albumName":"Album A","artworkUrl":"https://example.com/a.jpg","orderIndex":0},
      {"id":"a2","type":"encore","title":"ENCORE","orderIndex":1},
      {"id":"a3","type":"mc","title":"MC Talk","note":"some note","orderIndex":2}
    ]
    """.data(using: .utf8)!

    let items = try JSONDecoder().decode([LegacySetlistItem].self, from: json)
    XCTAssertEqual(items.count, 3)

    guard case .song(let id, let songId, let songName, let artistName, let albumName, let artworkUrl, let orderIndex) = items[0] else {
      return XCTFail("Expected song variant")
    }
    XCTAssertEqual(id, "a1")
    XCTAssertEqual(songId, "123")
    XCTAssertEqual(songName, "Song A")
    XCTAssertEqual(artistName, "Artist A")
    XCTAssertEqual(albumName, "Album A")
    XCTAssertEqual(artworkUrl, "https://example.com/a.jpg")
    XCTAssertEqual(orderIndex, 0)

    guard case .encore(let encoreId, let title, let encoreOrder) = items[1] else {
      return XCTFail("Expected encore variant")
    }
    XCTAssertEqual(encoreId, "a2")
    XCTAssertEqual(title, "ENCORE")
    XCTAssertEqual(encoreOrder, 1)

    guard case .mc(let mcId, let mcTitle, let note, let mcOrder) = items[2] else {
      return XCTFail("Expected mc variant")
    }
    XCTAssertEqual(mcId, "a3")
    XCTAssertEqual(mcTitle, "MC Talk")
    XCTAssertEqual(note, "some note")
    XCTAssertEqual(mcOrder, 2)
  }

  func testDecodesZustandEnvelopeWithIndexParallelArtists() throws {
    let json = """
    {
      "state": {
        "lives": [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "artists": ["Artist One", "Artist Two"],
            "artistImageUrls": ["https://example.com/1.jpg", "https://example.com/2.jpg"],
            "liveName": "Test Live",
            "date": "2026-01-01",
            "imageUrls": ["Tickemo/lives/1/a.jpg"],
            "imageAssetIds": [null],
            "memo": "memo text",
            "createdAt": "2026-01-01T00:00:00.000Z"
          }
        ],
        "setlists": {
          "11111111-1111-1111-1111-111111111111": [
            {"id":"s1","type":"song","songName":"Song 1","orderIndex":0}
          ]
        },
        "userProfile": {
          "name": "Test User",
          "username": "testuser",
          "joinedAt": "2026-01-01T00:00:00.000Z"
        },
        "hasOnboarded": true
      },
      "version": 0
    }
    """.data(using: .utf8)!

    let envelope = try JSONDecoder().decode(ZustandEnvelope.self, from: json)
    XCTAssertEqual(envelope.version, 0)
    XCTAssertEqual(envelope.state.lives.count, 1)

    let record = envelope.state.lives[0]
    XCTAssertEqual(record.artists, ["Artist One", "Artist Two"])
    XCTAssertEqual(record.artistImageUrls, ["https://example.com/1.jpg", "https://example.com/2.jpg"])
    XCTAssertEqual(record.artists?.count, record.artistImageUrls?.count)

    XCTAssertEqual(envelope.state.setlists[record.id]?.count, 1)
    XCTAssertEqual(envelope.state.userProfile?.name, "Test User")
    XCTAssertTrue(envelope.state.hasOnboarded)
  }

  func testICloudDataJSONFallbackShapeDecodes() throws {
    let json = """
    {
      "lives": [],
      "setlists": {},
      "userProfile": null,
      "hasOnboarded": false,
      "updatedAt": "2026-01-01T00:00:00.000Z"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(ICloudDataJSON.self, from: json)
    XCTAssertTrue(decoded.lives.isEmpty)
    XCTAssertNil(decoded.userProfile)
    XCTAssertFalse(decoded.hasOnboarded)
  }
}
