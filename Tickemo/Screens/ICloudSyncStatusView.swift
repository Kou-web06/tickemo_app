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

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        statusCard

        Text("iCloud sync is enabled, and your ticket/live records are kept up to date across all devices.")
          .font(.system(size: 14))
          .lineSpacing(6)
          .foregroundStyle(palette.descriptionText)
          .padding(.horizontal, 20)
          .padding(.bottom, 24)

        Text("Last sync: \(lastSyncText)")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(palette.syncTimeText)
          .padding(.horizontal, 20)
          .padding(.bottom, 32)

        syncButton
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
    }
    .background(palette.screenBackground.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) { header }
    .refreshable { await syncNow() }
  }

  // MARK: - Header

  private var header: some View {
    ZStack {
      HStack {
        Button {
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(palette.titleText)
            .frame(width: 44, height: 44)
        }
        Spacer()
        Color.clear.frame(width: 44, height: 44)
      }
      Text("iCloud Sync")
        .font(.system(size: 20, weight: .bold))
        .tracking(-0.5)
        .foregroundStyle(palette.titleText)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(
      ZStack {
        BlurEffectView(style: isDarkMode ? .systemMaterialDark : .systemMaterialLight)
        palette.headerBackground
      }
    )
    .overlay(alignment: .bottom) {
      Rectangle().fill(palette.headerBorder).frame(height: 1)
    }
  }

  // MARK: - Status card

  private var statusCard: some View {
    HStack {
      Text("Status")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(palette.statusLabel)
      Spacer()
      HStack(spacing: 10) {
        Circle()
          .fill(statusDotColor)
          .frame(width: 10, height: 10)
          .shadow(color: statusDotColor.opacity(0.4), radius: 3)
        Text(statusText)
          .font(.system(size: 15, weight: .semibold))
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
    case .notSyncedYet: "Not synced yet"
    case .syncing: "Syncing…"
    case .synced: "Synced"
    }
  }

  private var statusDotColor: Color {
    switch syncService.status {
    case .notSyncedYet: palette.statusLabel
    case .syncing, .synced: palette.success
    }
  }

  private var lastSyncText: String {
    guard let date = syncService.lastSuccessfulSyncDate else { return "Not synced" }
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
          Text("Syncing…")
        } else {
          Image(systemName: "icloud.and.arrow.up")
          Text("Sync now")
        }
      }
      .font(.system(size: 15, weight: .semibold))
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
