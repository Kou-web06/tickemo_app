import SwiftUI
import UIKit

/// Ports components/TicketDetail.tsx's layout and styling (colors, type
/// scale, section structure) to SwiftUI. Explicitly out of scope, same as
/// the rest of Phase 2: the custom bottom-sheet slide-up presentation (a
/// plain NavigationStack push + system back button replaces RN's floating
/// circular close button). Share-image generation (Ticket/CD/Receipt
/// cards) is implemented in ShareSheetView, presented from the footer's
/// share button. The `#set list` section
/// is read-only here plus tap-to-play: try real in-app playback first
/// (RN never had this, only external Spotify/Apple Music deep links), and
/// fall back to those same external links — ported from
/// TicketDetail.tsx's `handleOpenSongWithProvider`/`openSpotifySearch` —
/// when in-app playback isn't available (no Apple Music subscription,
/// unauthorized, song not in the catalog, etc). Editing happens in
/// SetlistEditorView.
struct RecordDetailView: View {
  @ObservedObject var record: CD_ChekiRecord

  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.dismiss) private var dismiss

  @State private var showingEditSheet = false
  @State private var showingDeleteConfirmation = false
  @State private var showingSetlistEditor = false
  @State private var showingShareSheet = false
  @State private var fallbackItem: CD_SetlistItem?

  private let appleMusicService = AppleMusicService()
  @State private var nowPlayingSongId: String?
  @State private var loadingSongId: String?

  private var liveType: LiveType { LiveType.normalized(record.liveType) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header

        VStack(alignment: .leading, spacing: 0) {
          Text(record.liveName ?? "-")
            .font(.system(size: 26, weight: .black))
            .foregroundStyle(Color(red: 0.169, green: 0.169, blue: 0.180))
            .padding(.top, 26)

          artistPriceRow
            .padding(.top, 10)

          dateTimeGrid
            .padding(.top, 28)

          setlistSection
            .padding(.top, 60)

          if let memo = record.memo, !memo.isEmpty {
            memoSection(memo)
              .padding(.top, 60)
          }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 110)
      }
    }
    .background(Color(red: 0.976, green: 0.976, blue: 0.976))
    .ignoresSafeArea(edges: .top)
    .overlay(alignment: .bottomTrailing) {
      footerTab
        .padding(.trailing, 12)
        .padding(.bottom, 28)
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingEditSheet) {
      RecordFormView(record: record)
    }
    .sheet(isPresented: $showingSetlistEditor) {
      SetlistEditorView(record: record)
    }
    .sheet(isPresented: $showingShareSheet) {
      ShareSheetView(record: record)
    }
    .alert("このチケットを削除しますか？", isPresented: $showingDeleteConfirmation) {
      Button("削除", role: .destructive) { deleteRecord() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("この操作は元に戻せません。")
    }
    .confirmationDialog(
      "アプリ内で再生できません",
      isPresented: Binding(get: { fallbackItem != nil }, set: { if !$0 { fallbackItem = nil } }),
      presenting: fallbackItem
    ) { item in
      Button("Spotifyで開く") { openInSpotify(item) }
      Button("Apple Musicで開く") { openInAppleMusic(item) }
      Button("キャンセル", role: .cancel) {}
    } message: { item in
      Text(item.songName ?? "この曲")
    }
  }

  // MARK: - Header

  private var header: some View {
    ZStack(alignment: .bottomTrailing) {
      Group {
        if let data = record.coverImageData, let uiImage = UIImage(data: data) {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
        } else {
          ZStack {
            Color(red: 0.839, green: 0.839, blue: 0.839)
            Text("NO IMAGE")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(Color(white: 0.5))
              .tracking(0.6)
          }
        }
      }
      .aspectRatio(1.11, contentMode: .fill)
      .frame(maxWidth: .infinity)
      .clipped()

      QRCodeView(value: record.qrCode)
        .frame(width: 56, height: 56)
        .padding(8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .padding(.trailing, 12)
        .padding(.bottom, 14)
    }
  }

  // MARK: - Artist / price row

  private var artistPriceRow: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(displayArtistsText)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Color(white: 0.557))
          .lineLimit(2)

        HugeIconLabel(icon: liveType.hugeIcon, size: 12) { Text(liveType.label) }
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color(white: 0.486))
      }

      Spacer(minLength: 0)

      HStack(spacing: 7) {
        HugeIconView(icon: HugeIcons.wallet01, size: 17)
          .foregroundStyle(Color(white: 0.616))
        Text(priceText)
          .font(.system(size: 17, weight: .heavy))
          .foregroundStyle(Color(white: 0.541))
      }
    }
  }

  private var displayArtistsText: String {
    let names = record.artistsArray?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let unique = (names?.isEmpty == false ? names! : [record.artist ?? "-"])
    var seen = Set<String>()
    let deduped = unique.filter { seen.insert($0.lowercased()).inserted }
    return deduped.isEmpty ? "-" : deduped.joined(separator: " / ")
  }

  private var priceText: String {
    record.ticketPrice.formatted(.currency(code: "JPY").precision(.fractionLength(0)))
  }

  // MARK: - Date / time grid

  private var dateTimeGrid: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(yearText)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(Color(white: 0.561))
          .tracking(1.2)
        HStack(alignment: .top, spacing: 8) {
          Text(monthDayText)
            .font(.system(size: 52, weight: .bold))
            .foregroundStyle(Color(red: 0.188, green: 0.188, blue: 0.212))
          if !weekdayText.isEmpty {
            Text(weekdayText)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(Color(white: 0.557))
              .padding(.top, 10)
              .tracking(1.1)
          }
        }
        Text(record.venue?.isEmpty == false ? record.venue! : "-")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(Color(red: 0.184, green: 0.184, blue: 0.204))
      }

      VStack(alignment: .leading, spacing: 16) {
        timeLine(label: "OPEN", value: record.startTime)
        timeLine(label: "START", value: record.endTime)
      }
      .padding(.top, 10)
      .frame(minWidth: 100)
    }
  }

  private func timeLine(label: String, value: String?) -> some View {
    HStack(alignment: .lastTextBaseline, spacing: 14) {
      Text(label)
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(Color(white: 0.557))
        .tracking(1)
      Text(value?.isEmpty == false ? value! : "--:--")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(Color(red: 0.180, green: 0.180, blue: 0.200))
    }
  }

  // Fixed English weekday abbreviations, independent of device locale —
  // matches TicketDetail.tsx's own hardcoded WEEKDAYS array rather than
  // relying on locale-sensitive date formatting.
  private static let weekdayAbbreviations = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = DateFormatting.timeZone
    return calendar
  }

  private var yearText: String {
    guard let date = DateFormatting.date(from: record.date) else { return "----" }
    let year = Self.utcCalendar.component(.year, from: date)
    return String(year)
  }

  private var monthDayText: String {
    guard let date = DateFormatting.date(from: record.date) else { return "--.--" }
    let comps = Self.utcCalendar.dateComponents([.month, .day], from: date)
    return "\(comps.month ?? 0).\(comps.day ?? 0)"
  }

  private var weekdayText: String {
    guard let date = DateFormatting.date(from: record.date) else { return "" }
    let weekday = Self.utcCalendar.component(.weekday, from: date) // 1 = Sunday
    return Self.weekdayAbbreviations[weekday - 1]
  }

  // MARK: - Setlist

  private var setlistSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("#set list")
          .font(.system(size: 18, weight: .black))
          .foregroundStyle(Color(red: 0.180, green: 0.180, blue: 0.196))
        Spacer()
        Button(record.sortedSetlistItems.isEmpty ? "Add Setlist" : "Edit") {
          showingSetlistEditor = true
        }
        .font(.system(size: 14, weight: .semibold))
      }

      if !record.sortedSetlistItems.isEmpty {
        VStack(spacing: 8) {
          ForEach(Array(record.sortedSetlistItems.enumerated()), id: \.element.objectID) { index, item in
            setlistRow(item, songNumber: songNumber(for: item))
          }
        }
        .padding(12)
        .background(Color(white: 0.929))
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
    }
  }

  private func songNumber(for item: CD_SetlistItem) -> Int? {
    guard item.kind == "song" else { return nil }
    let songs = record.sortedSetlistItems.filter { $0.kind == "song" }
    guard let index = songs.firstIndex(of: item) else { return nil }
    return index + 1
  }

  @ViewBuilder
  private func setlistRow(_ item: CD_SetlistItem, songNumber: Int?) -> some View {
    switch item.kind {
    case "encore":
      SetlistMarkerDivider(text: item.title ?? "ENCORE")
    case "mc":
      SetlistMarkerDivider(text: item.title?.isEmpty == false ? item.title! : "MC")
    default:
      songRow(item, songNumber: songNumber ?? 0)
    }
  }

  private func songRow(_ item: CD_SetlistItem, songNumber: Int) -> some View {
    HStack(spacing: 10) {
      Text(String(format: "%02d", songNumber))
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color(white: 0.545))
        .frame(width: 28, alignment: .leading)

      Text(item.songName ?? "-")
        .font(.system(size: 15, weight: .bold))
        .lineLimit(1)

      Spacer(minLength: 8)

      if let songId = item.songId, !songId.isEmpty {
        playButton(item)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private func playButton(_ item: CD_SetlistItem) -> some View {
    let songId = item.songId ?? ""
    if loadingSongId == songId {
      ProgressView()
        .frame(width: 26, height: 26)
    } else {
      Button {
        togglePlay(item)
      } label: {
        HugeIconView(icon: nowPlayingSongId == songId ? HugeIcons.pauseCircle : HugeIcons.playCircle, size: 22)
          .foregroundStyle(nowPlayingSongId == songId ? Color.accentColor : Color(white: 0.6))
      }
    }
  }

  /// Tries real in-app playback first; falls back to the same external
  /// Spotify/Apple Music links TicketDetail.tsx always used when playback
  /// isn't possible (no subscription, unauthorized, song not found, etc.).
  private func togglePlay(_ item: CD_SetlistItem) {
    guard let songId = item.songId, !songId.isEmpty else { return }

    if nowPlayingSongId == songId {
      appleMusicService.pause()
      nowPlayingSongId = nil
      return
    }

    Task {
      loadingSongId = songId
      defer { loadingSongId = nil }

      if !appleMusicService.isAuthorized() {
        guard await appleMusicService.authorize() else {
          fallbackItem = item
          return
        }
      }

      do {
        try await appleMusicService.play(songId: songId)
        nowPlayingSongId = songId
      } catch {
        nowPlayingSongId = nil
        fallbackItem = item
      }
    }
  }

  // MARK: - External fallback (ports TicketDetail.tsx's openSpotifySearch /
  // Apple Music web-search fallback)

  private func searchQuery(for item: CD_SetlistItem) -> String {
    "\(item.songName ?? "") \(item.artistName ?? "")".trimmingCharacters(in: .whitespaces)
  }

  private func openInSpotify(_ item: CD_SetlistItem) {
    let query = searchQuery(for: item)
    guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

    if let deepLink = URL(string: "spotify:search:\(encoded)"), UIApplication.shared.canOpenURL(deepLink) {
      UIApplication.shared.open(deepLink)
    } else if let webURL = URL(string: "https://open.spotify.com/search/\(encoded)") {
      UIApplication.shared.open(webURL)
    }
  }

  private func openInAppleMusic(_ item: CD_SetlistItem) {
    let query = searchQuery(for: item)
    guard !query.isEmpty,
          let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://music.apple.com/search?term=\(encoded)")
    else { return }
    UIApplication.shared.open(url)
  }

  // MARK: - Memo

  private func memoSection(_ memo: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("#memo")
        .font(.system(size: 18, weight: .black))
        .foregroundStyle(Color(red: 0.180, green: 0.180, blue: 0.196))

      HStack(alignment: .top, spacing: 8) {
        HugeIconView(icon: HugeIcons.quoteUp, size: 17)
          .foregroundStyle(Color(white: 0.608))
        Text(memo)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Color(red: 0.235, green: 0.235, blue: 0.251))
          .lineSpacing(6)
      }
    }
  }

  // MARK: - Footer

  private var footerTab: some View {
    HStack(spacing: 8) {
      footerButton(imageName: "Share", color: Color(white: 0.365)) {
        showingShareSheet = true
      }
      footerButton(imageName: "Edit", color: Color(white: 0.365)) {
        showingEditSheet = true
      }
      footerButton(imageName: "Confounded", color: Color(red: 0.961, green: 0.337, blue: 0.196)) {
        showingDeleteConfirmation = true
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 56)
    .background(.white.opacity(0.88))
    .clipShape(RoundedRectangle(cornerRadius: 28))
    .overlay(
      RoundedRectangle(cornerRadius: 28)
        .stroke(Color(white: 0.541).opacity(0.25), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
  }

  private func footerButton(imageName: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(imageName)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 22, height: 22)
        .foregroundStyle(color)
        .frame(width: 44, height: 44)
    }
  }

  private func deleteRecord() {
    viewContext.delete(record)
    try? viewContext.save()
    dismiss()
  }
}
