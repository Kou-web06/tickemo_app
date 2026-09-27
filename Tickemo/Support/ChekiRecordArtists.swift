import Foundation

extension CD_ChekiRecord {
  var artistsArray: [String]? {
    (artists as? [String]) ?? (artists as? NSArray)?.compactMap { $0 as? String }
  }

  var artistImageUrlsArray: [String]? {
    (artistImageUrls as? [String]) ?? (artistImageUrls as? NSArray)?.compactMap { $0 as? String }
  }

  /// 一覧の行に出す表示用。あだ名があればあだ名で出す（ArtistNicknames）。
  var artistDisplay: ArtistDisplayResult {
    let nicknames = ArtistNicknameStore.shared
    return ArtistDisplay.build(
      artists: artistsArray?.map(nicknames.displayName(for:)),
      fallbackArtist: artist.map(nicknames.displayName(for:))
    )
  }
}
