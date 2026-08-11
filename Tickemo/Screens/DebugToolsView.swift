import SwiftUI

// Settings 側の導線（行・シート・ハンドラ）も全て #if DEBUG 内にあるが、
// ビュー本体もリリースバイナリから確実に除外するためファイルごと囲う。
#if DEBUG

/// Phase 0/1 debug tools (Apple Music auth test, data migration test),
/// moved out of the app's main body once RecordListView became the real
/// entry screen. DEBUG-only, reached via a "Debug Tools" row in the
/// Settings tab.
struct DebugToolsView: View {
  private let appleMusicService = AppleMusicService()
  @State private var isAuthorized = false

  @State private var migrationSummaryText: String?
  @State private var isMigrating = false

  @State private var purchasesSummaryText: String?
  @State private var isCheckingPurchases = false

  @State private var widgetDiagText: String?

  @State private var showingPaywall = false

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

        Button("Sweep Duplicates (Debug)") {
          runDebugSweep()
        }
        .disabled(isMigrating)

        Button("Check CloudKit (Server)") {
          runCloudKitInventory()
        }
        .disabled(isMigrating)

        Button("Validate Schema (Dry Run)") {
          runSchemaInitialization(dryRun: true)
        }
        .disabled(isMigrating)

        Button("Init CloudKit Schema (Debug)") {
          runSchemaInitialization(dryRun: false)
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

        // 通常はPlus未加入時しか出ないペイウォールを、資格に関係なく
        // 直接シート表示してデザイン・商品情報を確認するためのボタン
        Button("Show Paywall (Debug)") {
          showingPaywall = true
        }

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

        Divider()
        Button("Widget Diagnostics") {
          runWidgetDiag()
        }
        Button("Force Widget Sync") {
          WidgetReloaderService.syncFromStore()
        }

        if let widgetDiagText {
          ScrollView {
            Text(widgetDiagText)
              .font(.system(.footnote, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 240)
          .padding(.horizontal)
        }
      }
      .padding()
      .navigationTitle("Debug Tools")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showingPaywall) {
        PaywallView()
      }
    }
  }

  private func runDebugMigration() {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      // Goes through the coordinator rather than the importer directly, so
      // this exercises the same claim/sweep path production takes. The
      // migration flag is deliberately *not* reset first: re-running is
      // already safe (the import is an upsert), and clearing the flag would
      // make this test a different code path than the real one.
      let summary = await MigrationCoordinator.shared.runManualImport()
      let claim = LegacyMigrationClaim().currentClaim()
      migrationSummaryText = """
      source: \(summary.source)
      records created: \(summary.recordCount)
      records already present: \(summary.recordsAlreadyPresent)
      setlist items: \(summary.setlistItemCount)
      images: \(summary.imageCount)
      profile imported: \(summary.profileImported)
      backup: \(summary.backupURL?.lastPathComponent ?? "none")
      error: \(summary.error ?? "none")
      claim: \(claim.map { "\($0.source) @ \($0.claimedAt) (\($0.deviceID.prefix(8)))" } ?? "none")
      """
      isMigrating = false
    }
  }

  /// Answers "did my add/delete actually reach CloudKit?" by comparing what
  /// the server holds against the local store, and showing the mirroring
  /// events (including failures) that got it there.
  private func runCloudKitInventory() {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      let inventory = await CloudKitInspector().inventory()
      let events = CloudSyncStatusService.shared.recentEvents.prefix(6)

      let eventLines = events.isEmpty
        ? "  (no mirroring events observed this launch)"
        : events.map { entry in
          let when = entry.endDate ?? entry.startDate
          let stamp = when.map { Self.timeFormatter.string(from: $0) } ?? "--:--:--"
          let state = entry.isFinished ? (entry.succeeded ? "ok" : "FAILED") : "in progress"
          let detail = entry.errorDescription.map { "\n      \($0)" } ?? ""
          return "  \(stamp) \(entry.typeLabel) \(state)\(detail)"
        }.joined(separator: "\n")

      let counts = inventory.recordCountsByType.isEmpty
        ? "  (none)"
        : inventory.recordCountsByType
          .sorted { $0.key < $1.key }
          .map { "  \($0.key): \($0.value)" }
          .joined(separator: "\n")

      migrationSummaryText = """
      account: \(inventory.accountStatus)
      core data zone on server: \(inventory.zoneExists ? "present" : "MISSING")
      local CD_ChekiRecord: \(inventory.localRecordCount)
      server CD_ChekiRecord: \(inventory.serverChekiRecordCount)
      match: \(inventory.localRecordCount == inventory.serverChekiRecordCount ? "yes" : "NO — not fully synced")

      server records by type:
      \(counts)

      recent mirroring events:
      \(eventLines)

      error: \(inventory.error ?? "none")
      """
      isMigrating = false
    }
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private func runDebugSweep() {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      let summary = await MigrationCoordinator.shared.runManualSweep()
      migrationSummaryText = summary.map {
        """
        merged record groups: \($0.mergedRecordGroups)
        deleted records: \($0.deletedRecords)
        deleted setlist items: \($0.deletedSetlistItems)
        deleted images: \($0.deletedImages)
        deleted profiles: \($0.deletedProfiles)
        deferred groups: \($0.deferredGroups)
        """
      } ?? "sweep failed"
      isMigrating = false
    }
  }

  /// See `docs/cloudkit-schema-deployment.md`. Only does anything useful on
  /// a build whose `icloud-container-environment` entitlement is
  /// `Development`; against Production it fails, which is itself the signal
  /// that the entitlement still needs flipping before schema work.
  ///
  /// Reports the account status and elapsed time alongside the result,
  /// because the failure this most often produces is a bare 30s timeout,
  /// and a timeout on its own doesn't say whether the model, the account,
  /// the entitlement or the network is at fault.
  private func runSchemaInitialization(dryRun: Bool) {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      let accountStatus = await PersistenceController.shared.cloudKitAccountStatus()
      let startedAt = Date()

      var outcome: String
      do {
        try await PersistenceController.shared.initializeCloudKitSchema(dryRun: dryRun)
        outcome = dryRun
          ? "dry run passed — the model is CloudKit-valid"
          : "succeeded — schema is now in the Development environment"
      } catch {
        outcome = "failed:\n\(error)"
      }

      migrationSummaryText = """
      mode: \(dryRun ? "dry run (no network)" : "live upload")
      cloudKit attached to store: \(PersistenceController.shared.isCloudKitEnabled)
      account status: \(accountStatus)
      elapsed: \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s
      result: \(outcome)
      """
      isMigrating = false
    }
  }

  private func runWidgetDiag() {
    let appGroup = "group.com.anonymous.Tickemo.widget"
    let dataKey = "liveWidgetData"

    let defaults = UserDefaults(suiteName: appGroup)
    let defaultsOk = defaults != nil
    let rawJson = defaults?.string(forKey: dataKey)
    let hasData = rawJson != nil

    var parsed = "—"
    if let json = rawJson, let data = json.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let title = obj["liveTitle"] as? String ?? "?"
      let date  = obj["liveDate"]  as? String ?? "?"
      let time  = obj["liveTime"]  as? String ?? "—"
      parsed = "\(title)  \(date) \(time)"
    }

    let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup)
    let coverPath = containerURL?.appendingPathComponent("widget_cover.jpg").path
    let hasCover = coverPath.map { FileManager.default.fileExists(atPath: $0) } ?? false

    widgetDiagText = """
    UserDefaults(suiteName:) accessible: \(defaultsOk)
    liveWidgetData key present: \(hasData)
    parsed: \(parsed)
    App Group container: \(containerURL?.path ?? "nil")
    cover image exists: \(hasCover)
    """
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

#endif
