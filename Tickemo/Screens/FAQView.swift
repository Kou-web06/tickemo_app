import SwiftUI

/// Ports screens/SettingsScreen.tsx's `FAQScreen`. Content is a static
/// transcription of `i18n.ts`'s `ja` FAQ resource block (4 categories, 9
/// Q&A pairs total) — the app's primary audience is Japanese, so this
/// sources from the `ja` block rather than `en`.
struct FAQView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var systemColorScheme

  private struct FAQItem {
    let question: String
    let answer: String
  }

  private struct FAQCategory {
    let title: String
    let items: [FAQItem]
  }

  private let categories: [FAQCategory] = [
    FAQCategory(title: "トラブル・不具合", items: [
      FAQItem(
        question: "触覚（Haptics）が動きません。",
        answer: "iPhoneの設定が原因のことが多いです。まず「低電力モード」をOFFにし、「設定 > サウンドと触覚 > システムハプティクス（または触覚）」がONになっているか確認してください。"
      ),
      FAQItem(
        question: "チケットの画像が表示されなくなりました。",
        answer: "端末のストレージ最適化やOSの更新により、画像のリンクが切れる場合があります。お手数ですが、一度その画像を削除し、再度アルバムから選択し直して保存してください。"
      ),
      FAQItem(
        question: "画面が固まって動かないときは？",
        answer: "一度アプリを終了して再起動してください。改善しない場合は端末の再起動をお試しください。"
      ),
      FAQItem(
        question: "アプリが落ちる・動作が重いです。",
        answer: "画像サイズが大きい場合や、バックグラウンドで多数のアプリが動いている場合に発生することがあります。画像を少し小さくするか、アプリの再起動をお試しください。"
      ),
    ]),
    FAQCategory(title: "データ・バックアップ", items: [
      FAQItem(
        question: "間違ってアプリを消してしまいました。データは復元できますか？",
        answer: "いいえ、できません。本アプリは、お客様の端末内（ローカル）のみにデータを保存しており、サーバーには送信していません。アプリを削除すると、データも全て削除されます。"
      ),
      FAQItem(
        question: "機種変更をしたいのですが。",
        answer: "設定画面の「iCloud同期」をONにしたうえで、同じApple IDで新しい端末にサインインしてください。同期完了まで少し時間がかかる場合があります。"
      ),
    ]),
    FAQCategory(title: "機能・仕様", items: [
      FAQItem(
        question: "友達とデータを共有できますか？",
        answer: "現在、リアルタイムでの共有機能はありません。作成したチケット画像をSNSなどでシェアしてお楽しみください。"
      ),
      FAQItem(
        question: "Android版（またはiOS版）とデータを移行できますか？",
        answer: "異なるOS間でのデータ移行は、バックアップファイルの形式が合えば可能ですが、動作保証はしておりません。"
      ),
    ]),
    FAQCategory(title: "その他", items: [
      FAQItem(
        question: "要望や不具合の報告はどこから？",
        answer: "設定画面の「フィードバック」またはストアのレビューからお願いします。個人で開発しているため、すぐに対応できない場合もございますが、全てのメッセージに目を通しております。"
      ),
    ]),
  ]

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: SettingsPalette { SettingsPalette(isDarkMode: isDarkMode) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
          VStack(alignment: .leading, spacing: 0) {
            Text(category.title)
              .font(.system(size: 20, weight: .heavy))
              .foregroundStyle(palette.titleText)
              .padding(.bottom, 16)

            ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
              VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                  Text("Q.")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.faqQuestionLabel)
                  Text(item.question)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineSpacing(6)
                }
                HStack(alignment: .top, spacing: 8) {
                  Text("A.")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.faqAnswerLabel)
                  Text(item.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.subtleText)
                    .lineSpacing(6)
                }
              }
              .padding(16)
              .background(palette.cardBackground)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .padding(.bottom, 20)
            }
          }
          .padding(.bottom, 32)
        }

        Text("その他ご不明な点は、設定画面の「フィードバック」からお問い合わせください。")
          .font(.system(size: 13))
          .foregroundStyle(palette.subtleText)
          .lineSpacing(6)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(16)
          .background(palette.mutedCardBackground)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .padding(.top, 10)
          .padding(.bottom, 40)
      }
      .padding(20)
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
      Text("よくある質問")
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
}
