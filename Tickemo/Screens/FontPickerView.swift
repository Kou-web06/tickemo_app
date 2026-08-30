import SwiftUI

private let fontPickerAccent = Color(red: 0.604, green: 0.486, blue: 0.973)

struct FontPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.appBgColor) private var bgColor
    @Environment(\.appCardBgColor) private var cardBgColor
    @State private var selected: AppFontChoice = FontPreferenceService.shared.selectedFont

    private var isDarkMode: Bool {
        ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
    }
    private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(AppFontChoice.allCases) { choice in
                        fontRow(choice)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background((bgColor ?? palette.screenBackground).ignoresSafeArea())
            .navigationTitle("フォント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        HugeIconView(icon: HugeIcons.cancel01, size: 17)
                    }
                }
            }
        }
    }

    private func fontRow(_ choice: AppFontChoice) -> some View {
        let isSelected = selected == choice
        return Button {
            HapticsPreferenceService.shared.impact(.light)
            selected = choice
            FontPreferenceService.shared.selectedFont = choice
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(choice.displayName)
                        .font(choice.bold(17))
                        .foregroundStyle(palette.primaryText)
                    Text(choice.sampleText)
                        .font(choice.regular(13))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(fontPickerAccent)
                } else {
                    Circle()
                        .stroke(palette.rowBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(isSelected ? fontPickerAccent.opacity(0.08) : (cardBgColor ?? palette.cardBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? fontPickerAccent.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: palette.sectionShadow.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
