import SwiftUI

/// Ports screens/SettingsScreen.tsx's `buildPalette(isDarkMode, primaryColor)`.
/// `switchThumb`/`switchTrackOff`/`switchTrackOn` are deliberately omitted:
/// confirmed dead in the RN source (never read outside `buildPalette`
/// itself) — `CustomToggleSwitch`'s actual colors are literal per-call-site
/// values, not palette-driven, and this port matches that.
struct SettingsPalette {
  let screenBackground: Color
  let cardBackground: Color
  let mutedCardBackground: Color
  let titleText: Color
  let primaryText: Color
  let secondaryText: Color
  let tertiaryText: Color
  let subtleText: Color
  let destructiveText: Color
  let rowBorder: Color
  let iconColor: Color
  let avatarRingBackground: Color
  let avatarFallbackBackground: Color
  let avatarFallbackText: Color
  let freeBadgeBackground: Color
  let freeBadgeText: Color
  let profileEditIcon: Color
  let sectionShadow: Color
  let paywallGradientStart: Color
  let paywallGradientEnd: Color
  let paywallCaption: Color
  let paywallTitle: Color
  let paywallAction: Color
  let plusGradientStart: Color
  let plusGradientEnd: Color
  let plusText: Color
  let faqQuestionLabel: Color
  let faqAnswerLabel: Color

  init(isDarkMode: Bool) {
    screenBackground = isDarkMode ? Color(hex: "#121212") : Color(hex: "#F3F2F8")
    cardBackground = isDarkMode ? Color(hex: "#1A1A1A") : Color(hex: "#FFFFFF")
    mutedCardBackground = isDarkMode ? Color(hex: "#202024") : Color(hex: "#F0F0F0")
    titleText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#333333")
    primaryText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
    secondaryText = isDarkMode ? Color(hex: "#A1A1AA") : Color(hex: "#8E8E93")
    tertiaryText = isDarkMode ? Color(hex: "#8A8A94") : Color(hex: "#9A9A9A")
    subtleText = isDarkMode ? Color(hex: "#B7B7C2") : Color(hex: "#666666")
    destructiveText = Color(hex: "#FF453A")
    rowBorder = isDarkMode ? Color(hex: "#2E2E35") : Color(hex: "#E8E8E8")
    iconColor = isDarkMode ? Color(hex: "#A8A8B4") : Color(hex: "#8E8E96")
    avatarRingBackground = isDarkMode ? Color(hex: "#222227") : Color(hex: "#FFFFFF")
    avatarFallbackBackground = isDarkMode ? Color(hex: "#313643") : Color(hex: "#D9DEE8")
    avatarFallbackText = isDarkMode ? Color(hex: "#E8EBF4") : Color(hex: "#3B4454")
    freeBadgeBackground = isDarkMode ? Color(hex: "#2D2D34") : Color(hex: "#E7E7E7")
    freeBadgeText = isDarkMode ? Color(hex: "#CFCFDD") : Color(hex: "#5A5A5A")
    profileEditIcon = isDarkMode ? Color(hex: "#DADAE6") : Color(hex: "#2F2F2F")
    sectionShadow = isDarkMode ? Color(hex: "#000000") : Color(hex: "#D2D2D2")
    paywallGradientStart = Color(hex: "#2B2B2B")
    paywallGradientEnd = Color(hex: "#121212")
    paywallCaption = Color.white.opacity(0.72)
    paywallTitle = Color(hex: "#FFFFFF")
    paywallAction = Color(hex: "#8FE58C")
    plusGradientStart = Color(hex: "#8FE58C")
    plusGradientEnd = Color(hex: "#8872F8")
    plusText = Color(hex: "#FFFFFF")
    faqQuestionLabel = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
    faqAnswerLabel = isDarkMode ? Color(hex: "#BCBCC8") : Color(hex: "#666666")
  }
}

