import SwiftUI

/// Ports lib/themePreference.ts's manual dark-mode override — a tri-state
/// preference (unset / light / dark), applied app-wide via
/// `.preferredColorScheme(...)` at the root `WindowGroup`.
///
/// RN's own `isDarkMode = manualDarkMode ?? false` never actually
/// consults the system appearance when unset — it collapses "no
/// preference" to hard-coded light mode everywhere it's read (confirmed
/// across all 6 RN screens that use this preference). That's judged to be
/// an RN bug, not a deliberate design choice, so it's deliberately NOT
/// replicated here: `colorScheme` returns `nil` when unset, which lets
/// `.preferredColorScheme(nil)` follow the system appearance as a user
/// would expect.
@Observable
final class ThemePreferenceService {
  static let shared = ThemePreferenceService()

  private static let defaultsKey = "themeDarkModeOverride"

  /// `nil` = no manual override (follow system). Mirrors RN's
  /// `boolean | null` cached preference.
  private(set) var manualDarkMode: Bool?

  private init() {
    if let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool {
      manualDarkMode = stored
    } else {
      manualDarkMode = nil
    }
  }

  /// `nil` here means "follow system" — deliberately not collapsed to
  /// `.light`, unlike RN (see type doc-comment).
  var colorScheme: ColorScheme? {
    guard let manualDarkMode else { return nil }
    return manualDarkMode ? .dark : .light
  }

  func setManualDarkMode(_ value: Bool) {
    manualDarkMode = value
    UserDefaults.standard.set(value, forKey: Self.defaultsKey)
  }

  /// The dark-mode toggle row needs a concrete on/off state to render even
  /// when there's no manual override — falls back to the system's current
  /// appearance (read from the view via `@Environment(\.colorScheme)`,
  /// since that's not available outside a View) rather than RN's
  /// hard-coded-light collapse.
  func effectiveIsDark(systemIsDark: Bool) -> Bool {
    manualDarkMode ?? systemIsDark
  }
}
