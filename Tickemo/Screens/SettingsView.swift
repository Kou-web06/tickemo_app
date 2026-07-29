import SwiftUI
import StoreKit
import CoreData

private let termsURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Terms-of-Use-2f65fd5d3e2d80ba8abcda85615cde4a?source=copy_link")!
private let privacyURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Privacy-Policy-2f85fd5d3e2d809b912dfc4ec2a2ed6a?source=copy_link")!
private let feedbackURL = URL(string: "https://forms.gle/Z6fQZZUM79WprPSk8")!
private let appStoreURL = URL(string: "https://apps.apple.com/ja/app/tickemo-%E3%83%A9%E3%82%A4%E3%83%96%E3%81%AE%E6%80%9D%E3%81%84%E5%87%BA%E3%82%92%E8%A8%98%E9%8C%B2/id6758604980")!
private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports screens/SettingsScreen.tsx's row list. Deliberately dropped from
/// this pass (see the approved plan): dark mode toggle (RN's own row was
/// `disabled`, never actually interactive), haptics toggle, language
/// (no i18n infra yet), Music Provider picker (RecordDetailView's
/// always-ask dialog is a deliberate improvement, not a gap to close),
/// iCloud sync status (CloudKit has no "sync now" equivalent, and RN's
/// status display was a hardcoded "Synced" regardless of actual state),
/// FAQ, and the currently-unreachable-in-RN-too NotificationSettings/
/// CountdownScreen.
struct SettingsView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss
  @Environment(\.requestReview) private var requestReview

  @FetchRequest(sortDescriptors: []) private var profiles: FetchedResults<CD_UserProfile>

  @State private var showingProfileEdit = false
  @State private var showingPaywall = false
  @State private var showingDeleteConfirmation = false
  @State private var resolvedProfile: CD_UserProfile?

  /// `profiles.first` once the fetch-or-create below has run and (if it had
  /// to insert one) been saved, so the @FetchRequest picks it up — resolved
  /// via `.task` rather than a computed property, since a computed property
  /// re-evaluated on every body access would insert a new, unsaved
  /// CD_UserProfile each time it's read.
  private var profile: CD_UserProfile? {
    profiles.first ?? resolvedProfile
  }

  var body: some View {
    NavigationStack {
      Group {
        if let profile {
          settingsList(profile: profile)
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
  }

  private func settingsList(profile: CD_UserProfile) -> some View {
    List {
      Section {
        profileHeader(profile)
        if !PurchasesService.shared.isPremium {
          paywallBanner
        }
      }

      Section("About App") {
        Link("Terms of Use", destination: termsURL)
        Link("Privacy Policy", destination: privacyURL)
      }

      Section("Support") {
        Button("Rate Tickemo") { requestReview() }
        ShareLink(item: appStoreURL, subject: Text("Tickemo")) {
          Text("Share Tickemo")
        }
        Link("Send Feedback", destination: feedbackURL)
      }

      Section("Account") {
        Button("Delete All Data", role: .destructive) {
          showingDeleteConfirmation = true
        }
      }

      Section {
        footer
      }
      .listRowBackground(Color.clear)
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") { dismiss() }
      }
    }
    .sheet(isPresented: $showingProfileEdit) {
      ProfileEditView(profile: profile)
    }
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
    .alert("Delete all data?", isPresented: $showingDeleteConfirmation) {
      Button("Delete Everything", role: .destructive) { deleteAllData() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently deletes every ticket, setlist, and your profile. This cannot be undone.")
    }
  }

  private func profileHeader(_ profile: CD_UserProfile) -> some View {
    Button {
      showingProfileEdit = true
    } label: {
      HStack(spacing: 14) {
        avatarView(profile)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(profile.name?.isEmpty == false ? profile.name! : "Add your name")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(.primary)
            membershipBadge
          }
          Text(joinedText(profile))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "pencil")
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func avatarView(_ profile: CD_UserProfile) -> some View {
    Group {
      if let data = profile.avatarImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          Color(.tertiarySystemBackground)
          Image(systemName: "person.fill")
            .foregroundStyle(.tertiary)
        }
      }
    }
    .frame(width: 56, height: 56)
    .clipShape(Circle())
  }

  private var membershipBadge: some View {
    let isPremium = PurchasesService.shared.isPremium
    return Text(isPremium ? "Plus" : "Free")
      .font(.system(size: 10, weight: .bold))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .foregroundStyle(isPremium ? accentPurple : .secondary)
      .overlay(
        Capsule().stroke(isPremium ? accentPurple : Color.secondary, lineWidth: 1)
      )
  }

  private func joinedText(_ profile: CD_UserProfile) -> String {
    guard let date = DateFormatting.isoDate(from: profile.joinedAt) else { return "" }
    return "Joined \(date.formatted(date: .abbreviated, time: .omitted))"
  }

  private var paywallBanner: some View {
    Button {
      showingPaywall = true
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Upgrade to Tickemo Plus").font(.system(size: 14, weight: .bold))
          Text("Unlock unlimited tickets and more.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
  }

  private var footer: some View {
    VStack(spacing: 4) {
      Text("Tickemo").font(.system(size: 12, weight: .semibold))
      Text("Version \(appVersionText)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var appVersionText: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    return "\(version) (\(build))"
  }

  private func deleteAllData() {
    // CD_ChekiRecord's Cascade delete rule takes CD_LiveImage/CD_SetlistItem
    // rows with it; CD_UserProfile is unrelated and deleted separately.
    for entityName in ["CD_ChekiRecord", "CD_UserProfile"] {
      let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
      if let objects = try? viewContext.fetch(request) {
        objects.forEach(viewContext.delete)
      }
    }
    try? viewContext.save()
  }
}
