import SwiftUI
import PhotosUI

/// Ports screens/ProfileEditScreen.tsx's editable fields (name, username,
/// avatar photo) onto CD_UserProfile. joinedAt/plusStartedAt are RN's
/// display-only fields too, shown here but not editable. RN's avatar picker
/// gives an interactive square-crop UI (`allowsEditing`/`aspect:[1,1]`);
/// this reuses RecordFormView's PhotosPicker + automatic center-crop
/// (ImageCropping.squareCroppedJPEGData) instead, favoring consistency
/// with the rest of this codebase's image-picking convention over exact
/// parity with RN's interactive cropper — both ultimately store a square
/// image, RN's is just user-positioned rather than auto-centered.
struct ProfileEditView: View {
  @ObservedObject var profile: CD_UserProfile

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  @State private var name: String
  @State private var username: String
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var avatarImageData: Data?

  init(profile: CD_UserProfile) {
    self.profile = profile
    _name = State(initialValue: profile.name ?? "")
    _username = State(initialValue: profile.username ?? "")
    _avatarImageData = State(initialValue: profile.avatarImageData)
  }

  private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && !username.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Avatar") {
          avatarPreview
          PhotosPicker("Choose Photo", selection: $selectedPhotoItem, matching: .images)
          if avatarImageData != nil {
            Button("Remove Photo", role: .destructive) { avatarImageData = nil }
          }
        }

        Section {
          TextField("Name", text: $name)
          HStack {
            Text("@").foregroundStyle(.secondary)
            TextField("username", text: $username)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }

        Section {
          if let joinedText {
            LabeledContent("Joined", value: joinedText)
          }
          if PurchasesService.shared.isPremium, let plusText {
            LabeledContent("Plus since", value: plusText)
          }
        }
      }
      .navigationTitle("Edit Profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!isValid)
        }
      }
      .onChange(of: selectedPhotoItem) { _, newItem in
        Task {
          guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
          avatarImageData = ImageCropping.squareCroppedJPEGData(from: data) ?? data
        }
      }
    }
  }

  @ViewBuilder
  private var avatarPreview: some View {
    HStack {
      Spacer()
      Group {
        if let avatarImageData, let uiImage = UIImage(data: avatarImageData) {
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
      .frame(width: 88, height: 88)
      .clipShape(Circle())
      Spacer()
    }
  }

  private var joinedText: String? {
    guard let date = DateFormatting.isoDate(from: profile.joinedAt) else { return nil }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private var plusText: String? {
    guard let date = DateFormatting.isoDate(from: profile.plusStartedAt) else { return nil }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func save() {
    profile.name = name.trimmingCharacters(in: .whitespaces)
    profile.username = username.trimmingCharacters(in: .whitespaces)
    profile.avatarImageData = avatarImageData
    try? viewContext.save()
    dismiss()
  }
}
