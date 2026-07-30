import SwiftUI
import UIKit

/// Wraps `UIVisualEffectView`/`UIBlurEffect` for the glass headers used
/// across the rebuilt Settings screens (Settings/ProfileEdit/
/// MusicProviderPicker/LanguagePicker/FAQ/ICloudSyncStatus) — ports RN's
/// `BlurView tint intensity={80}`. SwiftUI's `.ultraThinMaterial`/
/// `.regularMaterial` don't let intensity be parameterized directly, so
/// this is a small UIKit bridge rather than an approximation.
struct BlurEffectView: UIViewRepresentable {
  var style: UIBlurEffect.Style

  func makeUIView(context: Context) -> UIVisualEffectView {
    UIVisualEffectView(effect: UIBlurEffect(style: style))
  }

  func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
    uiView.effect = UIBlurEffect(style: style)
  }
}
