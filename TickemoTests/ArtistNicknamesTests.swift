import CoreData
import XCTest
@testable import Tickemo

final class ArtistNicknamesTests: XCTestCase {
  // MARK: - ArtistNicknames

  func testDisplayNameFallsBackToOfficialNameWithoutNickname() {
    XCTAssertEqual(ArtistNicknames.displayName(for: "テイラー・スウィフト", in: [:]), "テイラー・スウィフト")
  }

  func testDisplayNameUsesNicknameMatchedCaseInsensitivelyAndTrimmed() {
    let nicknames = ArtistNicknames.updating([:], artistName: "Mrs. GREEN APPLE", nickname: "ミセス")
    XCTAssertEqual(ArtistNicknames.displayName(for: " mrs. green apple ", in: nicknames), "ミセス")
  }

  func testUpdatingTrimsNickname() {
    let nicknames = ArtistNicknames.updating([:], artistName: "テイラー・スウィフト", nickname: "  Taylor Swift \n")
    XCTAssertEqual(nicknames, ["テイラー・スウィフト": "Taylor Swift"])
  }

  func testUpdatingWithEmptyNicknameRemovesIt() {
    let set = ArtistNicknames.updating([:], artistName: "Aimer", nickname: "えめ")
    XCTAssertEqual(ArtistNicknames.updating(set, artistName: "Aimer", nickname: "   "), [:])
    XCTAssertEqual(ArtistNicknames.updating(set, artistName: "Aimer", nickname: nil), [:])
  }

  func testUpdatingWithOfficialNameRemovesNicknameButKeepsCaseOnlyChange() {
    let set = ArtistNicknames.updating([:], artistName: "Aimer", nickname: "えめ")
    XCTAssertEqual(ArtistNicknames.updating(set, artistName: "Aimer", nickname: "Aimer"), [:])
    XCTAssertEqual(ArtistNicknames.updating([:], artistName: "Aimer", nickname: "AIMER"), ["aimer": "AIMER"])
  }

  func testUpdatingIgnoresEmptyArtistName() {
    XCTAssertEqual(ArtistNicknames.updating([:], artistName: "  ", nickname: "x"), [:])
  }

  // MARK: - ArtistNicknameStore

  func testStorePersistsToBackingAndReloads() {
    let backing = InMemoryArtistNicknameBackingStore()
    let store = ArtistNicknameStore(backing: backing)
    store.setNickname("Taylor Swift", for: "テイラー・スウィフト")

    XCTAssertEqual(backing.stored, ["テイラー・スウィフト": "Taylor Swift"])
    XCTAssertEqual(ArtistNicknameStore(backing: backing).displayName(for: "テイラー・スウィフト"), "Taylor Swift")
  }

  func testStoreClearsNickname() {
    let backing = InMemoryArtistNicknameBackingStore(initial: ["aimer": "えめ"])
    let store = ArtistNicknameStore(backing: backing)
    XCTAssertEqual(store.nickname(for: "Aimer"), "えめ")

    store.setNickname("", for: "Aimer")
    XCTAssertNil(store.nickname(for: "Aimer"))
    XCTAssertEqual(backing.stored, [:])
  }

  // MARK: - Receipt card

  private func makeContext() -> NSManagedObjectContext {
    PersistenceController(inMemory: true).container.viewContext
  }

  private func makeSong(_ context: NSManagedObjectContext, name: String, performer: String) -> CD_SetlistItem {
    let item = CD_SetlistItem(context: context)
    item.kind = "song"
    item.songName = name
    item.performerName = performer
    return item
  }

  func testReceiptUsesNicknamesForDisplayOnly() {
    let context = makeContext()
    let items = [
      makeSong(context, name: "A", performer: "テイラー・スウィフト"),
      makeSong(context, name: "B", performer: "Aimer"),
    ]
    let nicknames = ["テイラー・スウィフト": "Taylor Swift"]

    XCTAssertEqual(
      ShareCardData.receiptArtistLabel(setlistItems: items, fallbackArtist: nil, nicknames: nicknames),
      "Taylor Swift / Aimer"
    )
    let names = ShareCardData.receiptRows(setlistItems: items, nicknames: nicknames).compactMap { row -> String? in
      if case .song(_, let name, _) = row { return name }
      return nil
    }
    XCTAssertEqual(names, ["A - Taylor Swift", "B - Aimer"])
  }
}
