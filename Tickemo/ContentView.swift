import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

struct ContentView: View {
  @State private var selectedTab = 0
  @State private var showingMyPage = false
  @Environment(\.openURL) private var openURL

  // タブごとのナビゲーション経路。子ページ（ライブ詳細・アーティスト詳細
  // など）に入っているタブではアバターボタンを隠す判定に使う——子ページ
  // では戻るボタンと同じ位置になり邪魔なため。
  @State private var homePath = NavigationPath()
  @State private var calendarPath = NavigationPath()
  @State private var reportPath = NavigationPath()

  private var isAtTabRoot: Bool {
    switch selectedTab {
    case 0: homePath.isEmpty
    case 1: calendarPath.isEmpty
    case 2: reportPath.isEmpty
    default: true
    }
  }

  // アバターボタンに表示するプロフィール画像。SettingsView と同じ
  // CD_UserProfile.avatarImageData を参照する（設定済みならそちらを優先）。
  @FetchRequest(sortDescriptors: []) private var profiles: FetchedResults<CD_UserProfile>
  private var avatarImage: UIImage? {
    profiles.first?.avatarImageData.flatMap(UIImage.init(data:))
  }

  var body: some View {
    // Bound inside `body` rather than stored: `MigrationCoordinator` is
    // main-actor isolated, and a stored-property initializer would run
    // outside that isolation.
    let migration = MigrationCoordinator.shared

    ZStack(alignment: .topLeading) {
      tabs
        .zIndex(0)

      if isAtTabRoot {
        avatarButton
          .zIndex(1)
          .transition(.opacity)
      }

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
    .animation(.easeInOut(duration: 0.2), value: isAtTabRoot)
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
  // 縦位置・高さは RecordListView のチケット追加ボタン（primaryAction の
  // ツールバーボタン、ナビゲーションバーの固定44pt行に配置される）に
  // 揃えるため、セーフエリア上端からの追加パディングは付けない。
  private var avatarButton: some View {
    Button {
      HapticsPreferenceService.shared.impact(.light)
      openMyPage()
    } label: {
      avatarIcon
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .modifier(GlassCircleBackground())
    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    .padding(.leading, 16)
  }

  @ViewBuilder
  private var avatarIcon: some View {
    if let avatarImage {
      Image(uiImage: avatarImage)
        .resizable()
        .scaledToFill()
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    } else {
      HugeIconView(icon: HugeIcons.user, size: 20)
        .foregroundStyle(.primary)
    }
  }

  private var tabs: some View {
    TabView(selection: $selectedTab) {
      NavigationStack(path: $homePath) {
        RecordListView()
      }
      .tag(0)
      .tabItem {
        Label("Home", image: selectedTab == 0 ? "Home Active" : "Home")
      }

      CalendarView(path: $calendarPath)
        .tag(1)
        .tabItem {
          Label("Calendar", image: selectedTab == 1 ? "Calendar Active" : "Calendar")
        }

      StatisticsView(path: $reportPath)
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
    }
  }
}

#Preview {
  ContentView()
}
