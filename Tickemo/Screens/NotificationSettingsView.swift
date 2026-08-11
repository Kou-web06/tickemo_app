import SwiftUI

/// Ports screens/SettingsScreen.tsx's `NotificationSettingsScreen`. RN's
/// fourth toggle, "キャンペーン情報" (`campaigns`), is excluded — RN's own
/// scheduler never emits a target for it, so it's dead there too (same
/// precedent as excluding Collection's unreachable filter dropdown: match
/// the real behavior, not RN's own dead code).
struct NotificationSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  @State private var beforeLive = LiveNotificationSettings.shared.isEnabled(.beforeLive)
  @State private var onDay = LiveNotificationSettings.shared.isEnabled(.onDay)
  @State private var nextDayReview = LiveNotificationSettings.shared.isEnabled(.nextDayReview)

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }
  private let accent = Color(hex: "#9A7CF8")

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("下記の通知タイプを設定できます。新規登録時に自動でスケジュールされます。")
          .font(.system(size: 12))
          .lineSpacing(4)
          .foregroundStyle(palette.secondaryText)
          .padding(.horizontal, 8)
          .padding(.bottom, 14)

        VStack(spacing: 0) {
          toggleRow(
            title: "ライブ前日リマインド",
            desc: "ライブ前日の19時に通知します",
            isOn: $beforeLive,
            kind: .beforeLive
          )
          Rectangle().fill(palette.rowBorder).frame(height: 0.5)
          toggleRow(
            title: "ライブ当日リマインド",
            desc: "ライブ開始15分前に通知します",
            isOn: $onDay,
            kind: .onDay
          )
          Rectangle().fill(palette.rowBorder).frame(height: 0.5)
          toggleRow(
            title: "ライブ翌日の振り返り",
            desc: "ライブ翌日の10時に振り返り通知を送ります",
            isOn: $nextDayReview,
            kind: .nextDayReview
          )
        }
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: palette.sectionShadow.opacity(0.16), radius: 8, x: 0, y: 2)
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
      Text("通知設定")
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

  private func toggleRow(
    title: String,
    desc: String,
    isOn: Binding<Bool>,
    kind: LiveNotificationSettings.Kind
  ) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(palette.primaryText)
        Text(desc)
          .font(.system(size: 12))
          .foregroundStyle(palette.secondaryText)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: isOn)
        .labelsHidden()
        .tint(accent)
        .onChange(of: isOn.wrappedValue) { _, newValue in
          if newValue {
            LiveNotificationService.requestAuthorizationIfNeeded()
          }
          LiveNotificationSettings.shared.setEnabled(newValue, for: kind)
          HapticsPreferenceService.shared.impact(.light)
        }
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 64)
  }
}
