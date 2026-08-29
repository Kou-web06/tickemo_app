import SwiftUI

struct BgColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFontChoice) private var appFont
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBgColor) private var bgColor
    @AppStorage(AppBgColorService.userDefaultsKey) private var stored: String = AppBgColorChoice.system.rawValue

    private var selected: AppBgColorChoice {
        AppBgColorChoice(rawValue: stored) ?? .system
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]
    private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(AppBgColorChoice.allCases) { choice in
                        swatchView(choice)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .background((bgColor ?? Color(.systemBackground)).ignoresSafeArea())
            .navigationTitle("背景カラー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .font(appFont.bold(14))
                }
            }
        }
    }

    private func swatchView(_ choice: AppBgColorChoice) -> some View {
        let isSelected = selected == choice
        let isDark = colorScheme == .dark
        let fill = choice.swatchColor(isDark: isDark)

        return Button {
            HapticsPreferenceService.shared.impact(.light)
            AppBgColorService.shared.selectedColor = choice
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(isDark ? 0.4 : 0.1), radius: 6, x: 0, y: 2)
                        .overlay {
                            Circle()
                                .stroke(
                                    isSelected ? accentPurple : Color(.separator).opacity(0.3),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        }

                    if choice == .system {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color(.label).opacity(0.35))
                    }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accentPurple)
                    }
                }

                Text(choice.displayName)
                    .font(appFont.regular(12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
