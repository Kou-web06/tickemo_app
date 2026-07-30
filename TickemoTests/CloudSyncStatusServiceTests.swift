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
}
