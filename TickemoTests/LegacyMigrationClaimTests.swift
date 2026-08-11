import XCTest
@testable import Tickemo

final class LegacyMigrationClaimTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "LegacyMigrationClaimTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testNoClaimInitially() {
    let claim = LegacyMigrationClaim(ubiquitous: InMemoryClaimStore(), userDefaults: defaults)
    XCTAssertNil(claim.currentClaim())
    XCTAssertNil(claim.localClaim)
  }

  func testClaimIsReadableBackAndMirroredLocally() {
    let store = InMemoryClaimStore()
    let claim = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults)

    let written = claim.claim(source: "AsyncStorage", recordCount: 42)

    XCTAssertEqual(claim.currentClaim(), written)
    XCTAssertEqual(claim.localClaim, written)
    XCTAssertEqual(written.recordCount, 42)
    XCTAssertEqual(written.source, "AsyncStorage")
  }

  /// The reinstall case: `UserDefaults` is gone but iCloud still remembers,
  /// which is the whole reason the claim doesn't live in `UserDefaults`.
  func testClaimFromAnotherInstallIsSeenWithoutLocalMirror() {
    let store = InMemoryClaimStore()
    LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults)
      .claim(source: "AsyncStorage", recordCount: 7)

    let freshInstallDefaults = UserDefaults(suiteName: "\(suiteName!).fresh")!
    defer { freshInstallDefaults.removePersistentDomain(forName: "\(suiteName!).fresh") }

    let afterReinstall = LegacyMigrationClaim(ubiquitous: store, userDefaults: freshInstallDefaults)
    XCTAssertNil(afterReinstall.localClaim, "precondition: the local mirror should be gone")

    let seen = afterReinstall.currentClaim()
    XCTAssertEqual(seen?.recordCount, 7)
    // Having read it once, the fast path should now work offline too.
    XCTAssertEqual(afterReinstall.localClaim?.recordCount, 7)
  }

  /// Losing iCloud access must not re-arm the importer on a device that has
  /// already migrated.
  func testLocalMirrorSurvivesUbiquitousStoreGoingEmpty() {
    let store = InMemoryClaimStore()
    let claim = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults)
    claim.claim(source: "AsyncStorage", recordCount: 3)

    let offline = LegacyMigrationClaim(ubiquitous: InMemoryClaimStore(), userDefaults: defaults)
    XCTAssertEqual(offline.currentClaim()?.recordCount, 3)
  }

  func testCurrentClaimRefreshesFromICloudBeforeReading() {
    let store = InMemoryClaimStore()
    let claim = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults)

    _ = claim.currentClaim()

    XCTAssertEqual(store.synchronizeCallCount, 1)
  }

  func testDeviceIDIsStableAcrossInstances() {
    let store = InMemoryClaimStore()
    let first = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults).deviceID
    let second = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults).deviceID

    XCTAssertEqual(first, second)
    XCTAssertFalse(first.isEmpty)
  }

  func testClearRemovesBothCopies() {
    let store = InMemoryClaimStore()
    let claim = LegacyMigrationClaim(ubiquitous: store, userDefaults: defaults)
    claim.claim(source: "AsyncStorage", recordCount: 1)

    claim.clear()

    XCTAssertNil(claim.currentClaim())
    XCTAssertNil(claim.localClaim)
  }
}
