import SwiftUI

/// Ports screens/SettingsScreen.tsx's `FAQScreen`. Content is a static
/// English-language transcription of `i18n.ts`'s `en` FAQ resource block
/// (4 categories, 9 Q&A pairs total) — per the approved scope, all new
/// hard-coded copy in this rebuild sources from the `en` block for
/// consistency with every other already-rebuilt native screen.
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
    FAQCategory(title: "Troubleshooting", items: [
      FAQItem(
        question: "Haptics does not work.",
        answer: "This is often caused by iPhone settings. Please turn off Low Power Mode and check that \"Settings > Sounds & Haptics > System Haptics\" is enabled."
      ),
      FAQItem(
        question: "Ticket images are no longer displayed.",
        answer: "Image links may break due to storage optimization or OS updates on your device. Please delete the affected image once, then select it again from your album and save."
      ),
      FAQItem(
        question: "What should I do if the screen freezes?",
        answer: "Please close and restart the app once. If it does not improve, try restarting your device."
      ),
      FAQItem(
        question: "The app crashes or feels slow.",
        answer: "This may happen when image sizes are large or many apps are running in the background. Try reducing image size or restarting the app."
      ),
    ]),
    FAQCategory(title: "Data & Backup", items: [
      FAQItem(
        question: "I accidentally deleted the app. Can I restore my data?",
        answer: "No. This app stores data only on your device (local) and does not send it to servers. If the app is deleted, all data is also deleted."
      ),
      FAQItem(
        question: "I want to change devices.",
        answer: "Turn on \"iCloud Sync\" in settings and sign in to your new device with the same Apple ID. It may take some time for sync to complete."
      ),
    ]),
    FAQCategory(title: "Features", items: [
      FAQItem(
        question: "Can I share data with friends?",
        answer: "Currently, real-time sharing is not available. Please enjoy sharing created ticket images on SNS and other platforms."
      ),
      FAQItem(
        question: "Can I migrate data between Android and iOS?",
        answer: "Data migration across different OSes may be possible if backup file formats are compatible, but operation is not guaranteed."
      ),
    ]),
    FAQCategory(title: "Others", items: [
      FAQItem(
        question: "Where can I send requests or bug reports?",
        answer: "Please use \"Feedback\" on the settings screen or leave a store review. This app is developed individually, so immediate responses may not always be possible, but every message is reviewed."
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

        Text("If you have any other questions, please contact us from \"Feedback\" on the settings screen.")
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
          Image(systemName: "chevron.left")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(palette.primaryText)
            .frame(width: 44, height: 44)
        }
        Spacer()
        Color.clear.frame(width: 44, height: 44)
      }
      Text("FAQ")
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
