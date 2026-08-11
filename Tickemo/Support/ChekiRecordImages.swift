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

  /// Sports lives' "Game Photos" gallery (up to 6, ports
  /// `LiveEditScreen.tsx`'s sports-only `imageUrls` grid) — everything past
  /// the single cover/player-photo slot at `orderIndex == 0`. No schema
  /// change needed: `images` was already a to-many relationship ordered by
  /// `orderIndex`, so this is just a second read of the same collection.
  var galleryImages: [CD_LiveImage] {
    sortedImages.filter { $0.orderIndex > 0 }
  }
}
