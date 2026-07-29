import SwiftUI
import Photos
import UIKit

enum ShareActionError: Error {
  case photoLibraryDenied
}

/// The three share destinations ported from ShareImageGenerator.tsx's
/// handleSaveImage/handleStoriesShare/handleSystemShare.
enum ShareActions {
  private static let instagramStoriesUTI = "com.instagram.sharedSticker.backgroundImage"

  /// Add-only Photos authorization + PHAssetCreationRequest — the native
  /// equivalent of expo-media-library's saveToLibraryAsync. Uses
  /// `.addOnly` (not full read/write) to match the existing
  /// NSPhotoLibraryAddUsageDescription already present in Info.plist.
  static func saveToPhotos(pngData: Data) async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      throw ShareActionError.photoLibraryDenied
    }
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, data: pngData, options: nil)
    }
  }

  /// Instagram's documented third-party Stories-sharing integration: set
  /// the image on the pasteboard under Instagram's own sticker UTI, then
  /// open the Stories composer via custom URL scheme. Two-step fallback
  /// (stories composer, then a plain app-open) matches RN's iOS fallback
  /// chain minus the Android-only branch. Returns false if Instagram isn't
  /// installed at all.
  @MainActor
  static func shareToInstagramStories(pngData: Data) -> Bool {
    UIPasteboard.general.setItems(
      [[instagramStoriesUTI: pngData]],
      options: [.expirationDate: Date().addingTimeInterval(300)]
    )

    guard let bundleID = Bundle.main.bundleIdentifier,
          let storiesURL = URL(string: "instagram-stories://share?source_application=\(bundleID)")
    else {
      return false
    }

    if UIApplication.shared.canOpenURL(storiesURL) {
      UIApplication.shared.open(storiesURL)
      return true
    }
    if let fallbackURL = URL(string: "instagram://"), UIApplication.shared.canOpenURL(fallbackURL) {
      UIApplication.shared.open(fallbackURL)
      return true
    }
    return false
  }
}

/// Wraps `UIActivityViewController` for the "other" system-share action.
/// SwiftUI's `ShareLink` doesn't cleanly support an image + separate
/// caption string combination for this use case, so this is the more
/// direct/idiomatic choice here.
struct ActivityShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
