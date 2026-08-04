import SwiftUI

private enum ShareCardTypeOption: CaseIterable, Hashable {
  case ticket
  case receipt
  case cd

  var label: String {
    switch self {
    case .ticket: "Ticket"
    case .receipt: "Receipt"
    case .cd: "CD"
    }
  }

  var imageName: String {
    switch self {
    case .ticket: "Ticket"
    case .receipt: "Receipt bill"
    case .cd: "Podcast"
    }
  }
}

private enum ShareActionKind: Equatable {
  case save
  case stories
  case other
}

private struct ActivityShareItems: Identifiable {
  let id = UUID()
  let items: [Any]
}

/// Ports ShareImageGenerator.tsx's bottom-sheet modal as a standard SwiftUI
/// `.sheet`, matching every other modal in this app (Settings/Calendar/
/// Statistics/Paywall) rather than RN's custom slide-up/rounded-corner
/// animation. Card-type switching is a plain `switch`, not RN's
/// overlapping-opacity-layers trick (a RN perf/animation workaround with
/// no native equivalent needed).
struct ShareSheetView: View {
  @ObservedObject var record: CD_ChekiRecord

  @Environment(\.dismiss) private var dismiss
  @Environment(\.managedObjectContext) private var viewContext

  @State private var cardType: ShareCardTypeOption = .ticket
  @State private var cdTextColor: ShareCDTextColor = .white
  @State private var isGenerating = false
  @State private var inFlightAction: ShareActionKind?
  @State private var activityShareItems: ActivityShareItems?
  @State private var errorMessage: String?
  @State private var showingPaywall = false
  @State private var resolvedUsername: String?

  private var isLockedPreview: Bool {
    !PurchasesService.shared.isPremium && (cardType == .receipt || cardType == .cd)
  }

