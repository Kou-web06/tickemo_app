import SwiftUI

/// Phase 0/1 debug tools (Apple Music auth test, data migration test),
/// moved out of the app's main body once RecordListView became the real
/// entry screen. DEBUG-only, reached via a toolbar icon on RecordListView.
struct DebugToolsView: View {
  private let appleMusicService = AppleMusicService()
  @State private var isAuthorized = false

  @State private var migrationSummaryText: String?
  @State private var isMigrating = false

  @State private var purchasesSummaryText: String?
  @State private var isCheckingPurchases = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Text(isAuthorized ? "Apple Music: Authorized" : "Apple Music: Not authorized")
          .foregroundStyle(.secondary)
        Button("Test Apple Music Auth") {
          Task {
            isAuthorized = await appleMusicService.authorize()
          }
        }

        Divider()
        Button("Run Data Migration (Debug)") {
          runDebugMigration()
        }
        .disabled(isMigrating)

        if isMigrating {
          ProgressView()
        }

        if let migrationSummaryText {
          ScrollView {
            Text(migrationSummaryText)
              .font(.system(.footnote, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 200)
          .padding(.horizontal)
        }

        Divider()
        Button("Check RevenueCat (Debug)") {
          runPurchasesCheck()
        }
        .disabled(isCheckingPurchases)

        if isCheckingPurchases {
          ProgressView()
        }

        if let purchasesSummaryText {
          ScrollView {
            Text(purchasesSummaryText)
              .font(.system(.footnote, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 200)
          .padding(.horizontal)
        }
      }
      .padding()
      .navigationTitle("Debug Tools")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private func runDebugMigration() {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      let importer = DataMigrationImporter()
      importer.resetMigrationFlag()
      let summary = await importer.run()
      migrationSummaryText = """
      source: \(summary.source)
      records: \(summary.recordCount)
      setlist items: \(summary.setlistItemCount)
      images: \(summary.imageCount)
      profile imported: \(summary.profileImported)
      error: \(summary.error ?? "none")
      """
      isMigrating = false
    }
  }

  private func runPurchasesCheck() {
    isCheckingPurchases = true
    purchasesSummaryText = nil
    Task {
      await PurchasesService.shared.configure()
      let offerings = try? await PurchasesService.shared.fetchOfferings()
      let packageCount = offerings?.current?.availablePackages.count ?? 0
      purchasesSummaryText = """
      configured: \(PurchasesService.shared.isConfigured)
      isPremium: \(PurchasesService.shared.isPremium)
      membershipType: \(PurchasesService.shared.membershipType.rawValue)
      activeEntitlementIds: \(PurchasesService.shared.activeEntitlementIds)
      current offering packages: \(packageCount)
      """
      isCheckingPurchases = false
    }
  }
}

#Preview {
  DebugToolsView()
}
