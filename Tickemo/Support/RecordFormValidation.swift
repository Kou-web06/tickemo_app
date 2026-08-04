import Foundation

/// Pure save-gating logic for RecordFormView, split out so it's unit
/// testable without a SwiftUI/Core Data context. Matches RN's
/// LiveEditScreen.tsx `isFormValid`: live name and venue always required;
/// `sports` just needs a non-empty free-text name (no Apple Music search);
/// every other live type needs at least one named artist, and every named
/// artist must have a non-empty imageUrl (i.e. picked from search, not
/// free-typed) — blank/unnamed extra rows are ignored rather than blocking
/// save, a deliberate correction of what reads as an RN-side oversight (see
/// RecordFormView's doc comment).
enum RecordFormValidation {
  struct ArtistInput {
    let name: String
    let imageUrl: String?

    init(name: String, imageUrl: String? = nil) {
      self.name = name
      self.imageUrl = imageUrl
    }
  }

  static func isValid(liveName: String, venue: String, liveType: LiveType, artistEntries: [ArtistInput]) -> Bool {
    guard !liveName.trimmingCharacters(in: .whitespaces).isEmpty,
          !venue.trimmingCharacters(in: .whitespaces).isEmpty
    else { return false }

    if liveType == .sports {
      let name = artistEntries.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
      return !name.isEmpty
    }

    let named = artistEntries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !named.isEmpty else { return false }
    return named.allSatisfy { !($0.imageUrl ?? "").isEmpty }
  }
}
