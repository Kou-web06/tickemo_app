import SwiftUI

/// Ports screens/ICloudSyncScreen.tsx's visual design, but wired to real
/// CloudKit sync status via `CloudSyncStatusService` instead of RN's
/// `useCloudSync` hook (a completely different architecture — see that
/// service's doc-comment). Unlike RN, whose status text is hard-coded to
/// always say "Synced" regardless of actual state, this reports genuine
/// status (not-synced-yet / syncing / synced).
struct ICloudSyncStatusView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  @State private var isManualSyncing = false

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: ICloudSyncPalette { ICloudSyncPalette(isDarkMode: isDarkMode) }
  private var syncService: CloudSyncStatusService { CloudSyncStatusService.shared }

  @Environment(\.appFontChoice) private var appFont
  @Environment(\.appBgColor) private var bgColor

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          statusCard

          Text("iCloud同期が有効になっています。チケット・ライブの記録はすべてのデバイス間で自動的に同期されます。")
            .font(appFont.regular(14))
            .lineSpacing(6)
            .foregroundStyle(palette.descriptionText)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

          Text("最終同期: \(lastSyncText)")
            .font(appFont.regular(13))
            .foregroundStyle(palette.syncTimeText)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)

          syncButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
      }
      .background((bgColor ?? palette.screenBackground).ignoresSafeArea())
      .navigationTitle("iCloud Sync")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            HugeIconView(icon: HugeIcons.arrowLeft01, size: 20, weight: 2)
          }
        }
      }
      .refreshable { await syncNow() }
    }
    .presentationDetents([.height(380), .medium])
    .presentationDragIndicator(.visible)
  }

  // MARK: - Status card

  private var statusCard: some View {
    HStack {
      Text("Status")
        .font(appFont.bold(14))
        .foregroundStyle(palette.statusLabel)
      Spacer()
      HStack(spacing: 10) {
        Circle()
          .fill(statusDotColor)
          .frame(width: 10, height: 10)
          .shadow(color: statusDotColor.opacity(0.4), radius: 3)
        Text(statusText)
          .font(appFont.bold(15))
          .foregroundStyle(palette.statusText)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 18)
    .background(palette.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 30))
    .shadow(color: palette.shadowColor.opacity(0.04), radius: 3, x: 0, y: 1)
    .padding(.bottom, 24)
  }

  private var statusText: String {
    switch syncService.status {
    case .notSyncedYet: "未同期"
    case .syncing: "同期中…"
    case .synced: "同期済み"
    }
  }

  private var statusDotColor: Color {
    switch syncService.status {
    case .notSyncedYet: palette.statusLabel
    case .syncing, .synced: palette.success
    }
  }

  private var lastSyncText: String {
    guard let date = syncService.lastSuccessfulSyncDate else { return "未同期" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm"
    return formatter.string(from: date)
  }

  // MARK: - Sync button

  private var syncButton: some View {
    Button {
      Task { await syncNow() }
    } label: {
      HStack(spacing: 10) {
        if isManualSyncing || syncService.status == .syncing {
          ProgressView().tint(palette.indicatorColor)
          Text("同期中…")
        } else {
          HugeIconView(icon: HugeIcons.cloudUpload, size: 16)
          Text("今すぐ同期")
        }
      }
      .font(appFont.bold(15))
      .foregroundStyle(palette.buttonText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(palette.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 30))
      .shadow(color: palette.shadowColor.opacity(0.04), radius: 3, x: 0, y: 1)
    }
    .buttonStyle(.plain)
    .disabled(isManualSyncing || syncService.status == .syncing)
    .opacity((isManualSyncing || syncService.status == .syncing) ? 0.6 : 1)
  }

  private func syncNow() async {
    isManualSyncing = true
    await syncService.nudgeSync()
    isManualSyncing = false
  }
}
