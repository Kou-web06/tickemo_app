import SwiftUI

/// Ports screens/CollectionScreen.tsx's `buildCollectionPalette(isDarkMode)`.
/// Only the keys actually read by live JSX are included — RN also defines
/// `searchFieldBackground`/`modalSurface`/`modalBorder`/`iconOnDark`/
/// `searchEmptyIcon`/`quickFilter*` for a search bar and filter dropdown
/// that migration research confirmed are unreachable dead code (no control
/// ever opens them), so those are deliberately not ported.
struct CollectionPalette {
  let screenBackground: Color
  let headerBackground: Color
  let headerBorder: Color
  let primaryText: Color
  let secondaryText: Color
  let tertiaryText: Color
  let emptyText: Color

  init(isDarkMode: Bool) {
    screenBackground = isDarkMode ? Color(hex: "#121212") : Color(hex: "#F3F2F8")
    headerBackground = isDarkMode ? Color(hex: "#121212", opacity: 0.74) : Color(hex: "#F3F2F8", opacity: 0.62)
    headerBorder = .clear
    primaryText = isDarkMode ? Color(hex: "#F5F5F7") : Color(hex: "#333333")
    secondaryText = isDarkMode ? Color(hex: "#B7B7C2") : Color(hex: "#777777")
    tertiaryText = isDarkMode ? Color(hex: "#8A8A94") : Color(hex: "#8A8A8A")
    emptyText = isDarkMode ? Color(hex: "#A1A1AA") : Color(hex: "#555555")
  }
}
