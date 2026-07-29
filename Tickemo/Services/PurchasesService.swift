import RevenueCat
import Foundation

enum MembershipType: String {
  case free, plus, lifetime
}

/// Shared, cross-screen reactive purchase state — unlike AppleMusicService/
/// MusicKitService (deliberately view-local, stateless-ish instances),
/// entitlement status is genuinely cross-cutting (the list's free-tier gate,
/// the paywall, and anything else that cares about premium status all need
/// the same answer), so this follows PersistenceController's established
/// `static let shared` singleton pattern instead.
@Observable
final class PurchasesService {
  static let shared = PurchasesService()

  static let entitlementID = "Tickemo Plus"
  private static let apiKey = "appl_hRVOeiwkPvuPNjTIAiZFuKvqELh"
  /// The exact UserDefaults key RevenueCat's native SDK (5.59.0, same
  /// version already shipping in the RN app) caches its generated anonymous
  /// App User ID under — confirmed by reading
  /// ios/Pods/RevenueCat/Sources/Caching/DeviceCache.swift's `CacheKeys`.
  /// Since this is a plain UserDefaults.standard key in the same app
  /// sandbox (same bundle ID), the already-shipping RN build has already
  /// written it — reading it here before configuring lets the native SDK
  /// continue as the same RevenueCat customer instead of minting a new
  /// anonymous identity.
  private static let cachedAppUserIDKey = "com.revenuecat.userdefaults.appUserID.new"

  private(set) var isPremium = false
  private(set) var membershipType: MembershipType = .free
  private(set) var activeEntitlementIds: [String] = []
  private(set) var isConfigured = false

  private init() {}

  func configure() async {
    guard !isConfigured else { return }
    let cachedAppUserID = UserDefaults.standard.string(forKey: Self.cachedAppUserIDKey)
    Purchases.configure(withAPIKey: Self.apiKey, appUserID: cachedAppUserID)
    isConfigured = true

    // Safety net regardless of whether the cached-ID continuity above
    // worked: re-derive entitlements from the App Store receipt itself.
    _ = try? await Purchases.shared.restorePurchases()
    await refreshCustomerInfo()
  }

  @discardableResult
  func refreshCustomerInfo() async -> CustomerInfo? {
    guard let info = try? await Purchases.shared.customerInfo() else {
      applyStatus(isPremium: false, membershipType: .free, activeEntitlementIds: [])
      return nil
    }
    applyStatus(from: info)
    return info
  }

  func fetchOfferings() async throws -> Offerings {
    try await Purchases.shared.offerings()
  }

  func purchase(package: Package) async throws -> PurchaseResultData {
    let result = try await Purchases.shared.purchase(package: package)
    if !result.userCancelled {
      applyStatus(from: result.customerInfo)
    }
    return result
  }

  @discardableResult
  func restorePurchases() async throws -> CustomerInfo {
    let info = try await Purchases.shared.restorePurchases()
    applyStatus(from: info)
    return info
  }

  @discardableResult
  func syncPurchases() async throws -> CustomerInfo {
    let info = try await Purchases.shared.syncPurchases()
    applyStatus(from: info)
    return info
  }

  // MARK: - Status derivation (ports lib/revenuecat.ts's
  // getPremiumStatusFromCustomerInfo 1:1)

  private func applyStatus(from info: CustomerInfo) {
    let active = info.entitlements.active
    let ids = Array(active.keys)
    let premium = !ids.isEmpty
    let chosen = active[Self.entitlementID] ?? ids.first.flatMap { active[$0] }
    let productID = chosen?.productIdentifier.lowercased() ?? ""

    var type: MembershipType = .free
    if premium {
      let lifetimeMarkers = ["lifetime", "permanent", "buyout", "one_time", "onetime"]
      type = lifetimeMarkers.contains(where: productID.contains) ? .lifetime : .plus
    }
    applyStatus(isPremium: premium, membershipType: type, activeEntitlementIds: ids)
  }

  private func applyStatus(isPremium: Bool, membershipType: MembershipType, activeEntitlementIds: [String]) {
    self.isPremium = isPremium
    self.membershipType = membershipType
    self.activeEntitlementIds = activeEntitlementIds
  }
}
