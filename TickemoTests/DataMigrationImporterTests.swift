import XCTest
import CoreData
@testable import Tickemo

/// Feeds the importer a fixture instead of reading a real AsyncStorage
/// manifest. Returning non-nil here also keeps the importer from ever
/// consulting the iCloud fallback, so these tests don't touch the ubiquity
/// container.
private struct StubLegacyStoreLoader: LegacyStoreLoading {
  let json: String?

  func loadRawStoreJSON() -> String? { json }
}

final class DataMigrationImporterTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
  }

  override func tearDown() {
    context = nil
    persistence = nil
    super.tearDown()
  }

  // MARK: - Fixtures

  private func zustandJSON(
    lives: String,
    setlists: String = "{}",
    profile: String = "null"
  ) -> String {
    """
    {"version":0,"state":{"lives":[\(lives)],"setlists":\(setlists),"userProfile":\(profile),"hasOnboarded":true}}
    """
  }

  private func live(
    id: String,
    liveName: String = "Live A",
    date: String = "2025.01.12",
    createdAt: String = "2025-01-10T00:00:00.000Z"
  ) -> String {
    """
    {"id":"\(id)","liveName":"\(liveName)","date":"\(date)","memo":"","createdAt":"\(createdAt)"}
    """
  }

  private func makeImporter(json: String) -> DataMigrationImporter {
    DataMigrationImporter(
      container: persistence.container,
      legacyStoreLoader: StubLegacyStoreLoader(json: json)
    )
  }

  private func fetchRecords() throws -> [CD_ChekiRecord] {
    try context.fetch(CD_ChekiRecord.fetchRequest())
  }

  // MARK: - Tests

  func testImportsRecordsAndSetlistItems() async throws {
    let json = zustandJSON(
      lives: live(id: "record-1"),
      setlists: """
      {"record-1":[{"id":"item-1","type":"song","songName":"Song A","orderIndex":0},\
      {"id":"item-2","type":"encore","title":"ENCORE","orderIndex":1}]}
      """
    )

    let summary = await makeImporter(json: json).run()

    XCTAssertNil(summary.error)
    XCTAssertEqual(summary.source, "AsyncStorage")
    XCTAssertEqual(summary.recordCount, 1)
    XCTAssertEqual(summary.setlistItemCount, 2)

    let records = try fetchRecords()
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.liveName, "Live A")
    XCTAssertEqual(records.first?.setlistItems?.count, 2)
  }

  /// The property everything else leans on: an interrupted or repeated
  /// import must converge, not accumulate.
  func testRunningTwiceDoesNotDuplicateAnything() async throws {
    let json = zustandJSON(
      lives: "\(live(id: "record-1")),\(live(id: "record-2", liveName: "Live B"))",
      setlists: """
      {"record-1":[{"id":"item-1","type":"song","songName":"Song A","orderIndex":0}]}
      """
    )

    let first = await makeImporter(json: json).run()
    let second = await makeImporter(json: json).run()

    XCTAssertEqual(first.recordCount, 2)
    XCTAssertEqual(second.recordCount, 0, "second run should create nothing")
    XCTAssertEqual(second.recordsAlreadyPresent, 2)
    XCTAssertEqual(second.setlistItemCount, 0, "second run should add no setlist items")

    XCTAssertEqual(try fetchRecords().count, 2)
    let items = try context.fetch(CD_SetlistItem.fetchRequest())
    XCTAssertEqual(items.count, 1)
  }

  /// Legacy ids that aren't UUIDs used to mint a fresh UUID on every run,
  /// which duplicated the record each time.
  func testNonUUIDLegacyIDsStillDeduplicateAcrossRuns() async throws {
    let json = zustandJSON(lives: live(id: "1738291042311"))

    _ = await makeImporter(json: json).run()
    _ = await makeImporter(json: json).run()

    XCTAssertEqual(try fetchRecords().count, 1)
  }

  func testExistingRecordIsNotOverwrittenByStaleLegacyValues() async throws {
    let json = zustandJSON(lives: live(id: "record-1", liveName: "Old Name"))
    _ = await makeImporter(json: json).run()

    // Stand in for an edit made in the native app after migrating.
    let record = try XCTUnwrap(try fetchRecords().first)
    record.liveName = "Edited Name"
    try context.save()

    _ = await makeImporter(json: json).run()

    XCTAssertEqual(try fetchRecords().first?.liveName, "Edited Name")
  }

  func testImportsProfileAndFillsOnlyMissingFields() async throws {
    let json = zustandJSON(
      lives: live(id: "record-1"),
      profile: """
      {"name":"Kotaro","username":"kotaro","joinedAt":"2024-01-01T00:00:00.000Z"}
      """
    )

    let summary = await makeImporter(json: json).run()

    XCTAssertTrue(summary.profileImported)
    let profiles = try context.fetch(CD_UserProfile.fetchRequest())
    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles.first?.name, "Kotaro")
    XCTAssertEqual(profiles.first?.username, "kotaro")

    // A second run must not create a second profile row.
    _ = await makeImporter(json: json).run()
    XCTAssertEqual(try context.fetch(CD_UserProfile.fetchRequest()).count, 1)
  }

  func testNoLegacyDataIsReportedAsNothingRatherThanFailure() async {
    let summary = await makeImporter(json: "").run()

    XCTAssertNil(summary.error)
    XCTAssertEqual(summary.source, "none")
    XCTAssertFalse(summary.importedAnything)
  }

  func testMalformedLegacyJSONIsReportedAsNothingRatherThanCrashing() async {
    let summary = await makeImporter(json: "{\"state\":{\"lives\":\"not-an-array\"}}").run()

    XCTAssertEqual(summary.source, "none")
    XCTAssertFalse(summary.importedAnything)
  }

  // MARK: - Late-arrival scope

  func testCreatedAfterScopeImportsOnlyNewerRecords() async throws {
    let cutoff = try XCTUnwrap(DateFormatting.isoDate(from: "2025-02-01T00:00:00.000Z"))
    let json = zustandJSON(
      lives: """
      \(live(id: "old-record", createdAt: "2025-01-10T00:00:00.000Z")),\
      \(live(id: "new-record", liveName: "Live B", createdAt: "2025-03-10T00:00:00.000Z"))
      """
    )

    let summary = await makeImporter(json: json).run(scope: .createdAfter(cutoff))

    XCTAssertEqual(summary.recordCount, 1)
    XCTAssertEqual(try fetchRecords().map(\.liveName), ["Live B"])
  }

  /// Erring towards importing is deliberate: an extra ticket is visible and
  /// deletable, a dropped one is neither.
  func testCreatedAfterScopeIncludesRecordsWithUnparseableTimestamps() async throws {
    let cutoff = try XCTUnwrap(DateFormatting.isoDate(from: "2025-02-01T00:00:00.000Z"))
    let json = zustandJSON(lives: live(id: "broken-date", createdAt: "not a date"))

    let summary = await makeImporter(json: json).run(scope: .createdAfter(cutoff))

    XCTAssertEqual(summary.recordCount, 1)
  }

  func testCreatedAfterScopeWithNothingNewSkipsWork() async throws {
    let cutoff = try XCTUnwrap(DateFormatting.isoDate(from: "2025-02-01T00:00:00.000Z"))
    let json = zustandJSON(lives: live(id: "old-record", createdAt: "2025-01-10T00:00:00.000Z"))

    let summary = await makeImporter(json: json).run(scope: .createdAfter(cutoff))

    XCTAssertEqual(summary.source, "none")
    XCTAssertNil(summary.backupURL, "the per-launch path must not write a backup each time")
    XCTAssertEqual(try fetchRecords().count, 0)
  }

  func testCreatedAfterScopeDoesNotTouchTheProfile() async throws {
    let cutoff = try XCTUnwrap(DateFormatting.isoDate(from: "2025-02-01T00:00:00.000Z"))
    let json = zustandJSON(
      lives: live(id: "new-record", createdAt: "2025-03-10T00:00:00.000Z"),
      profile: """
      {"name":"Kotaro","username":"kotaro","joinedAt":"2024-01-01T00:00:00.000Z"}
      """
    )

    _ = await makeImporter(json: json).run(scope: .createdAfter(cutoff))

    XCTAssertEqual(try context.fetch(CD_UserProfile.fetchRequest()).count, 0)
  }
}
