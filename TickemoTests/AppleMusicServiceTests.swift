import XCTest
@testable import Tickemo

final class AppleMusicServiceTests: XCTestCase {
  func testResolvesWidthAndHeightPlaceholders() {
    let template = "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/{w}x{h}bb.jpg"
    XCTAssertEqual(
      AppleMusicService.resolvedArtworkURL(template, size: 800),
      "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/800x800bb.jpg"
    )
  }

  func testNonTemplateURLPassesThroughUnchanged() {
    let resolved = "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/600x600bb.jpg"
    XCTAssertEqual(AppleMusicService.resolvedArtworkURL(resolved, size: 80), resolved)
  }

  func testEmptyURLPassesThroughUnchanged() {
    XCTAssertEqual(AppleMusicService.resolvedArtworkURL("", size: 80), "")
  }
}
