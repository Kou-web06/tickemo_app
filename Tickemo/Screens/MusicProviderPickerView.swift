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

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Preferred service for links")
          .font(.system(size: 14, weight: .medium))
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

        Text("The selected service is used for song links and artist page navigation.")
          .font(.system(size: 12))
          .lineSpacing(4)
          .foregroundStyle(palette.secondaryText)
          .padding(.top, 14)
          .padding(.horizontal, 8)
      }
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 36)
    }
    .background(palette.screenBackground.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) { header }
  }

  private var header: some View {
    ZStack {
      HStack {
        Button {
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(palette.primaryText)
            .frame(width: 44, height: 44)
        }
        Spacer()
        Color.clear.frame(width: 44, height: 44)
      }
      Text("Music Provider")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(palette.titleText)
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 16)
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

  private func optionRow(title: String, tint: Color, value: MusicProviderPreference) -> some View {
    Button {
      select(value)
    } label: {
      HStack(spacing: 10) {
        radioCircle(isSelected: selection == value)
        Image(systemName: "music.note")
          .font(.system(size: 20))
          .foregroundStyle(tint)
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(palette.primaryText)
        Spacer()
        if selection == value {
          Image(systemName: "checkmark")
            .font(.system(size: 20))
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
    if HapticsPreferenceService.shared.isEnabled {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    dismiss()
  }
}
