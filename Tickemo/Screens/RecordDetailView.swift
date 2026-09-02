import SwiftUI
import UIKit
import CoreLocation

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
  @State private var isSetlistExpanded = true
  @State private var showingShareSheet = false

  // セットリストの書き出し（Apple Music プレイリスト作成 / テキスト）
  @State private var showingPlaylistExportDialog = false
  @State private var showingPlaylistTextShare = false
  @State private var isCreatingPlaylist = false
  @State private var playlistResultMessage: String?
  /// 直近の書き出しの足取り。失敗時はアラートからコピーできるようにして、
  /// 実機の不具合報告をそのまま送ってもらえるようにする。
  @State private var playlistDiagnosticsText: String?

  private let appleMusicService = AppleMusicService()
  @State private var nowPlayingSongId: String?
  @State private var loadingSongId: String?

  @State private var dominantColor: Color
  @State private var backgroundIsDark: Bool

  // Countdown for an upcoming live, reusing NextLiveCardData (same pure
  // logic/format as NextLiveCardView's home-screen card) rather than a
  // second implementation of the same "D : HH : MM : SS" ticking text.
  @State private var now = Date()
  private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private var isPast: Bool { NextLiveCardData.isPast(record, now: now) }
  private var countdown: (text: String, isMessage: Bool) { NextLiveCardData.countdownText(for: record, now: now) }

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

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header

        VStack(alignment: .leading, spacing: 0) {
          if !isPast {
            countdownRow
              .padding(.top, 26)
          }

          Text(record.liveName ?? "-")
            .font(appFont.bold(26))
            .foregroundStyle(primaryTextColor)
            .padding(.top, isPast ? 26 : 8)

          artistPriceRow
            .padding(.top, 10)

          dateTimeGrid
            .padding(.top, 28)

          setlistSection
            .padding(.top, 60)

          if let coordinate = record.venueCoordinate {
            venueSection(coordinate: coordinate)
              .padding(.top, 60)
          }

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
    .onReceive(countdownTimer) { now = $0 }
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
    .confirmationDialog("セットリストを書き出す", isPresented: $showingPlaylistExportDialog, titleVisibility: .visible) {
      Button("Apple Musicにプレイリストを作成") { createApplePlaylist() }
      Button("曲リストをコピー") {
        UIPasteboard.general.string = playlistText
        playlistResultMessage = "曲リストをコピーしました。"
      }
      Button("曲リストを共有") { showingPlaylistTextShare = true }
      Button("キャンセル", role: .cancel) {}
    }
    .sheet(isPresented: $showingPlaylistTextShare) {
      ActivityShareSheet(items: [playlistText])
    }
    .alert(
      "セットリストの書き出し",
      isPresented: Binding(
        get: { playlistResultMessage != nil },
        set: { if !$0 { playlistResultMessage = nil } }
      )
    ) {
      if let playlistDiagnosticsText {
        Button("詳細をコピー") {
          UIPasteboard.general.string = playlistDiagnosticsText
          playlistResultMessage = nil
        }
      }
      Button("OK", role: .cancel) { playlistResultMessage = nil }
    } message: {
      Text(playlistResultMessage ?? "")
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
                .font(appFont.bold(16))
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

  // MARK: - Countdown

  private var countdownRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("NEXT LIVE")
        .font(appFont.bold(12))
        .tracking(1.2)
        .foregroundStyle(secondaryTextColor)
      Text(countdown.text)
        .font(.system(size: countdown.isMessage ? 20 : 28, weight: .bold, design: .monospaced))
        .foregroundStyle(primaryTextColor)
    }
  }

  // MARK: - Artist / price row

  private var artistPriceRow: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(displayArtistsText)
          .font(appFont.bold(17))
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
        .font(appFont.bold(14))
        .foregroundStyle(secondaryTextColor)
      }

      Spacer(minLength: 0)

      HStack(spacing: 7) {
        Image("Wallet")
          .foregroundStyle(secondaryTextColor)
        Text(priceText)
          .font(appFont.bold(17))
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
          .font(appFont.bold(14))
          .foregroundStyle(secondaryTextColor)
          .tracking(1.2)
        HStack(alignment: .top, spacing: 8) {
          Text(monthDayText)
            .font(appFont.bold(52))
            .foregroundStyle(primaryTextColor)
          if !weekdayText.isEmpty {
            Text(weekdayText)
              .font(appFont.bold(12))
              .foregroundStyle(secondaryTextColor)
              .padding(.top, 10)
              .tracking(1.1)
          }
        }
        Text(record.venue?.isEmpty == false ? record.venue! : "-")
          .font(appFont.bold(16))
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
        .font(appFont.bold(14))
        .foregroundStyle(secondaryTextColor)
        .tracking(1)
      Text(value?.isEmpty == false ? value! : "--:--")
        .font(appFont.bold(22))
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
          .font(appFont.bold(18))
          .foregroundStyle(primaryTextColor)
        Spacer()
        // 編集はツールバーの編集ボタン（RecordFormView）に一本化したので、
        // ここには置かない。セトリが既にある場合だけ開閉トグルを出す —
        // 空の場合はそもそも畳む中身がないので "Add Setlist" のまま。
        if record.sortedSetlistItems.isEmpty {
          Button("Add Setlist") {
            showingSetlistEditor = true
          }
          .font(appFont.bold(14))
        } else {
          playlistExportButton
          collapseToggleButton
        }
      }

      if !record.sortedSetlistItems.isEmpty && isSetlistExpanded {
        VStack(spacing: 8) {
          ForEach(Array(record.sortedSetlistItems.enumerated()), id: \.element.objectID) { index, item in
            setlistRow(item, songNumber: songNumber(for: item))
          }
        }
        .padding(12)
        .background(setlistCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
    }
  }

  // ジャケット抽出色に寄せた背景。曲行（songRowBackground）より薄い濃度に
  // して、カード地と曲行カードの二層が視覚的に区別できるようにする。
  private var setlistCardBackground: some View {
    ZStack {
      Color.white
      dominantColor.opacity(0.35)
    }
  }

  /// セトリがあるときだけ出す書き出しボタン。Apple Music プレイリスト
  /// 作成と、どのプレイヤーにも貼れるテキストの2系統をここにまとめる。
  private var playlistExportButton: some View {
    Button {
      HapticsPreferenceService.shared.impact(.light)
      showingPlaylistExportDialog = true
    } label: {
      Group {
        if isCreatingPlaylist {
          ProgressView()
        } else {
          HugeIconView(icon: HugeIcons.playList, size: 15)
            .foregroundStyle(primaryTextColor)
        }
      }
      .frame(width: 30, height: 30)
      .background(setlistCardBackground)
      .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isCreatingPlaylist)
  }

  private var collapseToggleButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isSetlistExpanded.toggle()
      }
    } label: {
      Image(systemName: isSetlistExpanded ? "chevron.up" : "chevron.down")
        .font(appFont.bold(13))
        .foregroundStyle(primaryTextColor)
        .frame(width: 30, height: 30)
        .background(setlistCardBackground)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
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
    HStack(spacing: 12) {
      songArtwork(item, songNumber: songNumber)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.songName ?? "-")
          .font(appFont.bold(15))
          .foregroundStyle(primaryTextColor)
          .lineLimit(1)

        // 曲ごとのアーティスト名はカードの中に置く。対バンで演者が
        // 入れ替わっても、行を見れば誰の曲か分かるようにするため
        // （ブロックごとの区切り見出しは入れない）。実際に演奏した
        // 出演者を優先し、無ければ音源のアーティストを出す。
        if let artistName = SetlistPerformers.displayName(
          performer: item.performerName,
          songArtist: item.artistName
        ) {
          Text(artistName)
            .font(appFont.regular(12))
            .foregroundStyle(secondaryTextColor)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      if let songId = item.songId, !songId.isEmpty {
        playButton(item)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(songRowBackground)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  // カード自体（setlistCardBackground）より一段濃く、白一色に見えないよう
  // 曲行にもジャケット抽出色を乗せる。
  private var songRowBackground: some View {
    ZStack {
      Color.white
      dominantColor.opacity(0.55)
    }
  }

  /// Jacket thumbnail with the running track number overlaid as a small
  /// pill in the corner (rather than a separate text column) — the artwork
  /// carries the number instead of competing with the title for width, the
  /// same trick receipts use with QTY-per-line but adapted to art-forward
  /// rows. Sizing/fallback mirrors `NextLiveCardView.todaySongArtwork`.
  @ViewBuilder
  private func songArtwork(_ item: CD_SetlistItem, songNumber: Int) -> some View {
    ZStack(alignment: .topLeading) {
      if let urlString = item.artworkUrl, let url = URL(string: urlString) {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          songArtworkFallback
        }
      } else {
        songArtworkFallback
      }
    }
    .frame(width: 48, height: 48)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(alignment: .topLeading) {
      Text(String(format: "%02d", songNumber))
        .font(appFont.bold(9))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(4)
    }
  }

  private var songArtworkFallback: some View {
    ZStack {
      Color(white: 0.929)
      HugeIconView(icon: HugeIcons.musicNote01, size: 18)
        .foregroundStyle(Color(white: 0.686))
    }
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
          .foregroundStyle(nowPlayingSongId == songId ? Color.accentColor : secondaryTextColor)
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

  /// 音源のアーティストではなく「実際に歌った人」で検索する。カバー曲は
  /// 原曲のアーティスト名で引くと当然その原曲しか出てこないので、出演者名
  /// で引いた方がカバー音源にたどり着ける。出演者が未指定の曲は従来どおり
  /// 音源のアーティスト名にフォールバックする。
  private func searchQuery(for item: CD_SetlistItem) -> String {
    let artist = SetlistPerformers.displayName(
      performer: item.performerName,
      songArtist: item.artistName
    ) ?? ""
    return "\(item.songName ?? "") \(artist)".trimmingCharacters(in: .whitespaces)
  }

  private func openExternally(_ item: CD_SetlistItem) {
    MusicProviderPreferenceStore.load().open(query: searchQuery(for: item))
  }

  // MARK: - Playlist export

  private var songItems: [CD_SetlistItem] {
    record.sortedSetlistItems.filter { $0.kind == "song" }
  }

  private var playlistText: String {
    SetlistPlaylistText.songList(
      liveName: record.liveName,
      venue: record.venue,
      date: record.date,
      songs: songItems.map { ($0.songName, $0.performerName, $0.artistName) }
    )
  }

  /// Apple Music に登録済みの曲だけがプレイリストに入れられる。曲名検索
  /// を経ずに残った曲（OCR で候補に当たらなかった等）は songId を持たない
  /// ので、除外件数を結果メッセージで伝える。
  private func createApplePlaylist() {
    let songIds = songItems.compactMap { item -> String? in
      guard let id = item.songId?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
      return id
    }
    let skipped = songItems.count - songIds.count
    let name = SetlistPlaylistText.playlistName(
      liveName: record.liveName,
      venue: record.venue,
      date: record.date
    )

    let diagnostics = ApplePlaylistExportDiagnostics()
    diagnostics.record("呼び出し: 曲行=\(songItems.count) songIdあり=\(songIds.count) 除外=\(skipped)")

    Task {
      isCreatingPlaylist = true
      defer { isCreatingPlaylist = false }
      do {
        let added = try await ApplePlaylistExporter.createPlaylist(
          named: name,
          songIds: songIds,
          diagnostics: diagnostics
        )
        HapticsPreferenceService.shared.notify(.success)
        let skippedNote = skipped > 0 ? "\n\(skipped)曲はApple Musicに登録がないため除外しました。" : ""
        playlistDiagnosticsText = nil
        playlistResultMessage = "Apple Musicに「\(name)」を作成しました（\(added)曲）。\(skippedNote)"
      } catch {
        HapticsPreferenceService.shared.notify(.error)
        playlistDiagnosticsText = diagnostics.text
        let reason = (error as? ApplePlaylistExportError)?.errorDescription
          ?? "プレイリストを作成できませんでした。"
        playlistResultMessage = "\(reason)\n\n原因の切り分けに使うので、「詳細をコピー」で記録を送ってください。"
      }
    }
  }

  // MARK: - Venue map

  private func venueSection(coordinate: CLLocationCoordinate2D) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("#venue")
        .font(appFont.bold(18))
        .foregroundStyle(primaryTextColor)

      VenueMapCardView(
        venueName: record.venue?.isEmpty == false ? record.venue! : "-",
        address: record.venueAddress,
        coordinate: coordinate,
        tintColor: dominantColor
      )
    }
  }

  // MARK: - Memo

  private func memoSection(_ memo: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("#memo")
        .font(appFont.bold(18))
        .foregroundStyle(primaryTextColor)

      HStack(alignment: .top, spacing: 8) {
        HugeIconView(icon: HugeIcons.quoteUp, size: 17)
          .foregroundStyle(secondaryTextColor)
        Text(memo)
          .font(appFont.regular(16))
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
