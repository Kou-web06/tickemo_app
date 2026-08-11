import XCTest
import CoreData
@testable import Tickemo

final class CloudSyncStatusServiceTests: XCTestCase {
  func testInProgressEventReportsSyncing() {
    let event = SyncEventSnapshot(type: .import, endDate: nil, succeeded: false)
    let result = CloudSyncStatusService.reduce(current: (.notSyncedYet, nil), event: event)

    XCTAssertEqual(result.status, .syncing)
    XCTAssertNil(result.lastSuccess)
  }

  func testSuccessfulCompletedEventReportsSyncedAndUpdatesTimestamp() {
    let endDate = Date(timeIntervalSince1970: 1_700_000_000)
    let event = SyncEventSnapshot(type: .export, endDate: endDate, succeeded: true)
    let result = CloudSyncStatusService.reduce(current: (.syncing, nil), event: event)

    XCTAssertEqual(result.status, .synced)
    XCTAssertEqual(result.lastSuccess, endDate)
  }

  func testFailedCompletedEventLeavesCurrentStateUnchanged() {
    let previousSuccess = Date(timeIntervalSince1970: 1_600_000_000)
    let event = SyncEventSnapshot(type: .import, endDate: Date(), succeeded: false)
    let result = CloudSyncStatusService.reduce(current: (.synced, previousSuccess), event: event)

    XCTAssertEqual(result.status, .synced)
    XCTAssertEqual(result.lastSuccess, previousSuccess)
  }

  func testSetupEventTypeIsIgnored() {
    let event = SyncEventSnapshot(type: .setup, endDate: nil, succeeded: false)
    let result = CloudSyncStatusService.reduce(current: (.notSyncedYet, nil), event: event)

    XCTAssertEqual(result.status, .notSyncedYet)
    XCTAssertNil(result.lastSuccess)
  }

  // MARK: - Event log

  /// A failed export deliberately doesn't regress the headline status, so
  /// the log is the only place the failure survives. If it didn't, "sync
  /// works" and "every export is rejected" would look identical.
  func testFailedEventKeepsStatusButIsStillDistinguishable() {
    let failure = SyncEventSnapshot(
      type: .export,
      endDate: Date(),
      succeeded: false,
      startDate: Date(),
      errorDescription: "schema not deployed"
    )
    let result = CloudSyncStatusService.reduce(current: (.synced, nil), event: failure)

    XCTAssertEqual(result.status, .synced, "status should not regress on a transient failure")
    XCTAssertEqual(failure.errorDescription, "schema not deployed")
  }

  func testEventLabelsCoverEveryMirroringType() {
    XCTAssertEqual(SyncEventLogEntry.label(for: .setup), "setup")
    XCTAssertEqual(SyncEventLogEntry.label(for: .import), "import")
    XCTAssertEqual(SyncEventLogEntry.label(for: .export), "export")
  }

  func testUnfinishedEntryIsReportedAsInProgress() {
    let entry = SyncEventLogEntry(
      typeLabel: "export",
      startDate: Date(),
      endDate: nil,
      succeeded: false,
      errorDescription: nil
    )

    XCTAssertFalse(entry.isFinished)
  }
}
