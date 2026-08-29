import SwiftUI

enum AppBgColorChoice: String, CaseIterable, Identifiable {
    case system
    case warmCream
    case peach
    case lavender
    case sage
    case mint
    case sky
    case rose
    case sand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:    "デフォルト"
        case .warmCream: "クリーム"
        case .peach:     "ピーチ"
        case .lavender:  "ラベンダー"
        case .sage:      "セージ"
        case .mint:      "ミント"
        case .sky:       "スカイ"
        case .rose:      "ローズ"
        case .sand:      "サンド"
        }
    }

    func resolved(isDark: Bool) -> Color? {
        guard self != .system else { return nil }
        switch self {
        case .warmCream: return Color(hex: isDark ? "#28241E" : "#F7F3EC")
        case .peach:     return Color(hex: isDark ? "#2E1F1A" : "#FAE5D8")
        case .lavender:  return Color(hex: isDark ? "#211D2B" : "#EEE9F7")
        case .sage:      return Color(hex: isDark ? "#1C2420" : "#E6EDE8")
        case .mint:      return Color(hex: isDark ? "#1A2C26" : "#D6F0E8")
        case .sky:       return Color(hex: isDark ? "#1A2030" : "#E6EEF9")
        case .rose:      return Color(hex: isDark ? "#2B1D20" : "#F9E6EA")
        case .sand:      return Color(hex: isDark ? "#28251A" : "#F5EDD6")
        case .system:    return nil
        }
    }

    // Slightly tinted card surface that coordinates with the screen background
    func cardBackground(isDark: Bool) -> Color? {
        guard self != .system else { return nil }
        switch self {
        case .warmCream: return Color(hex: isDark ? "#33302A" : "#FEFCF6")
        case .peach:     return Color(hex: isDark ? "#38281F" : "#FEF5F0")
        case .lavender:  return Color(hex: isDark ? "#2C2938" : "#FAFAFF")
        case .sage:      return Color(hex: isDark ? "#252D29" : "#F8FCF9")
        case .mint:      return Color(hex: isDark ? "#1E3530" : "#EDFAF5")
        case .sky:       return Color(hex: isDark ? "#222B3D" : "#F7FAFF")
        case .rose:      return Color(hex: isDark ? "#372729" : "#FFF7F8")
        case .sand:      return Color(hex: isDark ? "#332E1F" : "#FDF8EE")
        case .system:    return nil
        }
    }

    func swatchColor(isDark: Bool) -> Color {
        resolved(isDark: isDark) ?? Color(.systemBackground)
    }
}

// MARK: - Persistence

final class AppBgColorService {
    static let shared = AppBgColorService()
    static let userDefaultsKey = "appBgColor"
    private init() {}

    var selectedColor: AppBgColorChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
                  let choice = AppBgColorChoice(rawValue: raw) else { return .system }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - SwiftUI Environment

private struct AppBgColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct AppCardBgColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var appBgColor: Color? {
        get { self[AppBgColorKey.self] }
        set { self[AppBgColorKey.self] = newValue }
    }

    var appCardBgColor: Color? {
        get { self[AppCardBgColorKey.self] }
        set { self[AppCardBgColorKey.self] = newValue }
    }
}

private struct AppBgColorModifier: ViewModifier {
    @AppStorage(AppBgColorService.userDefaultsKey)
    private var stored: String = AppBgColorChoice.system.rawValue
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let choice = AppBgColorChoice(rawValue: stored) ?? .system
        let dark = scheme == .dark
        return content
            .environment(\.appBgColor, choice.resolved(isDark: dark))
            .environment(\.appCardBgColor, choice.cardBackground(isDark: dark))
    }
}

extension View {
    func withAppBgColor() -> some View {
        modifier(AppBgColorModifier())
    }
}
