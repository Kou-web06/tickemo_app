import SwiftUI
import UIKit

/// Ports screens/SettingsScreen.tsx's `MusicProviderScreen` — a
/// persisted-only preference for parity purposes (see
/// `MusicProviderPreference.swift`'s doc-comment: `RecordDetailView`'s own
/// tap-to-play fallback keeps its existing "always ask" dialog rather than
/// reading this).
struct MusicProviderPickerView: View {
  @Binding var selection: MusicProviderPreference

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

  @Environment(\.appFontChoice) private var appFont
  @Environment(\.appBgColor) private var bgColor

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("デフォルトで開くアプリ")
            .font(appFont.regular(14))
            .foregroundStyle(palette.tertiaryText)
            .padding(.leading, 8)
            .padding(.bottom, 10)

          VStack(spacing: 0) {
            optionRow(title: "Apple Music", tint: Color(hex: "#FA243C"), value: .apple)
            Rectangle().fill(palette.rowBorder).frame(height: 0.5)
            optionRow(title: "Spotify", tint: Color(hex: "#1DB954"), value: .spotify)
          }
          .background(palette.cardBackground)
          .clipShape(RoundedRectangle(cornerRadius: 20))
          .shadow(color: palette.sectionShadow.opacity(0.16), radius: 8, x: 0, y: 2)

          Text("選択されたアプリは、楽曲のリンクやアーティストページの移動に使用されます。")
            .font(appFont.regular(12))
            .lineSpacing(4)
            .foregroundStyle(palette.secondaryText)
            .padding(.top, 14)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 36)
      }
      .background((bgColor ?? palette.screenBackground).ignoresSafeArea())
      .navigationTitle("音楽プロバイダー")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            HugeIconView(icon: HugeIcons.arrowLeft01, size: 20, weight: 2)
          }
        }
      }
    }
    // Two rows and a caption — showing this at full sheet height leaves a
    // huge dead area below, so it gets its own tight-fitting detent instead
    // of the default full-height sheet.
    .presentationDetents([.height(360), .medium])
    .presentationDragIndicator(.visible)
  }

  private func optionRow(title: String, tint: Color, value: MusicProviderPreference) -> some View {
    Button {
      select(value)
    } label: {
      HStack(spacing: 10) {
        radioCircle(isSelected: selection == value)
        HugeIconView(icon: HugeIcons.musicNote01, size: 20)
          .foregroundStyle(tint)
        Text(title)
          .font(appFont.bold(15))
          .foregroundStyle(palette.primaryText)
        Spacer()
        if selection == value {
          HugeIconView(icon: HugeIcons.tick02, size: 20)
            .foregroundStyle(palette.primaryText)
        }
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func radioCircle(isSelected: Bool) -> some View {
    Circle()
      .strokeBorder(isSelected ? palette.primaryText : palette.secondaryText, lineWidth: 1.4)
      .frame(width: 18, height: 18)
      .overlay {
        if isSelected {
          Circle().fill(palette.primaryText).frame(width: 8, height: 8)
        }
      }
  }

  private func select(_ value: MusicProviderPreference) {
    selection = value
    MusicProviderPreferenceStore.save(value)
    HapticsPreferenceService.shared.notify(.success)
    dismiss()
  }
}
