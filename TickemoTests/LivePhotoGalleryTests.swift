import XCTest
import CoreData
@testable import Tickemo

final class LivePhotoGalleryTests: XCTestCase {
  func testFreeUsersCanAddUpToThreePhotos() {
    XCTAssertEqual(LivePhotoGallery.limit(isPremium: false, liveType: .oneMan), 3)
    XCTAssertEqual(LivePhotoGallery.remaining(currentCount: 0, isPremium: false, liveType: .festival), 3)
    XCTAssertEqual(LivePhotoGallery.remaining(currentCount: 2, isPremium: false, liveType: .oneMan), 1)
    XCTAssertEqual(LivePhotoGallery.remaining(currentCount: 3, isPremium: false, liveType: .oneMan), 0)
  }

  func testSportsKeepsTheSixPhotosFreeUsersHadBefore() {
    XCTAssertEqual(LivePhotoGallery.limit(isPremium: false, liveType: .sports), 6)
  }

  func testPlusUsersGetTheLargerLimitForEveryLiveType() {
    for type in LiveType.allCases {
      XCTAssertEqual(LivePhotoGallery.limit(isPremium: true, liveType: type), 20)
    }
  }

  func testRemainingNeverGoesNegativeWhenAlreadyOverTheLimit() {
    // Plus 解約後など、上限を超えて既に入っている写真があっても消さない前提
    XCTAssertEqual(LivePhotoGallery.remaining(currentCount: 12, isPremium: false, liveType: .oneMan), 0)
  }

  /// 表紙なしで写真だけある記録: 表示用の coverImage は写真1枚目で代用するが、
  /// 編集フォームが使う storedCoverImage は nil（写真を表紙へ移さないため）
  func testStoredCoverImageIgnoresTheGalleryFallback() {
    let context = PersistenceController(inMemory: true).container.viewContext
    let record = CD_ChekiRecord(context: context)
    record.id = UUID()
    let photo = CD_LiveImage(context: context)
    photo.id = UUID()
    photo.orderIndex = 1
    photo.data = Data([0x01])
    photo.record = record

    XCTAssertEqual(record.coverImage, photo)
    XCTAssertNil(record.storedCoverImage)
    XCTAssertEqual(record.galleryImages, [photo])

    let cover = CD_LiveImage(context: context)
    cover.id = UUID()
    cover.orderIndex = 0
    cover.record = record
    XCTAssertEqual(record.storedCoverImage, cover)
    XCTAssertEqual(record.coverImage, cover)
  }
}
