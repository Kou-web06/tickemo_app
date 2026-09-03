import XCTest
@testable import Tickemo

/// 保存直前に走る出演者タグの整形。ワンマンのカバー曲が「原曲の
/// アーティスト」ではなく「実際に歌った人」で記録されるかどうかが
/// ここで決まる。
final class SetlistDraftPerformerNormalizationTests: XCTestCase {
  private func song(_ name: String, artist: String?, performer: String?) -> SetlistDraftItem {
    SetlistDraftItem(
      id: UUID(),
      kind: .song,
      songName: name,
      artistName: artist,
      performerName: performer
    )
  }

  private func mc(performer: String? = nil) -> SetlistDraftItem {
    SetlistDraftItem(id: UUID(), kind: .mc, performerName: performer)
  }

  /// ワンマンのカバー曲。音源は MyGO!!!!! でも、歌ったのは出演者の sumimi。
  /// 出演者欄に触れていなくても sumimi が入る。
  func testSingleArtistLiveTagsEverySongWithThatArtist() {
    let normalized = SetlistDraftItem.normalizingPerformers(
      [
        song("ハピネス", artist: "sumimi", performer: nil),
        song("詩超絆", artist: "MyGO!!!!!", performer: nil),
      ],
      artistNames: ["sumimi"]
    )
    XCTAssertEqual(normalized.map(\.performerName), ["sumimi", "sumimi"])
  }

  /// 対バンでは誰が演奏したか推測できないので、未指定は未指定のまま残す。
  func testMultiArtistLiveDoesNotGuessAnUnsetPerformer() {
    let normalized = SetlistDraftItem.normalizingPerformers(
      [song("詩超絆", artist: "MyGO!!!!!", performer: nil)],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertNil(normalized[0].performerName)
  }

  func testExplicitPerformerSurvivesAndAdoptsTheRegisteredSpelling() {
    let normalized = SetlistDraftItem.normalizingPerformers(
      [song("詩超絆", artist: "MyGO!!!!!", performer: "SUMIMI")],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertEqual(normalized[0].performerName, "sumimi")
  }

  /// アーティスト欄から消された出演者のタグは落ちる。単独公演なら
  /// 残った1組で埋め直され、対バンなら未指定に戻る。
  func testUnregisteredPerformerIsDroppedAndBackfilledOnlyWhenOneArtistRemains() {
    let oneArtist = SetlistDraftItem.normalizingPerformers(
      [song("詩超絆", artist: "MyGO!!!!!", performer: "Roselia")],
      artistNames: ["sumimi"]
    )
    XCTAssertEqual(oneArtist[0].performerName, "sumimi")

    let twoArtists = SetlistDraftItem.normalizingPerformers(
      [song("詩超絆", artist: "MyGO!!!!!", performer: "Roselia")],
      artistNames: ["sumimi", "MyGO!!!!!"]
    )
    XCTAssertNil(twoArtists[0].performerName)
  }

  /// MC / アンコールは表示に出ないので自動補完しない。登録済みの名前が
  /// 引き継がれていればそれは残す。
  func testMarkersAreNeverBackfilled() {
    let normalized = SetlistDraftItem.normalizingPerformers(
      [mc(), mc(performer: "sumimi"), mc(performer: "Roselia")],
      artistNames: ["sumimi"]
    )
    XCTAssertEqual(normalized.map(\.performerName), [nil, "sumimi", nil])
  }

  func testNoNamedArtistLeavesEverythingUntagged() {
    let normalized = SetlistDraftItem.normalizingPerformers(
      [song("ハピネス", artist: "sumimi", performer: "sumimi")],
      artistNames: ["   "]
    )
    XCTAssertNil(normalized[0].performerName)
  }
}
