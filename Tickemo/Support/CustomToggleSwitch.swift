import SwiftUI

/// Ports screens/SettingsScreen.tsx's `CustomThemeToggle` — a fully custom
/// animated pill switch (not `Toggle(.switch)`). Track 60x32, cornerRadius
/// 16, 2pt padding; thumb 28x28 white circle with a subtle drop shadow;
/// track background color and thumb x-offset both animate together.
/// RN's curve is `Easing.out(Easing.cubic)` over 220ms — `.timingCurve`
/// reproduces that exact cubic-bezier rather than approximating with the
/// built-in `.easeOut`.
struct CustomToggleSwitch: View {
  var isOn: Bool
  var showIcons: Bool = true
  var trackOnColor: Color = Color(hex: "#333333")
  var trackOffColor: Color = Color(hex: "#8B5CF6")
  var onToggle: () -> Void

  private static let animation = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.22)

  var body: some View {
    Button(action: onToggle) {
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 16)
          .fill(isOn ? trackOnColor : trackOffColor)
          .frame(width: 60, height: 32)
          .animation(Self.animation, value: isOn)

        if showIcons {
          HStack {
            Image(systemName: "sun.max.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 14)
            Spacer()
            Image(systemName: "moon.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 14)
          }
          .padding(.horizontal, 8)
          .frame(width: 60, height: 32)
          .allowsHitTesting(false)
        }

        Circle()
          .fill(Color.white)
          .frame(width: 28, height: 28)
          .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
          .offset(x: isOn ? 30 : 2)
          .animation(Self.animation, value: isOn)
      }
    }
    .buttonStyle(.plain)
  }
}
