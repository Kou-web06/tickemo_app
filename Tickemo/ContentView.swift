import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

struct ContentView: View {
  @State private var selectedTab = 0
  @State private var showingMyPage = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    // Bound inside `body` rather than stored: `MigrationCoordinator` is
    // main-actor isolated, and a stored-property initializer would run
    // outside that isolation.
    let migration = MigrationCoordinator.shared

    ZStack(alignment: .topLeading) {
      tabs
        .zIndex(0)

      avatarButton
        .zIndex(1)

      if showingMyPage {
        SettingsView(onClose: closeMyPage)
          // MyPage grows out of the avatar button's corner rather than
          // sliding in as a sheet — anchoring the scale at .topLeading
          // makes both dimensions expand away from that fixed corner,
          // i.e. diagonally toward the bottom-right.
          .transition(.scale(scale: 0.01, anchor: .topLeading).combined(with: .opacity))
          .zIndex(2)
      }
    }
    .withAppFont()
    .withAppBgColor()
    .overlay {
      if migration.isBusy {
        MigrationOverlayView(phase: migration.phase)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: migration.isBusy)
    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: showingMyPage)
    // `initial: true` so a cold launch via the shortcut (flag already set
    // before this view exists) is handled too, not just warm/background
    // taps that flip the flag while the view is already on screen.
    .onChange(of: ShortcutItemService.shared.pendingFeedbackRequest, initial: true) { _, isPending in
      guard isPending else { return }
      openMyPage()
      openURL(feedbackURL)
      ShortcutItemService.shared.clearPendingFeedbackRequest()
    }
  }

  private func openMyPage() {
    showingMyPage = true
  }

  private func closeMyPage() {
    showingMyPage = false
  }

  // どのタブからでもマイページへ飛べる、左上固定の丸いアバターボタン。
  private var avatarButton: some View {
    Button {
      HapticsPreferenceService.shared.impact(.light)
      openMyPage()
    } label: {
      HugeIconView(icon: HugeIcons.user, size: 20)
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .modifier(GlassCircleBackground())
    .padding(.leading, 16)
    .padding(.top, 8)
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
    }
    .tint(accentPurple)
    // Ports FloatingTabBar.tsx's medium-impact haptic on tab switches.
    .onChange(of: selectedTab) { _, _ in
      HapticsPreferenceService.shared.impact(.medium)
    }
  }
}

/// iOS 26's Liquid Glass (`.glassEffect`) on supported OS versions, falling
/// back to a plain material circle below that — deployment target is 17.6.
private struct GlassCircleBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.interactive(), in: Circle())
    } else {
      content
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
  }
}

#Preview {
  ContentView()
}