/// Ports screens/ICloudSyncScreen.tsx's own smaller `buildPalette` — note
/// `screenBackground` here (`#F2F2F7` light) differs from `SettingsPalette`'s
/// (`#F8F8F8`), so this is intentionally a separate struct, not a subset.
struct ICloudSyncPalette {
  let screenBackground: Color
  let titleText: Color
  let cardBackground: Color
  let shadowColor: Color
  let statusLabel: Color
  let statusText: Color
  let descriptionText: Color
  let syncTimeText: Color
  let buttonText: Color
  let indicatorColor: Color
  let success: Color

  init(isDarkMode: Bool) {
    screenBackground = isDarkMode ? Color(hex: "#121212") : Color(hex: "#F2F2F7")
    titleText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
    cardBackground = isDarkMode ? Color(hex: "#1A1A1A") : Color(hex: "#FFFFFF")
    shadowColor = isDarkMode ? Color(hex: "#000000") : Color(hex: "#5D5D5D")
    statusLabel = isDarkMode ? Color(hex: "#B7B7C2") : Color(hex: "#666666")
    statusText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
    descriptionText = isDarkMode ? Color(hex: "#A1A1AA") : Color(hex: "#888888")
    syncTimeText = isDarkMode ? Color(hex: "#8A8A94") : Color(hex: "#999999")
    buttonText = isDarkMode ? Color(hex: "#CFCFDD") : Color(hex: "#666666")
    indicatorColor = isDarkMode ? Color(hex: "#A1A1AA") : Color(hex: "#888888")
    success = Color(hex: "#34C759")
  }
}

/// Ports screens/ProfileEditScreen.tsx's own `buildPalette`.
struct ProfileEditPalette {
  let screenBackground: Color
  let primaryText: Color
  let cardBackground: Color
  let sectionShadow: Color
  let avatarBackground: Color
  let avatarFallbackBackground: Color
  let avatarText: Color
  let borderColor: Color
  let subText: Color
  let valueText: Color
  let inputBackground: Color
  let inputText: Color
  let placeholderText: Color
  let editIcon: Color
  let loadingIndicator: Color

  init(isDarkMode: Bool) {
    screenBackground = isDarkMode ? Color(hex: "#121212") : Color(hex: "#F8F8F8")
    primaryText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
    cardBackground = isDarkMode ? Color(hex: "#1A1A1A") : Color(hex: "#FFFFFF")
    sectionShadow = isDarkMode ? Color(hex: "#000000") : Color(hex: "#D2D2D2")
    avatarBackground = isDarkMode ? Color(hex: "#2B2B32") : Color(hex: "#111111")
    avatarFallbackBackground = isDarkMode ? Color(hex: "#3A3A45") : Color(hex: "#1F1F1F")
    avatarText = Color(hex: "#FFFFFF")
    borderColor = isDarkMode ? Color(hex: "#1A1A1A") : Color(hex: "#FFFFFF")
    subText = isDarkMode ? Color(hex: "#A1A1AA") : Color(hex: "#9A9A9A")
    valueText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#111111")
    inputBackground = isDarkMode ? Color(hex: "#26262C") : Color(hex: "#F5F5F5")
    inputText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#111111")
    placeholderText = isDarkMode ? Color(hex: "#8A8A94") : Color(hex: "#B8B8B8")
    editIcon = Color(hex: "#FFFFFF")
    loadingIndicator = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#000000")
  }
}

extension Color {
  /// Minimal `#RRGGBB` hex initializer — this project has no existing hex
  /// color helper, and this phase's palettes are transcribed directly from
  /// RN's hex literals, so a from-scratch parser is simpler than converting
  /// every value to `Color(red:green:blue:)` by hand.
  init(hex: String, opacity: Double = 1) {
    var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized.removeAll { $0 == "#" }
    var value: UInt64 = 0
    Scanner(string: sanitized).scanHexInt64(&value)
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    self.init(red: r, green: g, blue: b, opacity: opacity)
  }
}
