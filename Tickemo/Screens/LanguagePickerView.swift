import SwiftUI
import UIKit

/// Ports screens/SettingsScreen.tsx's `LanguageScreen` — Settings-row-only
/// per the approved scope (see `LanguagePreference.swift`'s doc-comment):
/// persists a choice, but nothing else in the native app reads it yet
/// (no i18n infrastructure exists for any other screen).
struct LanguagePickerView: View {
  @Binding var selection: LanguagePreference

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  private let options: [(value: LanguagePreference, label: String)] = [
    (.system, "System Default"),
    (.ja, "日本語"),
    (.en, "English"),
  ]

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Select display language")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(palette.tertiaryText)
          .padding(.leading, 8)
          .padding(.bottom, 10)

        VStack(spacing: 0) {
          ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
            optionRow(title: option.label, value: option.value)
            if index < options.count - 1 {
              Rectangle().fill(palette.rowBorder).frame(height: 0.5)
            }
          }
        }
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: palette.sectionShadow.opacity(0.16), radius: 8, x: 0, y: 2)

        Text("Changing the language affects how artist and song names appear in search results.")
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
          HugeIconView(icon: HugeIcons.arrowLeft01, size: 22, weight: 2)
            .foregroundStyle(palette.primaryText)
            .frame(width: 44, height: 44)
        }
        Spacer()
        Color.clear.frame(width: 44, height: 44)
      }
      Text("Language")
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

  private func optionRow(title: String, value: LanguagePreference) -> some View {
    Button {
      select(value)
    } label: {
      HStack(spacing: 10) {
        radioCircle(isSelected: selection == value)
        Text(title)
          .font(.system(size: 15, weight: .bold))
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

  private func select(_ value: LanguagePreference) {
    selection = value
    LanguagePreferenceStore.save(value)
    if HapticsPreferenceService.shared.isEnabled {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    dismiss()
  }
}
