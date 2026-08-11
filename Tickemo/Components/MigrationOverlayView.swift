import SwiftUI

/// Covers the app while the first-launch-after-update import runs.
///
/// It's deliberately a blocking cover rather than a subtle banner: behind
/// it the record list is empty, and an empty collection screen is exactly
/// what a user who just lost all their tickets would see. Showing that for
/// even a few seconds is alarming in a way a short, explained wait is not.
/// `MigrationCoordinator.isBusy` is false for the fast local checks, so a
/// launch with nothing to do never shows this at all.
struct MigrationOverlayView: View {
  let phase: MigrationCoordinator.Phase

  @Environment(\.colorScheme) private var systemColorScheme

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: CollectionPalette { CollectionPalette(isDarkMode: isDarkMode) }

  private var message: String {
    switch phase {
    case .waitingForCloud: "iCloudの記録を確認しています…"
    default: "記録を新しい形式に移行しています…"
    }
  }

  var body: some View {
    ZStack {
      palette.screenBackground
        .ignoresSafeArea()

      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)

        Text(message)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(palette.primaryText)
          .multilineTextAlignment(.center)

        Text("アプリを開いたままお待ちください。既存のデータが変更されることはありません。")
          .font(.system(size: 12))
          .foregroundStyle(palette.secondaryText)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 40)
    }
    // Nothing behind this should be reachable while it's up — a tap that
    // created a ticket mid-import would be confusing at best.
    .contentShape(Rectangle())
    .onTapGesture {}
    .transition(.opacity)
  }
}

#Preview {
  MigrationOverlayView(phase: .importing)
}
