import XCTest
import CoreData
@testable import Tickemo

/// Exercised with `cloudKitAvailable: false`, which makes the sweeper fall
/// back to object-ID ordering. That's the same code path as the CloudKit
/// one apart from where the tiebreak string comes from, and it's the only
/// one reachable without a live iCloud account.
final class DuplicateRecordSweeperTests: XCTestCase {
  private var persistence: PersistenceController!
  private var context: NSManagedObjectContext!
  private var sweeper: DuplicateRecordSweeper!

  override func setUp() {
    super.setUp()
    persistence = PersistenceController(inMemory: true)
    context = persistence.container.viewContext
    sweeper = DuplicateRecordSweeper(container: persistence.container, cloudKitAvailable: false)
  }

  override func tearDown() {
    sweeper = nil
    context = nil
    persistence = nil
    super.tearDown()
  }

  @discardableResult
  private func makeRecord(id: UUID, liveName: String = "Live A") -> CD_ChekiRecord {
    let record = CD_ChekiRecord(context: context)
    record.id = id
    record.liveName = liveName
    record.date = "2025.01.12"
    return record
  }

  @discardableResult
  private func makeImage(on record: CD_ChekiRecord, legacyPath: String?, order: Int16 = 0) -> CD_LiveImage {
    let image = CD_LiveImage(context: context)
    image.id = UUID()
    image.legacyRelativePath = legacyPath
    image.orderIndex = order
    image.data = Data([0x01, 0x02])
    image.record = record
    return image
  }

  @discardableResult
  private func makeSetlistItem(on record: CD_ChekiRecord, id: UUID, order: Int32 = 0) -> CD_SetlistItem {
    let item = CD_SetlistItem(context: context)
    item.id = id
    item.kind = "song"
    item.songName = "Song A"
    item.orderIndex = order
    item.record = record
    return item
  }

  // MARK: - Records

  func testCollapsesTwoRecordsSharingALegacyID() async throws {
    let sharedID = UUID()
    makeRecord(id: sharedID)
    makeRecord(id: sharedID)
    try context.save()

    let summary = try await sweeper.sweep()
    context.refreshAllObjects()

    XCTAssertEqual(summary.deletedRecords, 1)
    XCTAssertEqual(summary.mergedRecordGroups, 1)
    XCTAssertEqual(try context.fetch(CD_ChekiRecord.fetchRequest()).count, 1)
  }

  func testDistinctRecordsAreLeftAlone() async throws {
    makeRecord(id: UUID(), liveName: "Live A")
    makeRecord(id: UUID(), liveName: "Live B")
    try context.save()

    let summary = try await sweeper.sweep()

    XCTAssertFalse(summary.didChangeAnything)
    XCTAssertEqual(try context.fetch(CD_ChekiRecord.fetchRequest()).count, 2)
  }

  /// `images` cascades on delete, so a merge that deleted the loser without
  /// re-parenting first would take the user's photo with it.
  func testLoserImagesAreMovedToTheSurvivorRatherThanDeleted() async throws {
    let sharedID = UUID()
    let first = makeRecord(id: sharedID)
    let second = makeRecord(id: sharedID)
    makeImage(on: first, legacyPath: "Tickemo/a.jpg")
    makeImage(on: second, legacyPath: "Tickemo/b.jpg")
    try context.save()

    _ = try await sweeper.sweep()
    context.refreshAllObjects()

    let records = try context.fetch(CD_ChekiRecord.fetchRequest())
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(try context.fetch(CD_LiveImage.fetchRequest()).count, 2)
    XCTAssertEqual(records.first?.images?.count, 2)
  }

  func testLoserSetlistItemsAreMovedToTheSurvivor() async throws {
    let sharedID = UUID()
    let first = makeRecord(id: sharedID)
    let second = makeRecord(id: sharedID)
    makeSetlistItem(on: first, id: UUID(), order: 0)
    makeSetlistItem(on: second, id: UUID(), order: 1)
    try context.save()

    _ = try await sweeper.sweep()
    context.refreshAllObjects()

    let records = try context.fetch(CD_ChekiRecord.fetchRequest())
    XCTAssertEqual(records.first?.setlistItems?.count, 2)
    XCTAssertEqual(try context.fetch(CD_SetlistItem.fetchRequest()).count, 2)
  }

