import XCTest
import CoreData
@testable import Tickemo

final class ArtistGroupingTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  private func makeRecord(
    artist: String? = nil,
    artists: [String]? = nil,
    artistImageUrl: String? = nil,
    artistImageUrls: [String]? = nil,
    date: String,
    ticketPrice: Double = 0,
    withCoverImage: Bool = false
  ) -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    record.artist = artist
    record.artists = artists.map { NSArray(array: $0) }
    record.artistImageUrl = artistImageUrl
    record.artistImageUrls = artistImageUrls.map { NSArray(array: $0) }
    record.date = date
    record.ticketPrice = ticketPrice
    record.liveName = "Test Live"

    if withCoverImage {
      let image = CD_LiveImage(context: context)
      image.id = UUID()
      image.orderIndex = 0
      image.data = Data([0x00])
      image.record = record
    }

    return record
  }

  func testGroupingIsCaseInsensitiveAndTrimmed() {
    let a = makeRecord(artist: "Yoasobi", date: "2020-01-01")
    let b = makeRecord(artist: " YOASOBI ", date: "2020-06-01")
    try? context.save()

    let tiles = ArtistGrouping.tiles(from: [a, b])

    XCTAssertEqual(tiles.count, 1)
    XCTAssertEqual(tiles.first?.showCount, 2)
    // First-encountered casing is kept as the display name.
    XCTAssertEqual(tiles.first?.name, "Yoasobi")
  }

  func testGroupingPrefersMultiArtistArrayOverSingularField() {
    let record = makeRecord(artist: "Solo Name", artists: ["Artist One", "Artist Two"], date: "2020-01-01")
    try? context.save()

    let tiles = ArtistGrouping.tiles(from: [record])

    XCTAssertEqual(Set(tiles.map(\.name)), ["Artist One", "Artist Two"])
    XCTAssertFalse(tiles.contains { $0.name == "Solo Name" })
  }

  func testMatchesIsCaseInsensitive() {
    let record = makeRecord(artist: "Artist One", date: "2020-01-01")
    try? context.save()

    XCTAssertTrue(ArtistGrouping.matches(record, artistName: "artist one"))
    XCTAssertFalse(ArtistGrouping.matches(record, artistName: "artist two"))
  }

  func testLatestPastDateOnlyConsidersPastShows() {
    let farFuture = "2999-01-01"
    let past = "2020-06-15"
    let a = makeRecord(artist: "Artist", date: past)
    let b = makeRecord(artist: "Artist", date: farFuture)
    try? context.save()

    let tiles = ArtistGrouping.tiles(from: [a, b])

    XCTAssertEqual(tiles.first?.latestPastDateText, past)
  }

  func testTileCoverImagePicksFirstRecordWithData() {
    let withoutImage = makeRecord(artist: "Artist", date: "2020-01-01", withCoverImage: false)
    let withImage = makeRecord(artist: "Artist", date: "2020-06-01", withCoverImage: true)
    try? context.save()

    let tiles = ArtistGrouping.tiles(from: [withoutImage, withImage])

    XCTAssertNotNil(tiles.first?.coverImageData)
  }

  // MARK: - Artist photo entries (RN's resolveArtistThumbUrl/getRecordArtistEntries)

  func testEntriesAlignsImageUrlsByIndexWithArtistsArray() {
    let record = makeRecord(artists: ["Artist One", "Artist Two"], artistImageUrls: ["urlA", "urlB"], date: "2020-01-01")
    try? context.save()

    let entries = ArtistGrouping.entries(for: record)

    XCTAssertEqual(entries.map(\.name), ["Artist One", "Artist Two"])
    XCTAssertEqual(entries.map(\.imageUrl), ["urlA", "urlB"])
  }

  func testEntriesFallsBackToSingleArtistImageUrlAtIndexZeroOnly() {
    let record = makeRecord(artist: "Solo Artist", artistImageUrl: "solo-url", date: "2020-01-01")
    try? context.save()

    let entries = ArtistGrouping.entries(for: record)

    XCTAssertEqual(entries.map(\.name), ["Solo Artist"])
    XCTAssertEqual(entries.map(\.imageUrl), ["solo-url"])
  }

  func testEntriesDoesNotFallBackToSingleArtistImageUrlForLaterIndices() {
    // artistImageUrls is shorter than artists — index 1 ("Artist Two") has
    // no entry in the array, and must NOT fall back to the unrelated
    // single-artist artistImageUrl field (that fallback only applies to
    // index 0, matching RN's `index === 0 ? record.artistImageUrl : ''`).
    let record = makeRecord(
      artists: ["Artist One", "Artist Two"],
      artistImageUrl: "stale-single-artist-url",
      artistImageUrls: ["urlA"],
      date: "2020-01-01"
    )
    try? context.save()

    let entries = ArtistGrouping.entries(for: record)

    XCTAssertEqual(entries.first(where: { $0.name == "Artist One" })?.imageUrl, "urlA")
    XCTAssertNil(entries.first(where: { $0.name == "Artist Two" })?.imageUrl)
  }

  func testTileArtistImageUrlPicksFirstNonNilAcrossRecords() {
    let withoutUrl = makeRecord(artist: "Artist", date: "2020-01-01")
    let withUrl = makeRecord(artist: "Artist", artistImageUrl: "official-url", date: "2020-06-01")
    try? context.save()

    let tiles = ArtistGrouping.tiles(from: [withoutUrl, withUrl])

    XCTAssertEqual(tiles.first?.artistImageUrl, "official-url")
  }

  func testSortedSetlistItemsOrdersByOrderIndexRegardlessOfInsertionOrder() {
    let record = makeRecord(artist: "Artist", date: "2020-01-01")

    let second = CD_SetlistItem(context: context)
    second.id = UUID()
    second.kind = "song"
    second.songName = "Second Song"
    second.orderIndex = 1
    second.record = record

    let first = CD_SetlistItem(context: context)
    first.id = UUID()
    first.kind = "song"
    first.songName = "First Song"
    first.orderIndex = 0
    first.record = record

    try? context.save()

    let sorted = record.sortedSetlistItems
    XCTAssertEqual(sorted.map(\.songName), ["First Song", "Second Song"])
  }

  func testDeleteAllThenReinsertReplacesSetlistCompletely() {
    let record = makeRecord(artist: "Artist", date: "2020-01-01")
    let stale = CD_SetlistItem(context: context)
    stale.id = UUID()
    stale.kind = "song"
    stale.songName = "Stale Song"
    stale.orderIndex = 0
    stale.record = record
    try? context.save()

    XCTAssertEqual(record.sortedSetlistItems.count, 1)

    // Mirrors SetlistEditorView.save()'s delete-all-then-reinsert semantics.
    for existing in record.sortedSetlistItems {
      context.delete(existing)
    }
    let replacement = CD_SetlistItem(context: context)
    replacement.id = UUID()
    replacement.kind = "encore"
    replacement.title = "ENCORE"
    replacement.orderIndex = 0
    replacement.record = record
    try? context.save()

    XCTAssertEqual(record.sortedSetlistItems.count, 1)
    XCTAssertEqual(record.sortedSetlistItems.first?.kind, "encore")
  }
}
