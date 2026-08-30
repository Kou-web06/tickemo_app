import SwiftUI
import UIKit

/// Ports screens/CollectionScreen.tsx's inline "Next Live" card (the block
/// inside `ListHeaderComponent`, not just the small `NextLiveCountdown`
/// text component) — a flip card showing the soonest upcoming (or most
/// recent past) ticket, with a live countdown on the front and a
/// MusicKit-driven "song of the day" for that artist on the back.
struct NextLiveCardView: View {
  @ObservedObject var record: CD_ChekiRecord

  @State private var now = Date()
  @State private var isFlipped = false
  @State private var todaySong: TodaySongResult?
  @State private var showingInvalidQrAlert = false

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private static let cardHeight: CGFloat = 180
  // Same cubic-out curve as CustomToggleSwitch — matches RN's
  // `Easing.out(Easing.cubic)`; RN's own flip duration is 180ms.
  private static let flipAnimation = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.18)

  private var isPast: Bool { NextLiveCardData.isPast(record, now: now) }
  private var countdown: (text: String, isMessage: Bool) { NextLiveCardData.countdownText(for: record, now: now) }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(isPast ? "LAST LIVE" : "NEXT LIVE")
        .font(appFont.bold(15))
        .padding(.horizontal, 30)

      ZStack {
        frontFace
          .opacity(isFlipped ? 0 : 1)
          .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
          .allowsHitTesting(!isFlipped)
          .zIndex(0)
        backFace
          .opacity(isFlipped ? 1 : 0)
          .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
          .allowsHitTesting(isFlipped)
          .zIndex(0)

        // Explicit zIndex guarantees this always wins hit-testing over the
        // front/back faces regardless of any compositor ordering quirk
        // introduced by their opacity/rotation3DEffect siblings.
        flipButton
          .zIndex(1)
      }
      .frame(maxWidth: .infinity)
      .frame(height: Self.cardHeight)
      .background(backgroundImage)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, 20)
    }
    .onReceive(timer) { now = $0 }
    .task(id: record.objectID) {
      isFlipped = false
      todaySong = nil
      // ArtistGrouping.names handles both artistsArray and the legacy single
      // artist field, so the correct name is used even when record.artist is
      // empty because only artistsArray is populated.
      let artistName = ArtistGrouping.names(for: record).first ?? ""
      guard !artistName.isEmpty else { return }
      todaySong = await TodaySongCache.fetchTodaySong(for: artistName)
    }
    .alert("開けません", isPresented: $showingInvalidQrAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("QRコードのURLが無効です。")
    }
  }

  // MARK: - Shared background

  // Applied via `.background()` on the whole front/back ZStack rather than
  // as a ZStack *sibling* — a `scaledToFill()` Image sibling alongside
  // Text-heavy siblings (each stretched with `.frame(maxWidth: .infinity,
  // maxHeight: .infinity)`) was previously found to silently corrupt the
  // *other* siblings' measured layout (their first lines of text got
  // clipped off above the visible frame). `.background()` sizes its
  // content to match the foreground's already-resolved frame instead of
  // participating in that same proposed-size negotiation, which avoids the
  // bug entirely and also drops the GeometryReader indirection this view
  // used to need — GeometryReader nested inside a List row is a known
  // source of hit-testing/sizing flakiness for nested buttons, which is
  // suspected to be why the flip button didn't respond to taps on device.
  @ViewBuilder
  private var backgroundImage: some View {
    if let data = record.coverImageData, let uiImage = UIImage(data: data) {
      Image(uiImage: uiImage).resizable().scaledToFill().clipped()
    } else {
      Image("TicketEmpty").resizable().scaledToFill().clipped()
    }
  }

  // MARK: - Flip button (floats above both faces, never itself flips)

  private var flipButton: some View {
    VStack {
      HStack {
        Spacer()
        Button {
          withAnimation(Self.flipAnimation) {
            isFlipped.toggle()
          }
        } label: {
          HugeIconView(icon: HugeIcons.tap03, size: 16, weight: 2)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(12)
    .allowsHitTesting(true)
  }

  // MARK: - Front face

  private var frontFace: some View {
    ZStack(alignment: .topLeading) {
      Color.black.opacity(0.5)

      VStack(alignment: .leading, spacing: 0) {
        Text(record.liveName?.isEmpty == false ? record.liveName! : "LIVE TITLE")
          .font(appFont.bold(22))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(ArtistGrouping.names(for: record).first ?? "-")
          .font(appFont.regular(13))
          .foregroundStyle(.white)
          .lineLimit(1)
          .padding(.top, 4)
        Text(metaText)
          .font(appFont.bold(13))
          .foregroundStyle(.white)
          .padding(.top, 10)
        Text(countdown.text)
          .font(appFont.bold(countdown.isMessage ? 28 : 34))
          .foregroundStyle(.white)
          .padding(.top, 2)
      }
      .padding(18)
    }
    .overlay(alignment: .bottomTrailing) {
      qrButton.padding(16)
    }
  }

  private var metaText: String {
    let dateText = record.date?.isEmpty == false ? record.date! : "-"
    let startTimeSuffix = record.startTime?.isEmpty == false ? "  \(record.startTime!)" : ""
    let venueText = record.venue?.isEmpty == false ? record.venue! : "-"
    return "DATE    \(dateText)\(startTimeSuffix)\nVENUE    \(venueText)"
  }

  private var qrButton: some View {
    Button {
      openQrLink()
    } label: {
      ZStack {
        Color.white
        if let qr = record.qrCode, !qr.isEmpty, let uiImage = QRCodeImage.image(for: qr, scale: 8) {
          Image(uiImage: uiImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
        } else {
          HugeIconView(icon: HugeIcons.qrCode, size: 32)
            .foregroundStyle(Color(white: 0.173))
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .disabled(record.qrCode?.isEmpty != false)
  }

  private func openQrLink() {
    guard let qrCode = record.qrCode, !qrCode.isEmpty, let url = URL(string: qrCode),
          UIApplication.shared.canOpenURL(url)
    else {
      showingInvalidQrAlert = true
      return
    }
    UIApplication.shared.open(url)
  }

  // MARK: - Back face ("TODAY'S SONG")

  private var backFace: some View {
    ZStack(alignment: .topLeading) {
      Color(white: 16 / 255).opacity(0.66)

      VStack(alignment: .leading, spacing: 0) {
        Text("TODAY'S SONG")
          .font(appFont.bold(14))
          .foregroundStyle(.white)
          .tracking(0.4)
          .padding(.bottom, 12)

        HStack(spacing: 12) {
          todaySongArtwork
          VStack(alignment: .leading, spacing: 4) {
            Text(todaySong?.title ?? "No song data")
              .font(appFont.bold(18))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(todaySong?.artist ?? (record.artist?.isEmpty == false ? record.artist! : "-"))
              .font(appFont.regular(13))
              .foregroundStyle(Color(white: 0.898))
              .lineLimit(1)
          }
        }

        metaGrid
          .padding(.top, 12)
      }
      .padding(18)
    }
    .overlay(alignment: .bottomTrailing) {
      providerButton.padding(14)
    }
  }

  @ViewBuilder
  private var todaySongArtwork: some View {
    if let urlString = todaySong?.artworkUrl, let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        todaySongArtworkFallback
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
      todaySongArtworkFallback
    }
  }

  private var todaySongArtworkFallback: some View {
    ZStack {
      Color(hex: "#ECECEC")
      HugeIconView(icon: HugeIcons.musicNote01, size: 24)
        .foregroundStyle(Color(hex: "#A0A0A0"))
    }
    .frame(width: 52, height: 52)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var metaGrid: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 14) {
        metaItem(label: "ALBUM", value: todaySong?.album ?? "-")
        metaItem(label: "TIME", value: durationText)
      }
      HStack(spacing: 14) {
        metaItem(label: "GENRE", value: todaySong?.genre ?? "-")
        metaItem(label: "REL", value: releaseDateText)
      }
    }
    .padding(.trailing, 108) // reserves space for the provider pill, matching RN's paddingRight:108
  }

  private func metaItem(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(appFont.bold(6))
        .tracking(0.7)
        .foregroundStyle(.white.opacity(0.7))
      Text(value)
        .font(appFont.regular(9))
        .foregroundStyle(.white.opacity(0.86))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var durationText: String {
    guard let seconds = todaySong?.durationSeconds, seconds > 0 else { return "-" }
    let total = Int(seconds)
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  private var releaseDateText: String {
    guard let date = todaySong?.releaseDate else { return "-" }
    let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
    guard let year = comps.year else { return "-" }
    guard let month = comps.month, let day = comps.day else { return String(year) }
    return String(format: "%04d.%02d.%02d", year, month, day)
  }

  // Opens directly in the user's Settings-saved provider — no per-tap
  // "which provider?" prompt, matching RN's single persisted
  // `musicProvider` preference (RecordDetailView's setlist tap-to-play
  // fallback does the same via MusicProviderPreference.open).
  private var providerButton: some View {
    Button {
      HapticsPreferenceService.shared.impact(.light)
      openInPreferredProvider()
    } label: {
      HStack(spacing: 6) {
        HugeIconView(icon: HugeIcons.musicNote01, size: 11)
        Text("Listen")
          .font(appFont.bold(10))
          .tracking(0.2)
      }
      .foregroundStyle(.white.opacity(0.92))
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Color.black.opacity(0.38))
      .clipShape(Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .disabled(todaySong == nil)
  }

  private func openInPreferredProvider() {
    let query = "\(todaySong?.title ?? "") \(todaySong?.artist ?? (record.artist ?? ""))"
      .trimmingCharacters(in: .whitespaces)
    MusicProviderPreferenceStore.load().open(query: query, appleMusicURL: todaySong?.appleMusicUrl)
  }
}
