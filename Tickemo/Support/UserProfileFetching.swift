import CoreData

enum UserProfileFetching {
  /// There's no CD_UserProfile row until either the Phase 1 migration
  /// importer created one (if the RN user had a profile) or the user opens
  /// Settings for the first time on a fresh install — this covers both.
  static func fetchOrCreateUserProfile(context: NSManagedObjectContext) -> CD_UserProfile {
    let request = CD_UserProfile.fetchRequest()
    request.fetchLimit = 1
    if let existing = try? context.fetch(request).first {
      return existing
    }
    let profile = CD_UserProfile(context: context)
    profile.id = UUID()
    profile.joinedAt = DateFormatting.isoNow()
    return profile
  }
}
