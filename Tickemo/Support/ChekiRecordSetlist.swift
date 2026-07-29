import Foundation

extension CD_ChekiRecord {
  var sortedSetlistItems: [CD_SetlistItem] {
    let set = setlistItems as? Set<CD_SetlistItem> ?? []
    return set.sorted { $0.orderIndex < $1.orderIndex }
  }
}
