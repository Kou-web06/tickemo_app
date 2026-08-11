import SwiftUI

/// Ports screens/ArtistDetailScreen.tsx: a hero image, 3 stat columns
/// (total shows / first show date / total spent, all computed from past
/// shows only), and the artist's records grouped by year, reusing
/// RecordRowView rather than a bespoke row. Takes a plain artist name
/// string (matching RN's route param shape) rather than a dedicated Artist
/// entity, since none exists in the Core Data schema.
struct ArtistDetailView: View {
  let artistName: String

  // Live MusicKit lookup when none of this artist's records have a saved
  // photo — a top-1 search by name, cached in-memory only, never persisted.
  @State private var backfillImageUrl: String?
  private let appleMusicService = AppleMusicService()

  // RecordDetailView と同じ動的カラー背景。ヒーロー画像はリモート URL なので
  // ダウンロード完了後に抽出する（AsyncImage と同じ URLCache に乗るため
  // 画像の二重取得にはならない）。
  @State private var dominantColor: Color = DominantColorExtractor.fallback.color
  @State private var backgroundIsDark: Bool = DominantColorExtractor.fallback.isDark

  private var primaryTextColor: Color {
    backgroundIsDark ? .white : Color(red: 0.188, green: 0.188, blue: 0.212)
  }
  // メインテキストと同じ黒/白に連動させ、透明度だけで主従の差をつける
  private var secondaryTextColor: Color {
    primaryTextColor.opacity(0.7)
  }

  @FetchRequest(
    sortDescriptors: [
      NSSortDescriptor(keyPath: \CD_ChekiRecord.date, ascending: false),
      NSSortDescriptor(keyPath: \CD_ChekiRecord.createdAt, ascending: false),
    ]
  ) private var allRecords: FetchedResults<CD_ChekiRecord>

  // CD_ChekiRecord.artists is a Transformable attribute, which Core Data
  // can't filter on via NSPredicate — grouping/matching happens in memory,
  // same as RecordListView's own filtered/grid logic.
  private var records: [CD_ChekiRecord] {
    allRecords.filter { ArtistGrouping.matches($0, artistName: artistName) }
  }

