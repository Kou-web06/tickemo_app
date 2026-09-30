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
  @State private var seatAnnounce = LiveNotificationSettings.shared.isEnabled(.seatAnnounce)
  @State private var ticketApply = LiveNotificationSettings.shared.isEnabled(.ticketApply)
  @State private var paymentDue = LiveNotificationSettings.shared.isEnabled(.paymentDue)
  @State private var showingPaywall = false

  private var isPremium: Bool { PurchasesService.shared.isPremium }

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }
  private let accent = Color(hex: "#9A7CF8")

  @Environment(\.appFontChoice) private var appFont
  @Environment(\.appBgColor) private var bgColor

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("下記の通知タイプを設定できます。新規登録時に自動でスケジュールされます。")
            .font(appFont.regular(12))
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

          ticketScheduleSection
            .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 36)
      }
      .background((bgColor ?? palette.screenBackground).ignoresSafeArea())
      .navigationTitle("通知設定")
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
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
    // チケットの予定の3項目を足したぶん高さを広げた（元は 420pt）
    .presentationDetents([.height(680), .large])
    .presentationDragIndicator(.visible)
  }

  // MARK: - チケットの予定（Plus）

  private var ticketScheduleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Text("チケットの予定")
          .font(appFont.bold(13))
          .foregroundStyle(palette.primaryText)
        Text("Plus")
          .font(appFont.bold(10))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(accent))
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 4)

      Text("チケットの編集画面で入力した日時をもとに通知します。")
        .font(appFont.regular(12))
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 8)
        .padding(.bottom, 14)

      VStack(spacing: 0) {
        toggleRow(
          title: "座席発表",
          desc: "座席がわかる時刻に通知します",
          isOn: $seatAnnounce,
          kind: .seatAnnounce
        )
        Rectangle().fill(palette.rowBorder).frame(height: 0.5)
        toggleRow(
          title: "チケット申込",
          desc: "申込の30分前に通知します",
          isOn: $ticketApply,
          kind: .ticketApply
        )
        Rectangle().fill(palette.rowBorder).frame(height: 0.5)
        toggleRow(
          title: "支払い期限",
          desc: "期限の前日19時と3時間前に通知します",
          isOn: $paymentDue,
          kind: .paymentDue
        )
      }
      .disabled(!isPremium)
      .opacity(isPremium ? 1 : 0.5)
      .background(palette.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .shadow(color: palette.sectionShadow.opacity(0.16), radius: 8, x: 0, y: 2)
      .overlay {
        // Plus でない場合はカード全体を購入画面への入口にする
        if !isPremium {
          Button {
            showingPaywall = true
          } label: {
            Color.clear.contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Plusでチケットの予定の通知を使う")
        }
      }
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
          .font(appFont.bold(15))
          .foregroundStyle(palette.primaryText)
        Text(desc)
          .font(appFont.regular(12))
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
