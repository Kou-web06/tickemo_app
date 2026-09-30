import Foundation

/// ライブ写真（表紙以外の `CD_LiveImage`、`orderIndex >= 1`）の枚数上限。
///
/// もともとスポーツの「観戦写真」（RN の `imageUrls`、最大6枚）専用だった
/// 枠を、全ライブ種別の「写真」に広げた。無料は3枚、Plus は20枚まで。
/// スポーツだけは RN から引き継いだ「無料でも6枚」を削らないよう据え置く。
/// 上限は「追加できるか」の判定にだけ使い、上限を超えて既に入っている
/// 写真（Plus 解約後など）を消すことはしない。
enum LivePhotoGallery {
  static let freeLimit = 3
  static let sportsFreeLimit = 6
  static let plusLimit = 20

  static func limit(isPremium: Bool, liveType: LiveType) -> Int {
    if isPremium { return plusLimit }
    return liveType == .sports ? sportsFreeLimit : freeLimit
  }

  /// あと何枚追加できるか（0 なら追加不可）
  static func remaining(currentCount: Int, isPremium: Bool, liveType: LiveType) -> Int {
    max(0, limit(isPremium: isPremium, liveType: liveType) - currentCount)
  }
}