  private var isActionDisabled: Bool {
    isGenerating || isLockedPreview
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        preview
          .padding(.top, 12)

        cardTypeSwitcher

        if cardType == .cd {
          cdColorPicker
        }

        Text("where to share?")
          .font(.system(size: 16, weight: .bold))

        actionButtons
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
      .navigationTitle("Share")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: {
            HugeIconView(icon: HugeIcons.cancel01, size: 17)
          }
        }
      }
      .task {
        resolvedUsername = UserProfileFetching.fetchOrCreateUserProfile(context: viewContext).username
        try? viewContext.save()
      }
      .sheet(isPresented: $showingPaywall) {
        PaywallView()
      }
      .sheet(item: $activityShareItems) { wrapper in
        ActivityShareSheet(items: wrapper.items)
      }
      .alert("エラー", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  // MARK: - Preview

  private var preview: some View {
    let canvasSize = currentCanvasSize
    let previewHeight: CGFloat = cardType == .receipt ? 460 : 300
    let scale = previewHeight / canvasSize.height

    return ZStack {
      cardView(blurredBackground: false)
        .frame(width: canvasSize.width, height: canvasSize.height)
        .scaleEffect(scale)
        .frame(width: canvasSize.width * scale, height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .id(cardType)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))

      if isLockedPreview {
        lockOverlay
      }
    }
    .frame(height: previewHeight)
    .animation(.spring(duration: 0.4, bounce: 0.08), value: cardType)
  }

  private var currentCanvasSize: CGSize {
    switch cardType {
    case .ticket: ShareCapture.ticketCanvasSize
    case .cd: ShareCapture.cdCanvasSize
    case .receipt: ShareCapture.receiptCanvasSize
    }
  }

  @ViewBuilder
  private func cardView(blurredBackground: Bool) -> some View {
    switch cardType {
    case .ticket:
      ShareTicketCardView(record: record, showsBlurredBackground: blurredBackground)
    case .cd:
      ShareCDCardView(record: record, textColor: cdTextColor, username: resolvedUsername)
    case .receipt:
      ShareReceiptCardView(record: record, username: resolvedUsername)
    }
  }

  private var lockOverlay: some View {
    Button {
      showingPaywall = true
    } label: {
      VStack(spacing: 8) {
        HugeIconView(icon: HugeIcons.squareLock02, size: 28)
        Text("Upgrade to Plus")
          .font(.system(size: 15, weight: .heavy))
      }
      .foregroundStyle(Color(white: 0.18))
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Card type switcher

  private var cardTypeSwitcher: some View {
    HStack(spacing: 8) {
      ForEach(ShareCardTypeOption.allCases, id: \.self) { option in
        Button {
          withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
            cardType = option
          }
        } label: {
          HStack(spacing: 6) {
            Image(option.imageName)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 13, height: 13)
            Text(option.label)
              .font(.system(size: 13, weight: .bold))
          }
          .foregroundStyle(cardType == option ? .white : Color(white: 0.53))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(cardType == option ? Color(white: 0.2) : Color(white: 0.92))
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var cdColorPicker: some View {
    HStack(spacing: 12) {
      colorSwatch(.white)
      colorSwatch(.black)
    }
  }

  private func colorSwatch(_ color: ShareCDTextColor) -> some View {
    Button {
      cdTextColor = color
    } label: {
      Circle()
        .fill(color == .white ? Color.white : Color(white: 0.11))
        .frame(width: 24, height: 24)
        .overlay(
          Circle().stroke(cdTextColor == color ? Color(white: 0.2) : Color(white: 0.8), lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Share actions row

  private var actionButtons: some View {
    HStack(spacing: 32) {
      actionButton(kind: .save, imageName: "Download", scribbleImageName: "ShareScribbleSave", label: "save", action: handleSave)
      actionButton(kind: .stories, imageName: "Instagram", scribbleImageName: "ShareScribbleStories", label: "stories", action: handleStoriesShare)
      actionButton(kind: .other, imageName: "More Circle", scribbleImageName: "ShareScribbleOther", label: "other", action: handleSystemShare)
    }
  }

  private func actionButton(
    kind: ShareActionKind,
    imageName: String,
    scribbleImageName: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ZStack {
          Circle()
            .fill(isLockedPreview ? Color(white: 0.96) : Color.white)
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)

          if isGenerating && inFlightAction == kind {
            ProgressView()
          } else {
            Image(imageName)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 24, height: 24)
              .foregroundStyle(Color(white: 0.2))
          }

          if isLockedPreview {
            Image(scribbleImageName)
              .resizable()
              .scaledToFit()
              .frame(width: 60, height: 60)
              .allowsHitTesting(false)
          }
        }
        Text(label)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color(white: 0.2))
      }
    }
    .buttonStyle(.plain)
    .disabled(isActionDisabled)
  }

  // MARK: - Actions

  private func currentCardKind(blurredBackground: Bool) -> ShareCardKind {
    switch cardType {
    case .ticket:
      .ticket(record: record, blurredBackground: blurredBackground)
    case .cd:
      .cd(record: record, textColor: cdTextColor, username: resolvedUsername)
    case .receipt:
      .receipt(record: record, username: resolvedUsername)
    }
  }

  private func handleSave() {
    guard !isLockedPreview else { showingPaywall = true; return }
    guard let pngData = ShareCapture.capturePNG(currentCardKind(blurredBackground: false)) else {
      errorMessage = "画像を生成できませんでした。"
      return
    }

    inFlightAction = .save
    isGenerating = true
    Task {
      defer {
        isGenerating = false
        inFlightAction = nil
      }
      do {
        try await ShareActions.saveToPhotos(pngData: pngData)
        dismiss()
      } catch {
        errorMessage = "写真への保存に失敗しました。"
      }
    }
  }

  private func handleSystemShare() {
    guard !isLockedPreview else { showingPaywall = true; return }
    guard let pngData = ShareCapture.capturePNG(currentCardKind(blurredBackground: true)),
          let uiImage = UIImage(data: pngData)
    else {
      errorMessage = "画像を生成できませんでした。"
      return
    }

    let caption = ShareCardData.systemShareCaptionText(date: record.date, artist: record.artist, liveName: record.liveName)
    activityShareItems = ActivityShareItems(items: [uiImage, caption])
  }

  private func handleStoriesShare() {
    guard !isLockedPreview else { showingPaywall = true; return }
    guard let pngData = ShareCapture.capturePNG(currentCardKind(blurredBackground: true)) else {
      errorMessage = "画像を生成できませんでした。"
      return
    }

    if ShareActions.shareToInstagramStories(pngData: pngData) {
      dismiss()
    } else {
      errorMessage = "Instagramがインストールされていません。"
    }
  }
}
