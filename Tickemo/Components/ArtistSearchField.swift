import SwiftUI
import MusicKit
import UIKit

/// Ports components/ArtistInput.tsx: the RecordFormView artist field is the
/// canonical capture point for an artist's official MusicKit photo — once a
/// suggestion is picked here, `imageUrl` is saved on the record and every
/// other screen (Statistics TOP/ALL ARTISTS, ArtistDetail hero, Collection
/// artist grid) can display it instead of falling back to a placeholder.
/// Three states, matching RN: unselected search bar, dropdown while results
/// are in, and a selected "chip" with a clear (x) button.
struct ArtistSearchField: View {
  @Binding var name: String
  @Binding var imageUrl: String?

  @State private var searchTerm = ""
  @State private var suggestions: [AppleMusicService.ArtistResult] = []
  @State private var isSearching = false
  @State private var searchTask: Task<Void, Never>?
  // Re-read after every search attempt (see scheduleSearch) since
  // AppleMusicService.searchArtists silently swallows the specific
  // .permissionDenied error — without this, a denied/restricted Apple
  // Music permission looks identical to "no matching artists" and the
  // user has no way to tell why photos never show up.
  @State private var authorizationStatus = MusicAuthorization.currentStatus

  private let service = AppleMusicService()

  var body: some View {
    Group {
      if !name.isEmpty {
        selectedChip
      } else {
        VStack(alignment: .leading, spacing: 8) {
          searchBar
          if authorizationStatus == .denied || authorizationStatus == .restricted {
            authorizationWarning
          }
          if !suggestions.isEmpty {
            dropdown
          }
        }
      }
    }
    .task {
      // Request access as soon as the field appears, rather than waiting
      // for the user's first keystroke to discover (mid-typing) that a
      // system permission sheet is about to interrupt them.
      if authorizationStatus == .notDetermined {
        _ = await service.authorize()
      }
      authorizationStatus = MusicAuthorization.currentStatus
    }
  }

  private var authorizationWarning: some View {
    HStack(spacing: 8) {
      HugeIconView(icon: HugeIcons.alert01, size: 17)
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text("Apple Musicへのアクセスがオフです")
          .font(.system(size: 13, weight: .semibold))
        Text("アーティスト写真を検索するには設定でオンにしてください。")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Button("設定を開く") {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
      }
      .font(.system(size: 13, weight: .semibold))
      .buttonStyle(.plain)
      .foregroundStyle(.blue)
    }
    .padding(.vertical, 4)
  }

  private var selectedChip: some View {
    HStack(spacing: 12) {
      thumbnail(urlString: imageUrl, size: 40)
      Text(name)
        .font(.system(size: 16, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 8)
      Button {
        name = ""
        imageUrl = nil
        searchTerm = ""
      } label: {
        HugeIconView(icon: HugeIcons.cancelCircle, size: 20)
          .foregroundStyle(Color(white: 0.6))
      }
      .buttonStyle(.plain)
    }
  }

  private var searchBar: some View {
    HStack(spacing: 8) {
      HugeIconView(icon: HugeIcons.search01, size: 18)
        .foregroundStyle(Color(white: 0.6))
      TextField("アーティストを検索", text: $searchTerm)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .onChange(of: searchTerm) { _, newValue in
          scheduleSearch(term: newValue)
        }
      if isSearching {
        ProgressView()
      }
    }
  }

  private var dropdown: some View {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(suggestions, id: \.id) { artist in
          Button {
            select(artist)
          } label: {
            HStack(spacing: 12) {
              thumbnail(urlString: artist.imageUrl, size: 44)
              Text(artist.name)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
              Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          if artist.id != suggestions.last?.id {
            Divider()
          }
        }
      }
    }
    .frame(maxHeight: 300)
  }

  private func thumbnail(urlString: String?, size: CGFloat) -> some View {
    Group {
      // RN's ArtistInput resolves artwork to 80px for both the dropdown rows
      // and the selected chip — same fixed size regardless of the thumbnail's
      // on-screen point size here.
      if let urlString, let url = URL(string: AppleMusicService.resolvedArtworkURL(urlString, size: 80)) {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          placeholderIcon(size: size)
        }
      } else {
        placeholderIcon(size: size)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  private func placeholderIcon(size: CGFloat) -> some View {
    ZStack {
      Color(.tertiarySystemBackground)
      HugeIconView(icon: HugeIcons.user, size: size * 0.5)
        .foregroundStyle(Color(white: 0.6))
    }
  }

  private func scheduleSearch(term: String) {
    searchTask?.cancel()
    let trimmed = term.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      suggestions = []
      isSearching = false
      return
    }
    isSearching = true
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled else { return }
      let results = (try? await service.searchArtists(term: trimmed)) ?? []
      guard !Task.isCancelled else { return }
      suggestions = results
      isSearching = false
      authorizationStatus = MusicAuthorization.currentStatus
    }
  }

  private func select(_ artist: AppleMusicService.ArtistResult) {
    name = artist.name
    imageUrl = artist.imageUrl.isEmpty ? nil : artist.imageUrl
    searchTerm = ""
    suggestions = []
  }
}