  func testRecordWithoutAnIDIsGivenOne() async throws {
    let record = CD_ChekiRecord(context: context)
    record.liveName = "No ID"
    try context.save()

    _ = try await sweeper.sweep()
    context.refreshAllObjects()

    XCTAssertNotNil(try context.fetch(CD_ChekiRecord.fetchRequest()).first?.id)
  }

  // MARK: - Children on a single record

  /// The realistic single-device case: CloudKit delivers the record before
  /// its images, so the local import re-adds images it couldn't yet see.
  func testDuplicateImagesOnOneRecordAreCollapsedByLegacyPath() async throws {
    let record = makeRecord(id: UUID())
    makeImage(on: record, legacyPath: "Tickemo/a.jpg")
    makeImage(on: record, legacyPath: "Tickemo/a.jpg")
    makeImage(on: record, legacyPath: "Tickemo/b.jpg")
    try context.save()

    let summary = try await sweeper.sweep()
    context.refreshAllObjects()

    XCTAssertEqual(summary.deletedImages, 1)
    XCTAssertEqual(try context.fetch(CD_LiveImage.fetchRequest()).count, 2)
  }

  func testNativelyCreatedImagesWithoutLegacyPathsAreNotTreatedAsDuplicates() async throws {
    let record = makeRecord(id: UUID())
    makeImage(on: record, legacyPath: nil)
    makeImage(on: record, legacyPath: nil)
    try context.save()

    let summary = try await sweeper.sweep()

    XCTAssertEqual(summary.deletedImages, 0)
    XCTAssertEqual(try context.fetch(CD_LiveImage.fetchRequest()).count, 2)
  }

  func testDuplicateSetlistItemsAreCollapsedByID() async throws {
    let record = makeRecord(id: UUID())
    let sharedItemID = UUID()
    makeSetlistItem(on: record, id: sharedItemID)
    makeSetlistItem(on: record, id: sharedItemID)
    makeSetlistItem(on: record, id: UUID(), order: 1)
    try context.save()

    let summary = try await sweeper.sweep()
    context.refreshAllObjects()

    XCTAssertEqual(summary.deletedSetlistItems, 1)
    XCTAssertEqual(try context.fetch(CD_SetlistItem.fetchRequest()).count, 2)
  }

  // MARK: - Profile

  func testDuplicateProfilesAreMergedWithGapsFilled() async throws {
    let first = CD_UserProfile(context: context)
    first.id = UUID()
    first.name = "Kotaro"

    let second = CD_UserProfile(context: context)
    second.id = UUID()
    second.name = ""
    second.username = "kotaro"
    second.avatarImageData = Data([0x09])
    try context.save()

    let summary = try await sweeper.sweep()
    context.refreshAllObjects()

    XCTAssertEqual(summary.deletedProfiles, 1)
    let profiles = try context.fetch(CD_UserProfile.fetchRequest())
    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles.first?.name, "Kotaro")
    XCTAssertEqual(profiles.first?.username, "kotaro", "the survivor should inherit fields it lacked")
    XCTAssertEqual(profiles.first?.avatarImageData, Data([0x09]))
  }

  func testSweepingAnEmptyStoreIsANoOp() async throws {
    let summary = try await sweeper.sweep()

    XCTAssertFalse(summary.didChangeAnything)
    XCTAssertEqual(summary.deferredGroups, 0)
  }

  func testSweepIsIdempotent() async throws {
    let sharedID = UUID()
    makeRecord(id: sharedID)
    makeRecord(id: sharedID)
    try context.save()

    _ = try await sweeper.sweep()
    let second = try await sweeper.sweep()

    XCTAssertFalse(second.didChangeAnything)
  }
}
