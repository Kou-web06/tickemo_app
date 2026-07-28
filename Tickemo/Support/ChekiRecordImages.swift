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
}
