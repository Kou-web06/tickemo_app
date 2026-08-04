import SwiftUI
import RevenueCat

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports screens/PaywallScreen.tsx: a single lifetime one-time-purchase
/// product ("Tickemo Plus"), no subscription tiers. Presented as a plain
/// SwiftUI .sheet (rounded top corners + backdrop come for free, no custom
/// modal chrome needed to match the RN bottom-sheet look).
struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var package: Package?
  @State private var isLoadingOfferings = true
  @State private var isPurchasing = false
  @State private var isRestoring = false
  @State private var alertMessage: String?

  private let benefits: [(icon: HugeIcon, title: String, description: String)] = [
    (HugeIcons.infinity01, "Unlimited Tickets", "Add as many live tickets as you want."),
    (HugeIcons.playList, "Full Setlist Access", "Save and edit setlists for every show."),
    (HugeIcons.favourite, "Support Development", "Help keep Tickemo growing."),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          VStack(spacing: 8) {
            HStack(spacing: 8) {
              Text("Tickemo")
                .font(.system(size: 28, weight: .heavy))
              Text("Plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accentPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(accentPurple, lineWidth: 1.5))
            }
            Text("Unlock everything Tickemo has to offer.")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(.top, 12)

          VStack(spacing: 16) {
            ForEach(benefits, id: \.title) { benefit in
              HStack(spacing: 12) {
                HugeIconView(icon: benefit.icon, size: 20)
                  .foregroundStyle(.primary)
                  .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                  Text(benefit.title).font(.system(size: 15, weight: .bold))
                  Text(benefit.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
            }
          }
          .padding(.horizontal, 8)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
      }
      .safeAreaInset(edge: .bottom) {
        bottomPanel
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            HugeIconView(icon: HugeIcons.cancel01, size: 17)
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button(isRestoring ? "Restoring…" : "Restore") {
            Task { await handleRestore() }
          }
          .disabled(isRestoring)
          .font(.system(size: 13, weight: .semibold))
        }
      }
      .task {
        await loadOfferings()
      }
      .alert("お知らせ", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK") {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }

  private var bottomPanel: some View {
    VStack(spacing: 10) {
      HStack(alignment: .lastTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Lifetime Access").font(.system(size: 14, weight: .bold))
          Text("One-time purchase, no subscription").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Spacer()
        if let priceString = package?.storeProduct.localizedPriceString {
          Text(priceString).font(.system(size: 18, weight: .heavy))
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(accentPurple.opacity(0.08))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(accentPurple, lineWidth: 2))
      .clipShape(RoundedRectangle(cornerRadius: 20))

      Button {
        Task { await handlePurchase() }
      } label: {
        HStack {
          if isPurchasing {
            ProgressView().tint(.white)
          }
          Text(isPurchasing ? "処理中…" : "購入する")
            .font(.system(size: 16, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .background(accentPurple)
      .foregroundStyle(.white)
      .clipShape(Capsule())
      .disabled(isPurchasing || isLoadingOfferings || package == nil)
    }
    .padding(16)
    .background(.regularMaterial)
  }

  // MARK: - Offerings

  private func loadOfferings() async {
    isLoadingOfferings = true
    defer { isLoadingOfferings = false }

    guard let offerings = try? await PurchasesService.shared.fetchOfferings() else { return }
    let packages = offerings.current?.availablePackages ?? []

    let preferredID = EarlyOfferService.isWithinEarlyWindow() ? "tickemo_plus_lifetime" : "tickemo_plus_lifetime_usual"
    package = packages.first {
      $0.identifier.lowercased() == preferredID || $0.storeProduct.productIdentifier.lowercased() == preferredID
    } ?? packages.first { $0.packageType == .lifetime } ?? packages.first
  }

  // MARK: - Purchase (ports PaywallScreen.tsx's handlePurchase/waitForPremiumGrant)

  private func handlePurchase() async {
    guard let package, !isPurchasing else { return }
    isPurchasing = true
    defer { isPurchasing = false }

    do {
      let result = try await PurchasesService.shared.purchase(package: package)
      if result.userCancelled { return }
      if PurchasesService.shared.isPremium {
        dismiss()
        return
      }
      if await waitForPremiumGrant() {
        dismiss()
        return
      }
      alertMessage = "購入処理中です。しばらくしてからご確認ください。"
    } catch let error as ErrorCode where error == .purchaseCancelledError {
      return
    } catch let error as ErrorCode where error == .invalidReceiptError {
      _ = try? await PurchasesService.shared.syncPurchases()
      if await waitForPremiumGrant() {
        dismiss()
        return
      }
      alertMessage = "購入処理中です。しばらくしてからご確認ください。"
    } catch {
      alertMessage = "購入を完了できませんでした。もう一度お試しください。"
    }
  }

  private func waitForPremiumGrant(attempts: Int = 8, intervalNanoseconds: UInt64 = 900_000_000) async -> Bool {
    for _ in 0..<attempts {
      if PurchasesService.shared.isPremium { return true }
      try? await Task.sleep(nanoseconds: intervalNanoseconds)
      await PurchasesService.shared.refreshCustomerInfo()
    }
    return PurchasesService.shared.isPremium
  }

  // MARK: - Restore

  private func handleRestore() async {
    isRestoring = true
    defer { isRestoring = false }

    do {
      _ = try await PurchasesService.shared.restorePurchases()
      if PurchasesService.shared.isPremium {
        alertMessage = "購入が復元されました。"
        dismiss()
      } else {
        alertMessage = "以前の購入が見つかりませんでした。"
      }
    } catch {
      alertMessage = "以前の購入が見つかりませんでした。"
    }
  }
}
