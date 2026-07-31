import SwiftUI
import StoreKit
import CoreData

private let termsURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Terms-of-Use-2f65fd5d3e2d80ba8abcda85615cde4a?source=copy_link")!
private let privacyURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Privacy-Policy-2f85fd5d3e2d809b912dfc4ec2a2ed6a?source=copy_link")!
private let feedbackURL = URL(string: "https://forms.gle/Z6fQZZUM79WprPSk8")!
private let appStoreURL = URL(string: "https://apps.apple.com/ja/app/tickemo-%E3%83%A9%E3%82%A4%E3%83%96%E3%81%AE%E6%80%9D%E3%81%84%E5%87%BA%E3%82%92%E8%A8%98%E9%8C%B2/id6758604980")!

/// Full pixel-and-feature parity port of screens/SettingsScreen.tsx, per
/// the user's explicit "match RN exactly" request. Two deliberate
/// deviations from RN, both confirmed to be RN bugs rather than design
/// choices, fixed here at the user's direction (see
/// ThemePreferenceService/CustomToggleSwitch call sites for the specifics
/// of each): dark mode with no manual override now actually follows the
/// system appearance instead of RN's hard-coded-light collapse, and the
/// haptics toggle now shows ON as right/purple instead of RN's inverted
/// display. `NotificationSettingsScreen` and the "sns"/"about" row ids are
/// excluded — confirmed dead code in RN (registered as routes, but no row
/// in RN's live `sections` array ever navigates to them). Root of the
/// "Settings" tab (see ContentView) — no dismiss chrome since it's a
/// permanent tab page, not a sheet; the DEBUG tools entry point that used
/// to live on RecordListView's toolbar now lives here as a debug-only row.
struct SettingsView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.requestReview) private var requestReview
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.openURL) private var openURL

  @FetchRequest(sortDescriptors: []) private var profiles: FetchedResults<CD_UserProfile>

  @State private var showingProfileEdit = false
  @State private var showingDeleteConfirmation = false
  @State private var showingMusicProvider = false
  @State private var showingLanguage = false
  @State private var showingICloudSync = false
  @State private var showingFAQ = false
  @State private var showingShareSheet = false
  @State private var resolvedProfile: CD_UserProfile?
  #if DEBUG
  @State private var showingDebugSheet = false
  #endif

  @State private var isHapticsEnabled = HapticsPreferenceService.shared.isEnabled
  @State private var musicProviderValue = MusicProviderPreferenceStore.load()
  @State private var languageValue = LanguagePreferenceStore.load()

  private var profile: CD_UserProfile? {
    profiles.first ?? resolvedProfile
  }

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

  var body: some View {
    Group {
      if let profile {
        settingsBody(profile: profile)
      } else {
        ProgressView()
      }
    }
    .task {
      guard profiles.first == nil, resolvedProfile == nil else { return }
      let created = UserProfileFetching.fetchOrCreateUserProfile(context: viewContext)
      try? viewContext.save()
      resolvedProfile = created
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
    .safeAreaInset(edge: .top, spacing: 0) { headerBar }
    .sheet(isPresented: $showingProfileEdit) {
      ProfileEditView(profile: profile)
    }
    .sheet(isPresented: $showingMusicProvider) {
      MusicProviderPickerView(selection: $musicProviderValue)
    }
    .sheet(isPresented: $showingLanguage) {
      LanguagePickerView(selection: $languageValue)
    }
    .sheet(isPresented: $showingICloudSync) {
      ICloudSyncStatusView()
    }
    .sheet(isPresented: $showingFAQ) {
      FAQView()
    }
    .sheet(isPresented: $showingShareSheet) {
      ActivityShareSheet(items: ["Tickemo\n\(appStoreURL.absoluteString)"])
    }
    .alert("Delete all data?", isPresented: $showingDeleteConfirmation) {
      Button("Delete", role: .destructive) { deleteAllData() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("All records and settings will be deleted. This action cannot be undone.")
    }
    #if DEBUG
    .sheet(isPresented: $showingDebugSheet) {
      DebugToolsView()
    }
    #endif
  }

  // MARK: - Header

  private var headerBar: some View {
    VStack(spacing: 0) {
      HStack {
        Text("My page")
          .font(.system(size: 28, weight: .heavy))
          .foregroundStyle(palette.titleText)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 10)
    }
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

  // MARK: - Profile header

  private func profileHeader(_ profile: CD_UserProfile) -> some View {
    let isPremium = PurchasesService.shared.isPremium
    return HStack {
      HStack(spacing: 12) {
        avatarView(profile, isPremium: isPremium)

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Text(profile.name?.isEmpty == false ? profile.name! : "User")
              .font(.system(size: 20, weight: .heavy))
              .foregroundStyle(palette.titleText)
            membershipBadge(isPremium: isPremium)
          }
          Text("@\(displayUsername(profile)) • Joined \(JoinedDateFormatting.relativeString(from: profile.joinedAt))")
            .font(.system(size: 12))
            .foregroundStyle(palette.secondaryText)
        }
      }
      Spacer(minLength: 0)
      Button {
        showingProfileEdit = true
      } label: {
        HugeIconView(icon: HugeIcons.pencilEdit01, size: 18, weight: 2)
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
    let name = profile.name?.isEmpty == false ? profile.name! : "User"
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
    .frame(width: isPremium ? 34 : 34, height: 20)
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

  private var sectionsData: [RowSection] {
    var sections = [
      RowSection(id: "general", title: "General", rows: [
        Row(id: "dark-mode", label: "Theme"),
        Row(id: "haptics", label: "Haptics"),
        Row(id: "music-provider", label: "Music Provider", value: musicProviderValue == .spotify ? "Spotify" : "Apple Music"),
        Row(id: "language", label: "Language", value: languageValueLabel),
        Row(id: "icloud-sync", label: "iCloud Sync"),
      ]),
      RowSection(id: "about", title: "About this app", rows: [
        Row(id: "terms", label: "Terms of Use"),
        Row(id: "privacy", label: "Privacy Policy"),
      ]),
      RowSection(id: "support", title: "Support", rows: [
        Row(id: "review", label: "Review the app"),
        Row(id: "share-app", label: "Share this app"),
        Row(id: "faq", label: "FAQ"),
        Row(id: "feedback", label: "Feedback"),
      ]),
      RowSection(id: "account", title: "Account", rows: [
        Row(id: "delete", label: "Delete all data", destructive: true),
      ]),
    ]
    #if DEBUG
    sections.append(RowSection(id: "debug", title: "Debug", rows: [
      Row(id: "debug-tools", label: "Debug Tools"),
    ]))
    #endif
    return sections
  }

  private var languageValueLabel: String {
    switch languageValue {
    case .system: "System Default"
    case .ja: "日本語"
    case .en: "English"
    }
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
    let isToggleRow = row.id == "dark-mode" || row.id == "haptics"
    Button {
      handleRowTap(row.id)
    } label: {
      HStack(spacing: 8) {
        Text(row.label)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(row.destructive ? palette.destructiveText : palette.primaryText)

        Spacer(minLength: 8)

        rowTrailingContent(row)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isToggleRow)
  }

  @ViewBuilder
  private func rowTrailingContent(_ row: Row) -> some View {
    switch row.id {
    case "dark-mode":
      CustomToggleSwitch(isOn: isDarkMode, trackOnColor: Color(hex: "#333333"), trackOffColor: Color(hex: "#8B5CF6")) {
        ThemePreferenceService.shared.setManualDarkMode(!isDarkMode)
      }
    case "haptics":
      CustomToggleSwitch(isOn: isHapticsEnabled, trackOnColor: Color(hex: "#8B5CF6"), trackOffColor: Color(hex: "#333333")) {
        isHapticsEnabled.toggle()
        HapticsPreferenceService.shared.setEnabled(isHapticsEnabled)
      }
    default:
      HStack(spacing: 8) {
        if let value = row.value {
          Text(value).font(.system(size: 10)).foregroundStyle(palette.secondaryText)
        }
        if !row.destructive {
          rowIcon(row.id)
        }
      }
    }
  }

  @ViewBuilder
  private func rowIcon(_ id: String) -> some View {
    switch id {
    case "faq", "icloud-sync", "music-provider", "language", "debug-tools":
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
    case "music-provider": showingMusicProvider = true
    case "language": showingLanguage = true
    case "faq": showingFAQ = true
    case "delete": showingDeleteConfirmation = true
    case "review": requestReview()
    case "share-app": showingShareSheet = true
    case "feedback": openURL(feedbackURL)
    case "terms": openURL(termsURL)
    case "privacy": openURL(privacyURL)
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
