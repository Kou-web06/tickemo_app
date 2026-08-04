import Foundation

extension CD_ChekiRecord {
  var artistsArray: [String]? {
    (artists as? [String]) ?? (artists as? NSArray)?.compactMap { $0 as? String }
  }

  var artistImageUrlsArray: [String]? {
    (artistImageUrls as? [String]) ?? (artistImageUrls as? NSArray)?.compactMap { $0 as? String }
  }

  var artistDisplay: ArtistDisplayResult {
    ArtistDisplay.build(artists: artistsArray, fallbackArtist: artist)
  }
}
