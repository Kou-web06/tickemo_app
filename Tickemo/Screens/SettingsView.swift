import SwiftUI
import StoreKit
import CoreData

private let termsURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Terms-of-Use-2f65fd5d3e2d80ba8abcda85615cde4a?source=copy_link")!
private let privacyURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Privacy-Policy-2f85fd5d3e2d809b912dfc4ec2a2ed6a?source=copy_link")!
private let feedbackURL = URL(string: "https://forms.gle/Z6fQZZUM79WprPSk8")!
private let appStoreURL = URL(string: "https://apps.apple.com/ja/app/tickemo-%E3%83%A9%E3%82%A4%E3%83%96%E3%81%AE%E6%80%9D%E3%81%84%E5%87%BA%E3%82%92%E8%A8%98%E9%8C%B2/id6758604980")!

private let settingsAccentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)
struct SettingsView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.requestReview) private var requestReview
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.openURL) private var openURL

  @FetchRequest(sortDescriptors: []) private var profiles: FetchedResults<CD_UserProfile>

  @State private var showingProfileEdit = false
  @State private var showingDeleteConfirmation = false
  @State private var showingLegacyReimportConfirmation = false
  @State private var legacyReimportResult: String?
  @State private var isReimportingLegacy = false
  @State private var showingMusicProvider = false
  @State private var showingICloudSync = false
  @State private var showingNotificationSettings = false
  @State private var showingFAQ = false
  @State private var showingShareSheet = false
  @State private var showingWebView = false
  @State private var webViewURL: URL = termsURL
  @State private var resolvedProfile: CD_UserProfile?
  #if DEBUG
  @State private var showingDebugSheet = false
  #endif

  @State private var isHapticsEnabled = HapticsPreferenceService.shared.isEnabled
  @State private var musicProviderValue = MusicProviderPreferenceStore.load()

  private var profile: CD_UserProfile? {
    profiles.first ?? resolvedProfile
  }

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

  var body: some View {
    NavigationStack {
      Group {
        if let profile {
          settingsBody(profile: profile)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("マイページ")
      .task {
        guard profiles.first == nil, resolvedProfile == nil else { return }
        let created = UserProfileFetching.fetchOrCreateUserProfile(context: viewContext)
        try? viewContext.save()
        resolvedProfile = created
      }
    }
  }

  private func settingsBody(profile: CD_UserProfile) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        profileHeader(profile)

        if !PurchasesService.shared.isPremium {
          PaywallBannerView()
            .padding(.top, 15)
            .padding(.bottom, 12)
        }

        sectionsView

        footer
          .padding(.top, 80)
      }
      .padding(.horizontal, 20)
      .padding(.top, 28)
      .padding(.bottom, 120)
    }
    .background(palette.screenBackground.ignoresSafeArea())
    .sheet(isPresented: $showingProfileEdit) {
      ProfileEditView(profile: profile)
    }
    .sheet(isPresented: $showingMusicProvider) {
      MusicProviderPickerView(selection: $musicProviderValue)
    }
    .sheet(isPresented: $showingICloudSync) {
      ICloudSyncStatusView()
    }
    .sheet(isPresented: $showingNotificationSettings) {
      NotificationSettingsView()
    }
    .sheet(isPresented: $showingFAQ) {
      FAQView()
    }
    .sheet(isPresented: $showingShareSheet) {
      ActivityShareSheet(items: ["Tickemo\n\(appStoreURL.absoluteString)"])
    }
    .sheet(isPresented: $showingWebView) {
      SafariView(url: webViewURL)
    }
    .alert("すべてのデータを削除しますか？", isPresented: $showingDeleteConfirmation) {
      Button("削除", role: .destructive) { deleteAllData() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("すべての記録と設定が削除されます。この操作は取り消せません。")
    }
    .alert("以前のデータを取り込みますか？", isPresented: $showingLegacyReimportConfirmation) {
      Button("取り込む") { reimportLegacyData() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      // Not destructive, and worth saying so plainly: the importer only
      // adds rows it can't already find, so a user who taps this out of
      // worry can't make their situation worse.
      Text("旧バージョンのアプリに残っている記録のうち、まだ取り込まれていないものだけを追加します。今ある記録が変更・削除されることはありません。")
    }
    .alert(
      "取り込み結果",
      isPresented: Binding(
        get: { legacyReimportResult != nil },
        set: { if !$0 { legacyReimportResult = nil } }
      )
    ) {
      Button("OK", role: .cancel) { legacyReimportResult = nil }
    } message: {
      Text(legacyReimportResult ?? "")
    }
    #if DEBUG
    .sheet(isPresented: $showingDebugSheet) {
      DebugToolsView()
    }
    #endif
  }

  // MARK: - Profile header

  private func profileHeader(_ profile: CD_UserProfile) -> some View {
    let isPremium = PurchasesService.shared.isPremium
    return HStack {
      HStack(spacing: 12) {
        avatarView(profile, isPremium: isPremium)

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Text(profile.name?.isEmpty == false ? profile.name! : "ユーザー")
              .font(.system(size: 20, weight: .heavy))
              .foregroundStyle(palette.titleText)
            membershipBadge(isPremium: isPremium)
          }
          Text("@\(displayUsername(profile)) • joined \(JoinedDateFormatting.relativeString(from: profile.joinedAt))")
            .font(.system(size: 12))
            .foregroundStyle(palette.secondaryText)
        }
      }
      Spacer(minLength: 0)
      Button {
        showingProfileEdit = true
      } label: {
        Image("Edit")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .foregroundStyle(palette.profileEditIcon)
          .frame(width: 30, height: 30)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 18)
    .background(palette.screenBackground)
    .clipShape(RoundedRectangle(cornerRadius: 18))
  }

  private func displayUsername(_ profile: CD_UserProfile) -> String {
    var username = profile.username?.isEmpty == false ? profile.username! : "user"
    while username.hasPrefix("@") { username.removeFirst() }
    return username
  }

  @ViewBuilder
  private func avatarView(_ profile: CD_UserProfile, isPremium: Bool) -> some View {
    if isPremium {
      LinearGradient(
        colors: [palette.plusGradientStart, palette.plusGradientEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .frame(width: 68, height: 68)
      .clipShape(Circle())
      .overlay {
        Circle()
          .fill(palette.avatarRingBackground)
          .frame(width: 64, height: 64)
          .overlay { avatarContent(profile).frame(width: 60, height: 60).clipShape(Circle()) }
      }
    } else {
      Circle()
        .fill(palette.avatarRingBackground)
        .frame(width: 68, height: 68)
        .overlay { avatarContent(profile).frame(width: 60, height: 60).clipShape(Circle()) }
    }
  }

  @ViewBuilder
  private func avatarContent(_ profile: CD_UserProfile) -> some View {
    if let data = profile.avatarImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage).resizable().scaledToFill()
    } else {
      ZStack {
        palette.avatarFallbackBackground
        Text(initials(profile))
          .font(.system(size: 18, weight: .heavy))
          .foregroundStyle(palette.avatarFallbackText)
      }
    }
  }

  private func initials(_ profile: CD_UserProfile) -> String {
    let name = profile.name?.isEmpty == false ? profile.name! : "ユーザー"
    let letters = name.split(separator: " ").compactMap { $0.first }.prefix(2)
    let result = letters.map(String.init).joined().uppercased()
    return result.isEmpty ? "U" : result
  }

  private func membershipBadge(isPremium: Bool) -> some View {
    Group {
      if isPremium {
        LinearGradient(colors: [palette.plusGradientStart, palette.plusGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
          .overlay {
            Text("Plus")
              .font(.system(size: 9, weight: .bold))
              .tracking(0.5)
              .foregroundStyle(palette.plusText)
          }
      } else {
        palette.freeBadgeBackground
          .overlay {
            Text("Free")
              .font(.system(size: 9, weight: .bold))
              .tracking(0.5)
              .foregroundStyle(palette.freeBadgeText)
          }
      }
    }
    .frame(width: 34, height: 20)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .fixedSize()
  }

  // MARK: - Sections

  private struct Row: Identifiable {
    let id: String
    let label: String
    var value: String?
    var destructive = false
  }

  private struct RowSection: Identifiable {
    let id: String
    let title: String
    let rows: [Row]
  }

  private var icloudSyncStatusText: String {
    switch CloudSyncStatusService.shared.status {
    case .notSyncedYet: "未同期"
    case .syncing: "同期中…"
    case .synced: "同期済み"
    }
  }

  private var sectionsData: [RowSection] {
    var sections = [
      RowSection(id: "general", title: "一般", rows: [
        Row(id: "dark-mode", label: "ダークモード"),
        Row(id: "haptics", label: "触覚フィードバック"),
        Row(id: "music-provider", label: "音楽プロバイダー", value: musicProviderValue == .spotify ? "Spotify" : "Apple Music"),
        Row(id: "icloud-sync", label: "iCloud同期", value: icloudSyncStatusText),
        Row(id: "notifications", label: "通知"),
      ]),
      RowSection(id: "about", title: "アプリについて", rows: [
        Row(id: "terms", label: "利用規約"),
        Row(id: "privacy", label: "プライバシーポリシー"),
      ]),
      RowSection(id: "support", title: "サポート", rows: [
        Row(id: "review", label: "アプリをレビュー"),
        Row(id: "share-app", label: "アプリを応援"),
        Row(id: "faq", label: "よくある質問"),
        Row(id: "feedback", label: "フィードバック"),
      ]),
      RowSection(id: "account", title: "アカウント", rows: [
        Row(
          id: "reimport-legacy",
          label: "以前のバージョンのデータを取り込む",
          value: isReimportingLegacy ? "実行中…" : nil
        ),
        Row(id: "delete", label: "データをすべて削除", destructive: true),
      ]),
    ]
    #if DEBUG
    sections.append(RowSection(id: "debug", title: "デバッグ", rows: [
      Row(id: "debug-tools", label: "デバッグツール"),
    ]))
    #endif
    return sections
  }

  private var sectionsView: some View {
    ForEach(sectionsData) { section in
      VStack(alignment: .leading, spacing: 10) {
        Text(section.title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(palette.tertiaryText)
          .padding(.leading, 8)

        VStack(spacing: 0) {
          ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
            rowView(row)
            if index < section.rows.count - 1 {
              Rectangle().fill(palette.rowBorder).frame(height: 0.5)
            }
          }
        }
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: palette.sectionShadow.opacity(0.16), radius: 8, x: 0, y: 2)
      }
      .padding(.top, 22)
    }
  }

  @ViewBuilder
  private func rowView(_ row: Row) -> some View {
    if row.id == "dark-mode" || row.id == "haptics" {
      toggleRow(row)
    } else {
      Button {
        handleRowTap(row.id)
      } label: {
        HStack(spacing: 12) {
          rowLeadingIcon(row.id)
          Text(row.label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(row.destructive ? palette.destructiveText : palette.primaryText)
          Spacer(minLength: 8)
          rowTrailingContent(row)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 19)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func toggleRow(_ row: Row) -> some View {
    HStack(spacing: 12) {
      rowLeadingIcon(row.id)
      Text(row.label)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(palette.primaryText)
      Spacer(minLength: 8)
      if row.id == "dark-mode" {
        Toggle("", isOn: Binding(
          get: { isDarkMode },
          set: { _ in
            HapticsPreferenceService.shared.impact(.light)
            ThemePreferenceService.shared.setManualDarkMode(!isDarkMode)
          }
        ))
        .labelsHidden()
        .tint(settingsAccentPurple)
      } else {
        Toggle("", isOn: $isHapticsEnabled)
          .labelsHidden()
          .tint(settingsAccentPurple)
          .onChange(of: isHapticsEnabled) { _, newValue in
            HapticsPreferenceService.shared.setEnabled(newValue)
          }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
  }

  @ViewBuilder
  private func rowLeadingIcon(_ id: String) -> some View {
    switch id {
    case "dark-mode":
      settingsIcon("Moon", color: palette.iconColor)
    case "haptics":
      settingsIcon("haptics", color: palette.iconColor)
    case "music-provider":
      if musicProviderValue == .spotify {
        settingsIcon("Spotify", color: palette.iconColor)
      } else {
        settingsIcon("Itunes", color: palette.iconColor)
      }
    case "icloud-sync":
      settingsIcon("Cloud", color: palette.iconColor)
    case "notifications":
      HugeIconView(icon: HugeIcons.notification03, size: 20)
        .foregroundStyle(palette.iconColor)
        .frame(width: 24, height: 24)
    case "terms":
      settingsIcon("Palm", color: palette.iconColor)
    case "privacy":
      settingsIcon("Shield", color: palette.iconColor)
    case "review":
      settingsIcon("Star", color: palette.iconColor)
    case "share-app":
      settingsIcon("megaphone", color: palette.iconColor)
    case "faq":
      settingsIcon("question", color: palette.iconColor)
    case "feedback":
      settingsIcon("email", color: palette.iconColor)
    case "reimport-legacy":
      settingsIcon("Download", color: palette.iconColor)
    case "delete":
      settingsIcon("Confounded", color: palette.destructiveText)
    default:
      Color.clear.frame(width: 24, height: 24)
    }
  }

  private func settingsIcon(_ name: String, color: Color) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: 24, height: 24)
      .foregroundStyle(color)
  }

  @ViewBuilder
  private func rowTrailingContent(_ row: Row) -> some View {
    HStack(spacing: 8) {
      if let value = row.value {
        Text(value).font(.system(size: 10)).foregroundStyle(palette.secondaryText)
      }
      if !row.destructive {
        rowIcon(row.id)
      }
    }
  }

  @ViewBuilder
  private func rowIcon(_ id: String) -> some View {
    switch id {
    case "faq", "icloud-sync", "music-provider", "debug-tools", "reimport-legacy", "notifications":
      HugeIconView(icon: HugeIcons.arrowRight01, size: 15)
        .foregroundStyle(palette.iconColor)
    default:
      HugeIconView(icon: HugeIcons.arrowUpRight01, size: 18)
        .foregroundStyle(palette.iconColor)
    }
  }

  private func handleRowTap(_ id: String) {
    switch id {
    case "icloud-sync": showingICloudSync = true
    case "notifications": showingNotificationSettings = true
    case "music-provider": showingMusicProvider = true
    case "faq": showingFAQ = true
    case "delete": showingDeleteConfirmation = true
    case "reimport-legacy":
      guard !isReimportingLegacy else { return }
      showingLegacyReimportConfirmation = true
    case "review": requestReview()
    case "share-app": showingShareSheet = true
    case "feedback": openURL(feedbackURL)
    case "terms": webViewURL = termsURL; showingWebView = true
    case "privacy": webViewURL = privacyURL; showingWebView = true
    #if DEBUG
    case "debug-tools": showingDebugSheet = true
    #endif
    default: break
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 8) {
      Image("SettingsFooterLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 28, height: 28)
        .opacity(0.6)
      VStack(alignment: .leading, spacing: 0) {
        Text("Tickemo").font(.system(size: 11)).foregroundStyle(palette.secondaryText)
        Text("Version \(appVersionText)").font(.system(size: 11)).foregroundStyle(palette.secondaryText)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var appVersionText: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
  }

  private func reimportLegacyData() {
    isReimportingLegacy = true
    Task {
      let summary = await MigrationCoordinator.shared.runManualImport()
      isReimportingLegacy = false

      if let error = summary.error {
        legacyReimportResult = "取り込みに失敗しました。\n\(error)"
      } else if summary.source == "none" {
        legacyReimportResult = "取り込めるデータは見つかりませんでした。"
      } else if summary.importedAnything {
        legacyReimportResult = """
        \(summary.recordCount)件の記録を追加しました。
        セットリスト: \(summary.setlistItemCount)件 / 画像: \(summary.imageCount)件
        """
      } else {
        legacyReimportResult = "すでにすべて取り込み済みでした。追加された記録はありません。"
      }
    }
  }

  private func deleteAllData() {
    for entityName in ["CD_ChekiRecord", "CD_UserProfile"] {
      let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
      if let objects = try? viewContext.fetch(request) {
        objects.forEach(viewContext.delete)
      }
    }
    try? viewContext.save()
  }
}
