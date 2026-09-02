import XCTest
@testable import Tickemo

/// プレイリスト作成は Apple Music 側が応答を返さないまま固まることが
/// あるので、打ち切り機構そのものが本当に動くかをここで担保する
/// （MusicKit を実際に叩く経路はシミュレータでは通せないため）。
final class ApplePlaylistExporterTimeoutTests: XCTestCase {
  func testReturnsTheValueWhenTheOperationFinishesInTime() async throws {
    let value = try await ApplePlaylistExporter.withTimeout(seconds: 5) { "done" }
    XCTAssertEqual(value, "done")
  }

  func testThrowsTimeoutErrorWhenTheOperationOverruns() async {
    do {
      _ = try await ApplePlaylistExporter.withTimeout(seconds: 0.2) {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return "done"
      }
      XCTFail("タイムアウトせずに返ってきた")
    } catch is ApplePlaylistExporter.TimeoutError {
      // 期待どおり
    } catch {
      XCTFail("想定外のエラー: \(error)")
    }
  }

  /// 本命のケース。`Task.sleep` はキャンセルに応じて終われるので、
  /// それだけで試すと素通りしてしまう（実際、最初の実装はこのテストを
  /// 通ったのに実機のハングでは脱出できなかった）。MusicKit が固まる
  /// ときは continuation が二度と再開されず、キャンセルにも応じない。
  /// それを再現するため、絶対に再開しない continuation で待たせる。
  func testTimesOutEvenWhenTheOperationNeverCompletesAndIgnoresCancellation() async {
    let started = expectation(description: "operation started")
    do {
      _ = try await ApplePlaylistExporter.withTimeout(seconds: 0.3) {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
          started.fulfill()
        }
        return "never"
      }
      XCTFail("固まったまま返ってきた")
    } catch is ApplePlaylistExporter.TimeoutError {
      // 期待どおり
    } catch {
      XCTFail("想定外のエラー: \(error)")
    }
    await fulfillment(of: [started], timeout: 1)
  }

  func testPropagatesTheOperationsOwnErrorRatherThanMaskingItAsATimeout() async {
    struct Boom: Error {}
    do {
      _ = try await ApplePlaylistExporter.withTimeout(seconds: 5) { throw Boom() }
      XCTFail("エラーが伝播しなかった")
    } catch is Boom {
      // 期待どおり
    } catch {
      XCTFail("想定外のエラー: \(error)")
    }
  }
}
