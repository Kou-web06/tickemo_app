import Foundation

extension CD_ChekiRecord {
  var sortedImages: [CD_LiveImage] {
    let set = images as? Set<CD_LiveImage> ?? []
    return set.sorted { $0.orderIndex < $1.orderIndex }
  }

  var coverImage: CD_LiveImage? {
    sortedImages.first { $0.orderIndex == 0 } ?? sortedImages.first
  }

  var coverImageData: Data? {
    coverImage?.data
  }

  /// 表紙として保存された画像（`orderIndex == 0`）だけ。`coverImage` は
  /// 表紙が無いと写真の1枚目で代用するので表示用にはよいが、編集フォームが
  /// それを表紙として読み書きすると、保存のたびに写真の1枚目が表紙へ
  /// 移ってしまう。編集ではこちらを使う。
  var storedCoverImage: CD_LiveImage? {
    sortedImages.first { $0.orderIndex == 0 }
  }

  /// The live's photo gallery — everything past the single cover/
  /// player-photo slot at `orderIndex == 0`. Originally sports-only "Game
  /// Photos" (ports `LiveEditScreen.tsx`'s `imageUrls` grid), now available
  /// for every live type (limits in `LivePhotoGallery`). No schema change
  /// needed: `images` was already a to-many relationship ordered by
  /// `orderIndex`, so this is just a second read of the same collection.
  var galleryImages: [CD_LiveImage] {
    sortedImages.filter { $0.orderIndex > 0 }
  }
}
