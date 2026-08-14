import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

struct ContentView: View {
  @State private var selectedTab = 0
  @Environment(\.openURL) private var openURL

  var body: some View {
    // Bound inside `body` rather than stored: `MigrationCoordinator` is
    // main-actor isolated, and a stored-property initializer would run
    // outside that isolation.
    let migration = MigrationCoordinator.shared

    tabs
      .overlay {
        if migration.isBusy {
          MigrationOverlayView(phase: migration.phase)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: migration.isBusy)
      // `initial: true` so a cold launch via the shortcut (flag already set
      // before this view exists) is handled too, not just warm/background
      // taps that flip the flag while the view is already on screen.
      .onChange(of: ShortcutItemService.shared.pendingFeedbackRequest, initial: true) { _, isPending in
        guard isPending else { return }
        selectedTab = 3
        openURL(feedbackURL)
        ShortcutItemService.shared.clearPendingFeedbackRequest()
      }
  }

  private var tabs: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        RecordListView()
      }
      .tag(0)
      .tabItem {
        Label("Home", image: selectedTab == 0 ? "Home Active" : "Home")
      }

      CalendarView()
        .tag(1)
        .tabItem {
          Label("Calendar", image: selectedTab == 1 ? "Calendar Active" : "Calendar")
        }

      StatisticsView()
        .tag(2)
        .tabItem {
          Label("Report", image: selectedTab == 2 ? "Chart Active" : "Chart")
        }

      SettingsView()
        .tag(3)
        .tabItem {
          Label("Setting", image: selectedTab == 3 ? "Setting Active" : "Setting")
        }
    }
    .tint(accentPurple)
    // Ports FloatingTabBar.tsx's medium-impact haptic on tab switches.
    .onChange(of: selectedTab) { _, _ in
      HapticsPreferenceService.shared.impact(.medium)
    }
  }
}

#Preview {
  ContentView()
}
