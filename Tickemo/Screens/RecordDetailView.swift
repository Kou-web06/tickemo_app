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

  private let appleMusicService = AppleMusicService()
  @State private var nowPlayingSongId: String?
  @State private var loadingSongId: String?

  @State private var dominantColor: Color
  @State private var backgroundIsDark: Bool

  init(record: CD_ChekiRecord) {
    self.record = record
    // 一覧の行（RecordRowView）表示時に DominantColorCache へ先読みしてある
    // ため、通常はここでキャッシュに当たり、初回フレームから抽出色の背景で
    // 描画できる（開いた瞬間に白背景が見えるのを防ぐ）。
    let cached = record.coverImageData.flatMap { DominantColorCache.shared.cachedColor(for: $0) }
    _dominantColor = State(initialValue: cached?.color ?? DominantColorExtractor.fallback.color)
    _backgroundIsDark = State(initialValue: cached?.isDark ?? DominantColorExtractor.fallback.isDark)
  }

  private var primaryTextColor: Color {
    backgroundIsDark ? .white : Color(red: 0.169, green: 0.169, blue: 0.180)
  }
  // メインテキストと同じ黒/白に連動させ、透明度だけで主従の差をつける
  private var secondaryTextColor: Color {
    primaryTextColor.opacity(0.7)
  }

  private var liveType: LiveType { LiveType.normalized(record.liveType) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header

        VStack(alignment: .leading, spacing: 0) {
          Text(record.liveName ?? "-")
            .font(.system(size: 26, weight: .black))
            .foregroundStyle(primaryTextColor)
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
        .padding(.bottom, 40)
      }
    }
    .coordinateSpace(name: "scroll")
    .background(
      ZStack {
        Color.white
        dominantColor.opacity(0.75)
      }
      .ignoresSafeArea()
    )
    .ignoresSafeArea(edges: .top)
    .task(id: record.coverImageData) {
      guard let data = record.coverImageData else {
        withAnimation(.easeInOut(duration: 0.4)) {
          dominantColor = DominantColorExtractor.fallback.color
          backgroundIsDark = DominantColorExtractor.fallback.isDark
        }
        return
      }
      // キャッシュ済みなら init で反映済みのはずなので、アニメーション無しで
      // 即確定する（フェードによるちらつきを出さない）
      if let cached = DominantColorCache.shared.cachedColor(for: data) {
        dominantColor = cached.color
        backgroundIsDark = cached.isDark
        return
      }
      let extracted = await DominantColorCache.shared.color(for: data)
      withAnimation(.easeInOut(duration: 0.5)) {
        dominantColor = extracted.color
        backgroundIsDark = extracted.isDark
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      // ToolbarItemGroup だと 1 つのグループにまとめて表示されるため、
      // 独立したボタンとして並ぶよう個別の ToolbarItem に分ける
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          HapticsPreferenceService.shared.impact(.light)
          showingShareSheet = true
        } label: {
          toolbarIcon("Share", color: .black)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          HapticsPreferenceService.shared.impact(.light)
          showingEditSheet = true
        } label: {
          toolbarIcon("Edit", color: .black)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(role: .destructive) {
          HapticsPreferenceService.shared.impact(.light)
          showingDeleteConfirmation = true
        } label: {
          toolbarIcon("Confounded", color: .red)
        }
      }
    }
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
  }

  // MARK: - Header

  private var header: some View {
    GeometryReader { geo in
      let pullDown = max(0, geo.frame(in: .named("scroll")).minY)
      let h = geo.size.height
      // 画像高さが (h + pullDown) になるため、視覚上の下端フェード開始位置を
      // 画像座標系に変換して補正する。これで pullDown が増えても
      // フェードが始まる「見た目の位置」は常に下端から h*0.5 付近に固定される。
      let botFadeStart = (pullDown + h * 0.5) / (h + pullDown)

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
        .frame(width: geo.size.width, height: h + pullDown)
        .clipped()
        .mask(
          LinearGradient(
            stops: pullDown > 0 ? [
              // オーバースクロール中: 上端フェードなし（伸びた画像がきれいに見える）
              .init(color: .black, location: 0),
              .init(color: .black, location: botFadeStart),
              .init(color: .clear, location: 1),
            ] : [
              // 通常時: 上端も軽くフェード
              .init(color: .clear, location: 0),
              .init(color: .black, location: 0.12),
              .init(color: .black, location: botFadeStart),
              .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        // .offset はレイアウト位置を変えないため、後段に置いた mask は元の位置に
        // 残ってしまい、上に伸ばした画像の上端が切れる。mask の後に offset を
        // 適用することで、マスクごと画像を引き上げて上端を画面最上部に固定する。
        .offset(y: -pullDown)
        // 画像のレイアウト高さは h + pullDown のままなので、そのままだと
        // ZStack ごと成長して bottomTrailing 揃えの QR が下へ流れてしまう。
        // 高さ h に固定して QR の基準位置をオーバースクロールから切り離す。
        .frame(width: geo.size.width, height: h, alignment: .top)

        QRCodeView(value: record.qrCode)
          .frame(width: 56, height: 56)
          .padding(8)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 7))
          .padding(.trailing, 12)
          .padding(.bottom, 14)
          // ヘッダー自体はオーバースクロールで下に動くため、画像と同様に
          // 引き戻して QR を画面上の定位置に固定する
          .offset(y: -pullDown)
      }
    }
    .aspectRatio(1.11, contentMode: .fill)
    .frame(maxWidth: .infinity)
  }

  // MARK: - Artist / price row

  private var artistPriceRow: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(displayArtistsText)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(secondaryTextColor)
          .lineLimit(2)

        HStack(spacing: 6) {
          Image(liveType.imageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
          Text(liveType.label)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(secondaryTextColor)
      }

      Spacer(minLength: 0)

      HStack(spacing: 7) {
        Image("Wallet")
          .foregroundStyle(secondaryTextColor)
        Text(priceText)
          .font(.system(size: 17, weight: .heavy))
          .foregroundStyle(secondaryTextColor)
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
          .foregroundStyle(secondaryTextColor)
          .tracking(1.2)
        HStack(alignment: .top, spacing: 8) {
          Text(monthDayText)
            .font(.system(size: 52, weight: .bold))
            .foregroundStyle(primaryTextColor)
          if !weekdayText.isEmpty {
            Text(weekdayText)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(secondaryTextColor)
              .padding(.top, 10)
              .tracking(1.1)
          }
        }
        Text(record.venue?.isEmpty == false ? record.venue! : "-")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(primaryTextColor)
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
        .foregroundStyle(secondaryTextColor)
        .tracking(1)
      Text(value?.isEmpty == false ? value! : "--:--")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(primaryTextColor)
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
          .foregroundStyle(primaryTextColor)
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

  /// Tries real in-app playback first; falls back to opening the same
  /// search query in the user's Settings-saved provider (no per-tap "which
  /// provider?" prompt) when playback isn't possible (no subscription,
  /// unauthorized, song not found, etc.).
  private func togglePlay(_ item: CD_SetlistItem) {
    guard let songId = item.songId, !songId.isEmpty else { return }
    HapticsPreferenceService.shared.impact(.light)

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
          openExternally(item)
          return
        }
      }

      do {
        try await appleMusicService.play(songId: songId)
        nowPlayingSongId = songId
      } catch {
        nowPlayingSongId = nil
        openExternally(item)
      }
    }
  }

  // MARK: - External fallback (ports TicketDetail.tsx's openSpotifySearch /
  // Apple Music web-search fallback, opened directly in the saved provider)

  private func searchQuery(for item: CD_SetlistItem) -> String {
    "\(item.songName ?? "") \(item.artistName ?? "")".trimmingCharacters(in: .whitespaces)
  }

  private func openExternally(_ item: CD_SetlistItem) {
    MusicProviderPreferenceStore.load().open(query: searchQuery(for: item))
  }

  // MARK: - Memo

  private func memoSection(_ memo: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("#memo")
        .font(.system(size: 18, weight: .black))
        .foregroundStyle(primaryTextColor)

      HStack(alignment: .top, spacing: 8) {
        HugeIconView(icon: HugeIcons.quoteUp, size: 17)
          .foregroundStyle(secondaryTextColor)
        Text(memo)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(primaryTextColor)
          .lineSpacing(6)
      }
    }
  }

  // MARK: - Toolbar

  private func toolbarIcon(_ imageName: String, color: Color) -> some View {
    Image(imageName)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: 22, height: 22)
      .foregroundStyle(color)
  }

  private func deleteRecord() {
    HapticsPreferenceService.shared.notify(.warning)
    viewContext.delete(record)
    try? viewContext.save()
    dismiss()
  }

}
