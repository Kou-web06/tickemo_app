import XCTest
@testable import Tickemo

final class RecordFormValidationTests: XCTestCase {
  private typealias Artist = RecordFormValidation.ArtistInput

  private func isValid(
    liveName: String = "Some Live",
    venue: String = "Some Venue",
    liveType: LiveType = .oneMan,
    artists: [Artist]
  ) -> Bool {
    RecordFormValidation.isValid(liveName: liveName, venue: venue, liveType: liveType, artistEntries: artists)
  }

  func testRequiresLiveNameAndVenue() {
    XCTAssertFalse(isValid(liveName: "", artists: [Artist(name: "A", imageUrl: "url")]))
    XCTAssertFalse(isValid(venue: "", artists: [Artist(name: "A", imageUrl: "url")]))
    XCTAssertFalse(isValid(liveName: "  ", artists: [Artist(name: "A", imageUrl: "url")]))
  }

  func testSingleArtistRequiresAnImageUrl() {
    XCTAssertFalse(isValid(artists: [Artist(name: "A", imageUrl: nil)]))
    XCTAssertFalse(isValid(artists: [Artist(name: "A", imageUrl: "")]))
    XCTAssertTrue(isValid(artists: [Artist(name: "A", imageUrl: "https://example.com/a.jpg")]))
  }

  func testSingleArtistRequiresANonEmptyName() {
    XCTAssertFalse(isValid(artists: [Artist(name: "", imageUrl: "https://example.com/a.jpg")]))
  }

  func testMultiArtistRequiresEveryNamedEntryToHaveAnImage() {
    let artists = [
      Artist(name: "A", imageUrl: "https://example.com/a.jpg"),
      Artist(name: "B", imageUrl: nil),
    ]
    XCTAssertFalse(isValid(liveType: .twoMan, artists: artists))
  }

  func testMultiArtistIgnoresBlankExtraRows() {
    // A blank row added via "+ Add artist" and never filled in shouldn't
    // permanently block save — deliberately not reproducing RN's apparent
    // `.every()`-over-blank-rows oversight.
    let artists = [
      Artist(name: "A", imageUrl: "https://example.com/a.jpg"),
      Artist(name: "", imageUrl: nil),
    ]
    XCTAssertTrue(isValid(liveType: .twoMan, artists: artists))
  }

  func testMultiArtistRequiresAtLeastOneNamedEntry() {
    let artists = [Artist(name: "", imageUrl: nil), Artist(name: "  ", imageUrl: nil)]
    XCTAssertFalse(isValid(liveType: .festival, artists: artists))
  }

  func testSportsSkipsImageRequirementAndAppleMusicEntirely() {
    XCTAssertTrue(isValid(liveType: .sports, artists: [Artist(name: "Yomiuri Giants", imageUrl: nil)]))
  }

  func testSportsStillRequiresANonEmptyName() {
    XCTAssertFalse(isValid(liveType: .sports, artists: [Artist(name: "", imageUrl: nil)]))
    XCTAssertFalse(isValid(liveType: .sports, artists: []))
  }
}
