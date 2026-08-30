import SwiftUI

enum AppFontChoice: String, CaseIterable, Identifiable {
    case system
    case zenMaruGothic = "ZenMaruGothic"
    case shipporiMincho = "ShipporiMincho"
    case kaiseiDecol = "KaiseiDecol"
    case dotGothic16 = "DotGothic16"
    case yuseiMagic = "YuseiMagic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "デフォルト"
        case .zenMaruGothic: "ぜんまるごしっく"
        case .shipporiMincho: "しっぽり明朝"
        case .kaiseiDecol: "かいせいデコール"
        case .dotGothic16: "ドットゴシック"
        case .yuseiMagic: "遊星マジック"
        }
    }

    var sampleText: String { "ライブの思い出を記録" }

    func regular(_ size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size)
        case .zenMaruGothic: .custom("ZenMaruGothic-Regular", size: size)
        case .shipporiMincho: .custom("ShipporiMincho-Regular", size: size)
        case .kaiseiDecol: .custom("KaiseiDecol-Regular", size: size)
        case .dotGothic16: .custom("DotGothic16-Regular", size: size)
        case .yuseiMagic: .custom("YuseiMagic-Regular", size: size)
        }
    }

    func bold(_ size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size, weight: .bold)
        case .zenMaruGothic: .custom("ZenMaruGothic-Bold", size: size)
        case .shipporiMincho: .custom("ShipporiMincho-Bold", size: size)
        case .kaiseiDecol: .custom("KaiseiDecol-Bold", size: size)
        case .dotGothic16: .custom("DotGothic16-Regular", size: size)
        case .yuseiMagic: .custom("YuseiMagic-Regular", size: size)
        }
    }

    // UIKit equivalent — used for UINavigationBarAppearance
    func uiFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        switch self {
        case .system:
            return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        case .zenMaruGothic:
            return UIFont(name: bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular", size: size)
                ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        case .shipporiMincho:
            return UIFont(name: bold ? "ShipporiMincho-Bold" : "ShipporiMincho-Regular", size: size)
                ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        case .kaiseiDecol:
            return UIFont(name: bold ? "KaiseiDecol-Bold" : "KaiseiDecol-Regular", size: size)
                ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
        case .dotGothic16:
            return UIFont(name: "DotGothic16-Regular", size: size) ?? .systemFont(ofSize: size)
        case .yuseiMagic:
            return UIFont(name: "YuseiMagic-Regular", size: size) ?? .systemFont(ofSize: size)
        }
    }
}

// MARK: - Persistence

final class FontPreferenceService {
    static let shared = FontPreferenceService()
    static let userDefaultsKey = "appFontChoice"
    private init() {}

    var selectedFont: AppFontChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
                  let choice = AppFontChoice(rawValue: raw) else { return .system }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - SwiftUI Environment

private struct AppFontChoiceKey: EnvironmentKey {
    static let defaultValue: AppFontChoice = .system
}

extension EnvironmentValues {
    var appFontChoice: AppFontChoice {
        get { self[AppFontChoiceKey.self] }
        set { self[AppFontChoiceKey.self] = newValue }
    }
}

// Reads from @AppStorage so any UserDefaults write by FontPreferenceService
// triggers an immediate environment re-propagation to all descendant views,
// and also updates UINavigationBarAppearance for navigation titles.
private struct AppFontEnvironmentModifier: ViewModifier {
    @AppStorage(FontPreferenceService.userDefaultsKey)
    private var storedFont: String = AppFontChoice.system.rawValue

    private var fontChoice: AppFontChoice {
        AppFontChoice(rawValue: storedFont) ?? .system
    }

    func body(content: Content) -> some View {
        content
            .environment(\.appFontChoice, fontChoice)
            .onChange(of: storedFont, initial: true) { _, _ in
                applyNavigationBarFont(fontChoice)
            }
    }

    private func applyNavigationBarFont(_ choice: AppFontChoice) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        if choice != .system {
            appearance.largeTitleTextAttributes = [
                .font: choice.uiFont(34, bold: true)
            ]
            appearance.titleTextAttributes = [
                .font: choice.uiFont(17, bold: true)
            ]
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Refresh currently visible navigation bars
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.navigationController?.navigationBar
                    .setNeedsLayout()
            }
        }
    }
}

extension View {
    func withAppFont() -> some View {
        modifier(AppFontEnvironmentModifier())
    }
}
