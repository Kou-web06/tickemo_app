import SwiftUI
import RevenueCat
import Lottie

private let accentPurple = Color(hex: "#8B5CF6")
private let termsURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Terms-of-Use-2f65fd5d3e2d80ba8abcda85615cde4a?source=copy_link")!
private let privacyURL = URL(string: "https://traveling-fahrenheit-b9b.notion.site/Tickemo-Privacy-Policy-2f85fd5d3e2d809b912dfc4ec2a2ed6a?source=copy_link")!
private let defaultLifetimePriceValue = 480
private let defaultOriginalPriceValue = 980

private enum PaywallPalette {
  static let background = Color(hex: "#F8F8F8")
  static let textDark = Color(hex: "#333333")
  static let heroTitle = Color(hex: "#151515")
  static let plusPillBackground = Color(hex: "#F5F3FF")
  static let plusText = Color(hex: "#5B38B2")
  static let heroSubtitle = Color(hex: "#7A7A7A")
  static let earlyCountdown = Color(hex: "#C23A3A")
  static let featureIconDefault = Color(hex: "#1F1F1F")
  static let featureTitle = Color(hex: "#171717")
  static let featureDescription = Color(hex: "#7D7D7D")
  static let restoreText = Color(hex: "#4c4c4c")
  static let planCardBackground = Color(hex: "#F5F3FF")
  static let planTitle = Color(hex: "#111111")
  static let planSubTitle = Color(hex: "#7A7A7A")
  static let planOriginalPrice = Color(hex: "#9A9A9A")
  static let planCurrentPrice = Color(hex: "#181817")
  static let footerText = Color(hex: "#9A9A9A")
  static let footerSeparator = Color(hex: "#B0B0B0")
  static let patternRing = Color(hex: "#E6E6E6", opacity: 0.52)
}

private func formatJPYFallback(_ value: Int) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.groupingSeparator = ","
  return "￥" + (formatter.string(from: NSNumber(value: value)) ?? "\(value)")
}

