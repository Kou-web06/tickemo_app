import SwiftUI

/// Ports components/PaywallBanner.tsx — a richer, self-contained upgrade
/// banner (gradient background, live countdown, illustration) than a plain
/// text-and-chevron row. Only meant to be shown when
/// `!PurchasesService.shared.isPremium` — the caller is responsible for
/// that gate (matching RN's own `membershipType === 'free'` check at the
/// call site, not inside the component).
struct PaywallBannerView: View {
  @State private var showingPaywall = false
  @State private var remainingSeconds: TimeInterval = EarlyOfferService.remainingSeconds()

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    Button {
      showingPaywall = true
    } label: {
      GeometryReader { proxy in
        let imageWidth = min(max(proxy.size.width * 0.36, 120), 170)

        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            Text("24時間限定 51%オフ")
              .font(appFont.bold(14))
              .foregroundStyle(Color(hex: "#FFF6FD"))

            if remainingSeconds > 0 {
              Text(EarlyOfferService.format(remaining: remainingSeconds))
                .font(appFont.bold(20))
                .foregroundStyle(Color(hex: "#ffe8ed"))
                .padding(.top, 8)
            } else {
              Text("キャンペーン終了")
                .font(appFont.regular(15))
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.top, 8)
            }

            Text("Plusにアップグレード")
              .font(appFont.bold(12))
              .foregroundStyle(Color(hex: "#3c3c3d"))
              .padding(.horizontal, 10)
              .padding(.vertical, 10)
              .background(Color.white)
              .clipShape(Capsule())
              .padding(.top, 10)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Image("BannerPass")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageWidth, height: imageWidth * 0.9)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .frame(height: 110)
      .background(
        LinearGradient(
          colors: [Color(hex: "#2B2B2B"), Color(hex: "#121212")],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .onReceive(timer) { _ in
      remainingSeconds = EarlyOfferService.remainingSeconds()
    }
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
  }
}
