import Foundation

/// Port of `utils/artistDisplay.ts`'s `buildTicketArtistDisplay`.
struct ArtistDisplayResult {
  let mainText: String
  let showAndMore: Bool
}

enum ArtistDisplay {
  private static let maxSafeArtistTextLength = 25

  static func build(artists: [String]?, fallbackArtist: String?) -> ArtistDisplayResult {
    let source = (artists?.isEmpty == false ? artists! : [fallbackArtist ?? ""])
    let normalized = source
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    guard !normalized.isEmpty else {
      return ArtistDisplayResult(mainText: "-", showAndMore: false)
    }
    guard normalized.count > 1 else {
      return ArtistDisplayResult(mainText: normalized[0], showAndMore: false)
    }

    let firstTwoJoined = "\(normalized[0]) / \(normalized[1])"
    let shouldUseSafetyFallback = firstTwoJoined.count >= maxSafeArtistTextLength

    if normalized.count == 2 {
      return ArtistDisplayResult(
        mainText: shouldUseSafetyFallback ? normalized[0] : firstTwoJoined,
        showAndMore: shouldUseSafetyFallback
      )
    }

    return ArtistDisplayResult(
      mainText: shouldUseSafetyFallback ? normalized[0] : firstTwoJoined,
      showAndMore: true
    )
  }
}