/// Ports screens/PaywallScreen.tsx as closely as SwiftUI allows: same
/// concentric background rings, VIP pass illustration, hero/benefits copy,
/// and — the part most visibly missing before — a floating frosted "island"
/// bottom panel (blurred glass, rounded 38pt, drop shadow) holding the plan
/// card + CTA, instead of a flat edge-to-edge `.regularMaterial` bar.
/// Presented as a plain SwiftUI `.sheet` from callers; the
/// `.presentation*` modifiers below reproduce RN's 95%-height, 28pt
/// rounded-top bottom sheet without any custom modal chrome.
struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var package: Package?
  @State private var isLoadingOfferings = true
  @State private var isPurchasing = false
  @State private var isRestoring = false
  @State private var alertMessage: String?
  @State private var remainingSeconds: TimeInterval = EarlyOfferService.remainingSeconds()
  @State private var webViewURL: PaywallWebViewURL?

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private var isEarlyWindow: Bool { remainingSeconds > 0 }

  private enum BenefitIcon {
    case asset(String)
    case lottie(String)
  }

  private let benefits: [(icon: BenefitIcon, title: String, description: String)] = [
    (.asset("Ticket add"), "無制限のアーカイブ", "過去のチケットも写真もすべて保存。"),
    (.asset("disc"), "シェアカードの拡張", "ストーリーズで映える限定画像を無制限に生成。"),
    (.asset("Chart"), "レポートの全期間解放", "過去の年やAll-Timeのレポートも制限なく閲覧。"),
    (.asset("widget"), "ホーム画面ウィジェット", "次のライブまでのカウントダウンをホーム画面に表示。"),
    (.asset("letter-case"), "フォントのカスタマイズ", "8種類のフォントからアプリの雰囲気を自分好みに。"),
    (.asset("Rolling brush"), "背景カラーのカスタマイズ", "8種類のカラーテーマでアプリの見た目をデザイン。"),
    (.lottie("heart_like"), "開発者を応援", "今後のアップデートと新機能の開発をサポート"),
  ]

  private var currentPriceText: String {
    package?.storeProduct.localizedPriceString ?? formatJPYFallback(defaultLifetimePriceValue)
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    ZStack {
      PaywallPalette.background.ignoresSafeArea()

      GeometryReader { proxy in
        backgroundPattern(width: proxy.size.width)
      }
      .allowsHitTesting(false)

      ScrollView {
        VStack(spacing: 0) {
          Image("PaywallPass")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 300)
            .padding(.bottom, 24)

          heroSection
            .padding(.bottom, 18)

          benefitsSection
        }
        .padding(.bottom, 260)
      }
    }
    .overlay(alignment: .topLeading) {
      closeButton.padding(.leading, 8).padding(.top, 8)
    }
    .overlay(alignment: .topTrailing) {
      restoreButton.padding(.trailing, 12).padding(.top, 8)
    }
    .overlay(alignment: .bottom) {
      bottomIslandPanel
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    .presentationDetents([.fraction(0.95)])
    .presentationCornerRadius(28)
    .presentationDragIndicator(.hidden)
    .presentationBackground(PaywallPalette.background)
    .task {
      await loadOfferings()
    }
    .onReceive(timer) { _ in
      remainingSeconds = EarlyOfferService.remainingSeconds()
    }
    .sheet(item: $webViewURL) { wrapper in
      SafariView(url: wrapper.url)
    }
    .alert("お知らせ", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
      Button("OK") {}
    } message: {
      Text(alertMessage ?? "")
    }
  }

  // MARK: - Background

  private func backgroundPattern(width: CGFloat) -> some View {
    let patternSize = max(width * 1.35, 500)
    let patternStroke = max(width * 0.08, 48)
    return ZStack {
      Circle()
        .stroke(PaywallPalette.patternRing, lineWidth: patternStroke)
        .frame(width: patternSize, height: patternSize)
        .offset(x: patternSize * 0.80, y: -patternSize * 0.37)
      Circle()
        .stroke(PaywallPalette.patternRing, lineWidth: patternStroke)
        .frame(width: patternSize * 0.90, height: patternSize * 0.90)
        .offset(x: patternSize * 0.54, y: -patternSize * 0.56)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .clipped()
  }

  // MARK: - Top controls

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      HugeIconView(icon: HugeIcons.cancel01, size: 20, weight: 2.2)
        .foregroundStyle(PaywallPalette.textDark)
        .padding(8)
        .contentShape(Rectangle())
    }
  }

  private var restoreButton: some View {
    Button {
      Task { await handleRestore() }
    } label: {
      Text(isRestoring ? "復元中…" : "購入を復元")
        .font(appFont.bold(12))
        .foregroundStyle(PaywallPalette.restoreText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
          Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.58)))
            .overlay(Capsule().stroke(Color.white.opacity(0.84), lineWidth: 1))
        }
    }
    .disabled(isRestoring)
  }

  // MARK: - Hero

  private var heroSection: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text("Tickemo")
          .font(appFont.bold(34))
          .foregroundStyle(PaywallPalette.heroTitle)
          .tracking(0.3)
        Text("Plus")
          .font(appFont.bold(17))
          .foregroundStyle(PaywallPalette.plusText)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(PaywallPalette.plusPillBackground)
          .clipShape(Capsule())
          .overlay(Capsule().stroke(accentPurple, lineWidth: 1.5))
      }

      Text("全てのライブにこだわりをプラス。制限なしですべての機能にアクセスしよう")
        .font(appFont.bold(13))
        .foregroundStyle(PaywallPalette.heroSubtitle)
        .multilineTextAlignment(.center)
        .lineSpacing(7)
        .padding(.top, 10)

      if isEarlyWindow {
        Text("限定価格まで残り \(EarlyOfferService.format(remaining: remainingSeconds))")
          .font(appFont.bold(13))
          .foregroundStyle(PaywallPalette.earlyCountdown)
          .padding(.top, 6)
      }
    }
    .padding(.horizontal, 24)
  }

  // MARK: - Benefits

  private var benefitsSection: some View {
    VStack(spacing: 16) {
      ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
        HStack(alignment: .top, spacing: 12) {
          Group {
            switch benefit.icon {
            case .asset(let name):
              Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(PaywallPalette.featureIconDefault)
            case .lottie(let name):
              LottieView(animation: .named(name))
                .playing(loopMode: .loop)
                .frame(width: 28, height: 28)
            }
          }
          .frame(width: 34)
          .padding(.top, 1)

          VStack(alignment: .leading, spacing: 3) {
            Text(benefit.title)
              .font(appFont.bold(16))
              .foregroundStyle(PaywallPalette.featureTitle)
            Text(benefit.description)
              .font(appFont.regular(12))
              .foregroundStyle(PaywallPalette.featureDescription)
              .lineSpacing(5)
          }

          Spacer(minLength: 0)
        }
      }
    }
    .padding(.horizontal, 30)
  }

  // MARK: - Bottom island

  private var bottomIslandPanel: some View {
    VStack(spacing: 10) {
      planCard
      purchaseButton
      footerLinks
    }
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 38, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(Color.white.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous).stroke(Color.white.opacity(0.92), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 18, x: 0, y: 8)
    }
  }

  private var planCard: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 6) {
        Text("買い切り")
          .font(appFont.bold(15))
          .foregroundStyle(PaywallPalette.planTitle)
        Text("リリース記念価格・サブスクなし")
          .font(appFont.regular(10))
          .foregroundStyle(PaywallPalette.planSubTitle)
      }

      Spacer(minLength: 10)

      HStack(alignment: .lastTextBaseline, spacing: 6) {
        Text(formatJPYFallback(defaultOriginalPriceValue))
          .font(appFont.bold(14))
          .foregroundStyle(PaywallPalette.planOriginalPrice)
          .strikethrough()
        Text(currentPriceText)
          .font(appFont.bold(20))
          .foregroundStyle(PaywallPalette.planCurrentPrice)
      }
    }
    .padding(.vertical, 17)
    .padding(.horizontal, 17)
    .background(PaywallPalette.planCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(accentPurple, lineWidth: 2))
  }

  private var purchaseButton: some View {
    Button {
      Task { await handlePurchase() }
    } label: {
      HStack(spacing: 8) {
        if isPurchasing {
          ProgressView().tint(.white)
        }
        Text(isPurchasing ? "購入処理中..." : "続ける")
          .font(appFont.bold(17))
          .foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(accentPurple)
      .clipShape(Capsule())
    }
    .opacity(isPurchasing ? 0.7 : 1)
    .disabled(isPurchasing || isLoadingOfferings || package == nil)
  }

  private var footerLinks: some View {
    HStack(spacing: 8) {
      Button { webViewURL = PaywallWebViewURL(url: termsURL) } label: {
        Text("利用規約")
          .font(appFont.regular(10))
          .foregroundStyle(PaywallPalette.footerText)
      }
      Text("・")
        .font(appFont.regular(10))
        .foregroundStyle(PaywallPalette.footerSeparator)
      Button { webViewURL = PaywallWebViewURL(url: privacyURL) } label: {
        Text("プライバシーポリシー")
          .font(appFont.regular(10))
          .foregroundStyle(PaywallPalette.footerText)
      }
    }
    .padding(.top, 4)
  }

  // MARK: - Offerings

  private func loadOfferings() async {
    isLoadingOfferings = true
    defer { isLoadingOfferings = false }

    guard let offerings = try? await PurchasesService.shared.fetchOfferings() else { return }
    let packages = offerings.current?.availablePackages ?? []

    let preferredID = EarlyOfferService.isWithinEarlyWindow() ? "tickemo_plus_lifetime" : "tickemo_plus_lifetime_usual"
    package = packages.first {
      $0.identifier.lowercased() == preferredID || $0.storeProduct.productIdentifier.lowercased() == preferredID
    } ?? packages.first { $0.packageType == .lifetime } ?? packages.first
  }

  // MARK: - Purchase (ports PaywallScreen.tsx's handlePurchase/waitForPremiumGrant)

  private func handlePurchase() async {
    guard let package, !isPurchasing else { return }
    isPurchasing = true
    defer { isPurchasing = false }

    do {
      let result = try await PurchasesService.shared.purchase(package: package)
      if result.userCancelled { return }
      if PurchasesService.shared.isPremium {
        dismiss()
        return
      }
      if await waitForPremiumGrant() {
        dismiss()
        return
      }
      alertMessage = "購入確認を処理中です\nApple側の反映が遅れている可能性があります。数分後に「購入を復元」をお試しください。"
    } catch let error as ErrorCode where error == .purchaseCancelledError {
      return
    } catch let error as ErrorCode where error == .invalidReceiptError {
      _ = try? await PurchasesService.shared.syncPurchases()
      if await waitForPremiumGrant() {
        dismiss()
        return
      }
      alertMessage = "購入確認を処理中です\nApple側の反映が遅れている可能性があります。数分後に「購入を復元」をお試しください。"
    } catch {
      alertMessage = "購入処理に失敗しました。時間をおいて再度お試しください。"
    }
  }

  private func waitForPremiumGrant(attempts: Int = 8, intervalNanoseconds: UInt64 = 900_000_000) async -> Bool {
    for _ in 0..<attempts {
      if PurchasesService.shared.isPremium { return true }
      try? await Task.sleep(nanoseconds: intervalNanoseconds)
      await PurchasesService.shared.refreshCustomerInfo()
    }
    return PurchasesService.shared.isPremium
  }

  // MARK: - Restore

  private func handleRestore() async {
    isRestoring = true
    defer { isRestoring = false }

    do {
      _ = try await PurchasesService.shared.restorePurchases()
      if PurchasesService.shared.isPremium {
        dismiss()
      } else {
        alertMessage = "購入の復元に失敗しました"
      }
    } catch {
      alertMessage = "購入の復元に失敗しました"
    }
  }
}

private struct PaywallWebViewURL: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}
