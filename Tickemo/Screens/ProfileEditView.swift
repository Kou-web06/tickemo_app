import SwiftUI

/// Full pixel-and-feature parity port of screens/ProfileEditScreen.tsx.
/// Avatar picking uses `ImagePickerRepresentable` (a `UIImagePickerController`
/// wrapper with `allowsEditing = true`) instead of this codebase's usual
/// `PhotosPicker` + automatic center-crop convention (see
/// `RecordFormView`/`ImageCropping.swift`) — a screen-local exception made
/// specifically to get RN's real interactive, user-positioned crop UI,
/// which `PhotosPicker`/`PHPickerViewController` has no equivalent for.
struct ProfileEditView: View {
  @ObservedObject var profile: CD_UserProfile

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  @State private var name: String
  @State private var username: String
  @State private var avatarImageData: Data?
  @State private var showingImagePicker = false
  @State private var isSaving = false
  @State private var displayNameError: String?
  @State private var showingAlert = false
  @State private var alertMessage = ""

  init(profile: CD_UserProfile) {
    self.profile = profile
    _name = State(initialValue: profile.name ?? "")
    _username = State(initialValue: profile.username ?? "")
    _avatarImageData = State(initialValue: profile.avatarImageData)
  }

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: ProfileEditPalette { ProfileEditPalette(isDarkMode: isDarkMode) }
  private var isPremium: Bool { PurchasesService.shared.isPremium }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        profileCard
        formCard
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 40)
    }
    .background(palette.screenBackground.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) { header }
    .sheet(isPresented: $showingImagePicker) {
      ImagePickerRepresentable { data in
        avatarImageData = data
      }
      .ignoresSafeArea()
    }
    .alert("入力エラー", isPresented: $showingAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(alertMessage)
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        HugeIconView(icon: HugeIcons.arrowLeft01, size: 20, weight: 2)
          .foregroundStyle(palette.primaryText)
          .frame(width: 36, height: 36)
      }

      Spacer()

      Text("Edit Profile")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(palette.primaryText)

      Spacer()

      Button {
        save()
      } label: {
        ZStack {
          Circle().fill(palette.saveButton)
          if isSaving {
            ProgressView().tint(.white)
          } else {
            HugeIconView(icon: HugeIcons.tick02, size: 15, weight: 2)
              .foregroundStyle(.white)
          }
        }
        .frame(width: 34, height: 34)
      }
      .disabled(isSaving)
      .opacity(isSaving ? 0.6 : 1)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
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

  // MARK: - Profile card

  private var profileCard: some View {
    HStack(alignment: .top) {
      ZStack(alignment: .bottomTrailing) {
        avatarContent
          .frame(width: 72, height: 72)
          .clipShape(Circle())

        Button {
          showingImagePicker = true
        } label: {
          Image("Edit")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 13, height: 13)
            .foregroundStyle(palette.editIcon)
            .frame(width: 28, height: 28)
            .background(palette.avatarBackground)
            .clipShape(Circle())
            .overlay(Circle().stroke(palette.borderColor, lineWidth: 2))
        }
        .offset(x: 6, y: 6)
      }

      if isPremium {
        Image("BannerPass")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 110, height: 100)
          .padding(.horizontal, 10)
          .padding(.top, -16)
      }

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 6) {
        Text("Joined")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(palette.subText)
        Text(formattedDate(profile.joinedAt))
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(palette.valueText)

        if isPremium {
          Text("Plus since")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.subText)
            .padding(.top, 10)
          Text(formattedDate(profile.plusStartedAt))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(palette.valueText)
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity)
    .background(palette.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .shadow(color: palette.sectionShadow.opacity(0.08), radius: 8, x: 0, y: 2)
    .padding(.top, 12)
  }

  @ViewBuilder
  private var avatarContent: some View {
    if let avatarImageData, let uiImage = UIImage(data: avatarImageData) {
      Image(uiImage: uiImage).resizable().scaledToFill()
    } else {
      ZStack {
        palette.avatarFallbackBackground
        Text(initials)
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(palette.avatarText)
      }
    }
  }

  private var initials: String {
    let base = name.isEmpty ? (username.isEmpty ? "U" : username) : name
    let letters = base.split(separator: " ").compactMap { $0.first }.prefix(2)
    let result = letters.map(String.init).joined().uppercased()
    return result.isEmpty ? "U" : result
  }

  private func formattedDate(_ isoString: String?) -> String {
    guard let isoString, let date = DateFormatting.isoDate(from: isoString) else { return "-" }
    return date.formatted(date: .numeric, time: .omitted)
  }

  // MARK: - Form card

  private var formCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Display Name")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(palette.subText)
        .padding(.top, 8)
        .padding(.bottom, 10)

      TextField("Display Name", text: $name)
        .font(.system(size: 14))
        .foregroundStyle(palette.inputText)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(palette.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onChange(of: name) { _, newValue in
          if newValue.trimmingCharacters(in: .whitespaces).count > 8 {
            displayNameError = "表示名は8文字以内で入力してください"
          } else {
            displayNameError = nil
          }
        }

      if let displayNameError {
        Text(displayNameError)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color(hex: "#E53935"))
          .padding(.top, 8)
      }

      Text("Username")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(palette.subText)
        .padding(.top, 18)
        .padding(.bottom, 10)

      HStack(spacing: 6) {
        Text("@")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(palette.inputText)
        TextField("username", text: $username)
          .font(.system(size: 14))
          .foregroundStyle(palette.inputText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      .padding(.horizontal, 14)
      .frame(height: 44)
      .background(palette.inputBackground)
      .clipShape(RoundedRectangle(cornerRadius: 14))

      Text("Your username is shown on your public profile")
        .font(.system(size: 11))
        .foregroundStyle(palette.subText)
        .padding(.top, 10)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .shadow(color: palette.sectionShadow.opacity(0.08), radius: 8, x: 0, y: 2)
    .padding(.top, 20)
  }

  // MARK: - Save

  private func save() {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    var normalizedUsername = username.trimmingCharacters(in: .whitespaces)
    while normalizedUsername.hasPrefix("@") { normalizedUsername.removeFirst() }

    guard !trimmedName.isEmpty else {
      alertMessage = "表示名を入力してください"
      showingAlert = true
      return
    }
    guard trimmedName.count <= 8 else {
      displayNameError = "表示名は8文字以内で入力してください"
      return
    }
    guard !normalizedUsername.isEmpty else {
      alertMessage = "ユーザー名を入力してください"
      showingAlert = true
      return
    }

    isSaving = true
    profile.name = trimmedName
    profile.username = normalizedUsername
    profile.avatarImageData = avatarImageData
    try? viewContext.save()
    isSaving = false
    dismiss()
  }
}