  private var pastRecords: [CD_ChekiRecord] {
    let today = ArtistGrouping.utcCalendar.startOfDay(for: Date())
    return records.filter { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return date < today
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        hero
        statsRow
          .padding(.horizontal, 22)
          .padding(.top, 24)

        yearGroupedList
          .padding(.horizontal, 22)
          .padding(.top, 28)

        appleMusicLink
          .padding(.horizontal, 22)
          .padding(.top, 20)
          .padding(.bottom, 32)
      }
    }
    .coordinateSpace(name: "scroll")
    .navigationTitle(artistName)
    .navigationBarTitleDisplayMode(.inline)
    // RecordDetailView と同じ没入型ヘッダー: 画像を画面最上部まで届かせる
    .toolbarBackground(.hidden, for: .navigationBar)
    .ignoresSafeArea(edges: .top)
    // 画像の最支配色でベタ塗りし、ヘッダー下端のフェードがそのまま
    // 背景に溶け込むようにする（白ミックスすると色がずれて境目が見える）
    .background(dominantColor.ignoresSafeArea())
    .task(id: artistName) {
      guard heroImageUrl == nil, backfillImageUrl == nil else { return }
      guard let url = await appleMusicService.bestMatchArtistImageUrl(for: artistName) else { return }
      // 800px はグリッドタイル・Report 行と同じ解像度。URL 文字列が一致する
      // ことで DominantColorCache の先読み結果（URL キー）がここでも当たる
      backfillImageUrl = AppleMusicService.resolvedArtworkURL(url, size: 800)
    }
    .onAppear {
      // .task より先（初回描画前）に同期でキャッシュを引き、入口で先読み済み
      // なら初回フレームから抽出色で塗る。ミス時は下の .task が追いつく。
      if let urlString = resolvedHeroImageUrl,
         let cached = DominantColorCache.shared.cachedColor(forURL: urlString, mode: .dominant) {
        dominantColor = cached.color
        backgroundIsDark = cached.isDark
      }
    }
    .task(id: resolvedHeroImageUrl) {
      guard let urlString = resolvedHeroImageUrl else {
        withAnimation(.easeInOut(duration: 0.4)) {
          dominantColor = DominantColorExtractor.fallback.color
          backgroundIsDark = DominantColorExtractor.fallback.isDark
        }
        return
      }
      // 先読み済み・再訪ならアニメーション無しで即確定
      if let cached = DominantColorCache.shared.cachedColor(forURL: urlString, mode: .dominant) {
        dominantColor = cached.color
        backgroundIsDark = cached.isDark
        return
      }
      // 取得失敗時は現在の背景色（フォールバック）を維持する
      guard let extracted = await DominantColorCache.shared.color(forURL: urlString, mode: .dominant) else { return }
      withAnimation(.easeInOut(duration: 0.5)) {
        dominantColor = extracted.color
        backgroundIsDark = extracted.isDark
      }
    }
  }

  // MARK: - Hero

  // A saved photo (from ArtistSearchField) takes priority; if none of this
  // artist's records have one, `backfillImageUrl`'s live MusicKit search
  // (see .task above) fills the gap — never the user's own ticket cover
  // photo, unlike the Collection artist grid. `entries(for:)` already
  // resolves the per-record, per-index artistImageUrl (or single-artist
  // fallback), so this just takes the first non-nil match across records.
  private var heroImageUrl: String? {
    let target = artistName.trimmingCharacters(in: .whitespaces).lowercased()
    for record in records {
      if let url = ArtistGrouping.entries(for: record).first(where: { $0.name.lowercased() == target })?.imageUrl {
        return url
      }
    }
    return nil
  }

  private var resolvedHeroImageUrl: String? {
    heroImageUrl ?? backfillImageUrl
  }

  // RecordDetailView.header と同じストレッチヘッダー: オーバースクロール量
  // (pullDown) だけ画像を伸ばし、offset で引き戻して上端を画面最上部に固定する。
  @ViewBuilder
  private var hero: some View {
    GeometryReader { geo in
      let pullDown = max(0, geo.frame(in: .named("scroll")).minY)
      let h = geo.size.height
      // 画像高さが (h + pullDown) に伸びるため、下端フェードの開始位置を
      // 画像座標系に変換し、見た目の位置を常に下端から h*0.5 付近に固定する
      let botFadeStart = (pullDown + h * 0.5) / (h + pullDown)

      ZStack(alignment: .bottomLeading) {
        Group {
          if let urlString = resolvedHeroImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Color(red: 0.839, green: 0.839, blue: 0.839)
            }
          } else {
            Color(red: 0.839, green: 0.839, blue: 0.839)
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
        // offset はレイアウト位置を変えないため、mask より後に置かないと
        // 上に伸ばした画像の上端がマスクに切られる（RecordDetailView と同じ）
        .offset(y: -pullDown)
        // レイアウト高さを h に固定し、bottomLeading 揃えのスクリムと
        // アーティスト名が「伸びた画像の下端」に自然と追従するようにする
        .frame(width: geo.size.width, height: h, alignment: .top)

        // 黒スクリムは画像下端のフェードを覆い隠して背景との境目を
        // 作ってしまうため廃止。名前の可読性は背景色の明暗連動で確保する。
        Text(artistName)
          .font(.system(size: 26, weight: .black))
          .foregroundStyle(primaryTextColor)
          .padding(16)
      }
    }
    // 340pt: 従来の 260pt からの拡大分に加え、ignoresSafeArea で画像が
    // ステータスバー裏まで届くようになった分の視覚的な目減りも補う
    .frame(height: 340)
    .frame(maxWidth: .infinity)
  }

  // MARK: - Stats

  private var statsRow: some View {
    HStack {
      statColumn(label: "LIVE", value: "\(records.count)")
      Spacer()
      statColumn(label: "FIRST", value: firstShowText)
      Spacer()
      statColumn(label: "SPENT", value: spentText)
    }
  }

  private func statColumn(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(secondaryTextColor)
        .tracking(1)
      Text(value)
        .font(.system(size: 17, weight: .heavy))
        .foregroundStyle(primaryTextColor)
    }
  }

  private var firstShowText: String {
    let dates = pastRecords.compactMap { DateFormatting.date(from: $0.date) }
    guard let earliest = dates.min() else { return "-" }
    return earliest.formatted(.dateTime.month(.defaultDigits).day())
  }

  private var spentText: String {
    let total = pastRecords.reduce(0.0) { $0 + $1.ticketPrice }
    return total.formatted(.currency(code: "JPY").precision(.fractionLength(0)))
  }

  // MARK: - Year-grouped list

  private var yearGroupedList: some View {
    let groups = Dictionary(grouping: records) { record -> Int in
      guard let date = DateFormatting.date(from: record.date) else { return 0 }
      return ArtistGrouping.utcCalendar.component(.year, from: date)
    }
    let years = groups.keys.sorted(by: >)

    return VStack(alignment: .leading, spacing: 20) {
      ForEach(years, id: \.self) { year in
        VStack(alignment: .leading, spacing: 10) {
          Text(year == 0 ? "-" : String(year))
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(secondaryTextColor)

          ForEach(groups[year] ?? [], id: \.objectID) { record in
            NavigationLink(value: record) {
              RecordRowView(record: record)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  // MARK: - Provider link

  @ViewBuilder
  private var appleMusicLink: some View {
    if let url = URL(string: "https://music.apple.com/search?term=\(artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&entity=artist") {
      Link(destination: url) {
        HugeIconLabel(icon: HugeIcons.musicNote01, size: 13) { Text("Search on Apple Music") }
          .font(.system(size: 13, weight: .semibold))
      }
    }
  }
}
