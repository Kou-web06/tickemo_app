import XCTest
@testable import Tickemo

final class StableLegacyIDTests: XCTestCase {
  func testParsableUUIDIsPreservedExactly() {
    let original = "6C1A6E3E-9D4B-4B2E-8C1F-2A9E0B7D5F31"
    XCTAssertEqual(StableLegacyID.uuid(for: original), UUID(uuidString: original))
  }

  func testLowercaseUUIDMapsToTheSameValueAsUppercase() {
    let upper = "6C1A6E3E-9D4B-4B2E-8C1F-2A9E0B7D5F31"
    XCTAssertEqual(StableLegacyID.uuid(for: upper.lowercased()), StableLegacyID.uuid(for: upper))
  }

  /// The property the whole upsert depends on: a legacy id that isn't a
  /// UUID must still map to the *same* UUID every run, or a re-import
  /// silently duplicates every affected record.
  func testNonUUIDIDIsDeterministic() {
    let legacyID = "1738291042311-cheki"
    XCTAssertEqual(StableLegacyID.uuid(for: legacyID), StableLegacyID.uuid(for: legacyID))
  }

  func testDifferentNonUUIDIDsDoNotCollide() {
    XCTAssertNotEqual(StableLegacyID.uuid(for: "record-1"), StableLegacyID.uuid(for: "record-2"))
  }

  func testDerivedUUIDIsWellFormed() {
    let derived = StableLegacyID.uuid(for: "not-a-uuid")
    let roundTripped = UUID(uuidString: derived.uuidString)

    XCTAssertEqual(roundTripped, derived)
    // Version 5 nibble and RFC 4122 variant bits.
    XCTAssertEqual(derived.uuid.6 & 0xF0, 0x50)
    XCTAssertEqual(derived.uuid.8 & 0xC0, 0x80)
  }

  func testEmptyIDDoesNotCrash() {
    XCTAssertEqual(StableLegacyID.uuid(for: ""), StableLegacyID.uuid(for: ""))
  }
}
