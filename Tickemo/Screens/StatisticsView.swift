import SwiftUI
import Charts
import MusicKit
import UIKit

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports screens/StatisticsScreen.tsx: a year-chip filter row, a stats strip,
/// TOP ARTISTS/ALL ARTISTS/MONTHLY LIVES/TOP VENUES/TOP SONGS/TOTAL SPENDING
/// sections. All grouping/sorting/tie-expansion logic lives in
/// StatisticsData (pure, unit-tested); this view only lays it out. The
/// monthly bar chart uses Swift Charts rather than RN's
/// react-native-gifted-charts dependency — a single flat bar series needs
/// nothing gifted-charts-specific. Total-spending hide/reveal is a plain
/// non-persisted @State, matching RN's own (non-persisted) toggle exactly.
/// Root of the "Report" tab (see ContentView), so it self-wraps a
/// NavigationStack for its own title bar but has no dismiss chrome — it's a
/// permanent tab page, not a sheet.
struct StatisticsView: View {
  @FetchRequest(sortDescriptors: []) private var records: FetchedResults<CD_ChekiRecord>

  @State private var selectedYear: Int?
  @State private var priceHidden = false
  @State private var showingPaywall = false

  // Non-persisted, in-memory cache of live-searched artist photos for
  // records saved without one (e.g. typed before ArtistSearchField existed,
  // or picked with no MusicKit match). Matches RN's own `artistImages`
  // React state exactly: keyed by lowercased name, top-1-result search,
  // never written back to the record.
  @State private var artistImageBackfill: [String: String] = [:]
  // Refreshed after every backfill attempt (see backfillArtistImages) so a
  // denied/restricted Apple Music permission — which otherwise makes every
  // backfill search silently return nothing — is visible here too. Someone
  // who never opens RecordFormView's ArtistSearchField (where this same
  // check also lives) would otherwise have no way to learn why TOP/ALL
  // ARTISTS never show photos.
  @State private var musicAuthorizationStatus = MusicAuthorization.currentStatus
  private let appleMusicService = AppleMusicService()

  private var attendedRecords: [CD_ChekiRecord] {
    StatisticsData.attendedRecords(Array(records), now: Date())
  }

  private var availableYears: [Int] {
    StatisticsData.availableYears(attendedRecords)
  }

  private var filteredRecords: [CD_ChekiRecord] {
    StatisticsData.yearFiltered(attendedRecords, year: selectedYear)
  }

  // Tickemo Plus: free users only get the current year's report — every
  // other year chip and All-Time are blurred behind a paywall. Matches
  // availableYears' own year derivation (DateFormatting.utcCalendar), never
  // Calendar.current, so "this year" can't drift a day off from how those
  // years were computed in the first place.
  private var isPremium: Bool { PurchasesService.shared.isPremium }
  private var currentYear: Int { DateFormatting.utcCalendar.component(.year, from: Date()) }
  private var isLocked: Bool { !isPremium && selectedYear != currentYear }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          yearChips
          authorizationWarning

          ZStack {
            VStack(alignment: .leading, spacing: 28) {
              summarySection
              topArtistsSection
              allArtistsSection
              monthlyChartSection
              topVenuesSection
              topSongsSection
              spendingSection
            }
            .blur(radius: isLocked ? 14 : 0)
            .allowsHitTesting(!isLocked)

            if isLocked {
              lockOverlay
            }
          }
        }
        .padding(16)
      }
      .navigationTitle("Report")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: ArtistRoute.self) { route in
        ArtistDetailView(artistName: route.name)
      }
      // ArtistDetailView 内の各ライブ行（NavigationLink(value: record)）の
      // 遷移先。Collection タブと違いこのスタックには未登録だったため、
      // Report 経由で開いたアーティスト画面から詳細に飛べなかった。
      .navigationDestination(for: CD_ChekiRecord.self) { record in
        RecordDetailView(record: record)
      }
      .onChange(of: availableYears) { _, years in
        if let year = selectedYear, !years.contains(year) {
          selectedYear = nil
        }
      }
      .sheet(isPresented: $showingPaywall) {
        PaywallView()
      }
    }
  }

  // MARK: - Plus lock overlay

  private var lockOverlay: some View {
    Button {
      showingPaywall = true
    } label: {
      VStack(spacing: 8) {
        HugeIconView(icon: HugeIcons.squareLock02, size: 28)
        Text("Upgrade to Plus")
          .font(.system(size: 15, weight: .heavy))
        Text("過去の年やAll-TimeのレポートはPlus限定です")
          .font(.system(size: 12))
          .multilineTextAlignment(.center)
      }
      .foregroundStyle(Color(white: 0.18))
      .padding(.horizontal, 22)
      .padding(.vertical, 14)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Year chips

  private var yearChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        yearChip(title: "All-Time", isActive: selectedYear == nil) { selectedYear = nil }
        ForEach(availableYears, id: \.self) { year in
          yearChip(title: "\(year)", isActive: selectedYear == year) { selectedYear = year }
        }
      }
    }
  }

  @ViewBuilder
  private var authorizationWarning: some View {
    if musicAuthorizationStatus == .denied || musicAuthorizationStatus == .restricted {
      HStack(spacing: 8) {
        HugeIconView(icon: HugeIcons.alert01, size: 17)
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("Apple Music access is off")
            .font(.system(size: 13, weight: .semibold))
          Text("Turn it on in Settings to show official artist photos.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Button("Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
      }
      .padding(12)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }

  private func yearChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isActive ? .white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isActive ? accentPurple : Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Stats strip

  private var summarySection: some View {
    let summary = StatisticsData.summary(filteredRecords)
    return HStack {
      statBlock(label: "LIVE", value: "\(summary.totalLives)")
      Spacer()
      statBlock(label: "ARTISTS", value: "\(summary.totalArtists)")
      Spacer()
      statBlock(label: "VENUES", value: "\(summary.totalVenues)")
    }
  }

  private func statBlock(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Color(white: 0.557))
        .tracking(1)
      Text(value)
        .font(.system(size: 20, weight: .heavy))
        .foregroundStyle(Color(red: 0.188, green: 0.188, blue: 0.212))
    }
  }

  // MARK: - Sections

  private var topArtistsSection: some View {
    let items = StatisticsData.topArtists(filteredRecords)
    let missingNames = items.filter { $0.artistImageUrl == nil }.map(\.name)
    return sectionContainer(title: "TOP ARTISTS") {
      if items.isEmpty {
        emptyRow
      } else {
        VStack(spacing: 12) {
          ForEach(items) { item in
            StatisticsRankingRow(
              rank: item.rank,
              name: item.name,
              detail: "\(item.count) lives",
              thumbnail: .artworkUrl(item.artistImageUrl ?? artistImageBackfill[item.name.lowercased()]),
              imageShape: .circle
            )
          }
        }
      }
    }
    .task(id: missingNames) {
      // ArtistDetailView の背景色を先読み（ヒーローと同じ 800px URL）。
      // バックフィルで埋まる分は backfillArtistImages 側で先読みする。
      for item in items {
        DominantColorCache.shared.prewarm(urlString: item.artistImageUrl, mode: .dominant)
      }
      await backfillArtistImages(names: missingNames)
    }
  }

  private var allArtistsSection: some View {
    let items = StatisticsData.allArtists(filteredRecords)
    let missingNames = items.filter { $0.artistImageUrl == nil }.map(\.name)
    return sectionContainer(title: "ALL ARTISTS") {
      if items.isEmpty {
        emptyRow
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(items) { entry in
              NavigationLink(value: ArtistRoute(name: entry.name)) {
                ArtistArchiveCardView(entry: resolved(entry))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .task(id: missingNames) {
      for entry in items {
        DominantColorCache.shared.prewarm(urlString: entry.artistImageUrl, mode: .dominant)
      }
      await backfillArtistImages(names: missingNames)
    }
  }

  private func resolved(_ entry: ArtistArchiveEntry) -> ArtistArchiveEntry {
    guard entry.artistImageUrl == nil, let backfilled = artistImageBackfill[entry.name.lowercased()] else {
      return entry
    }
    return ArtistArchiveEntry(id: entry.id, name: entry.name, lastLiveDateText: entry.lastLiveDateText, artistImageUrl: backfilled)
  }

  /// Mirrors RN's per-name live-search backfill effects for TOP ARTISTS/ALL
  /// ARTISTS (the only two sections that do this): a top-1 MusicKit search
  /// per missing name, cached in `artistImageBackfill` so it only ever runs
  /// once per name per app session, never persisted back to the record.
  private func backfillArtistImages(names: [String]) async {
    // Locked (blurred, Plus-gated) sections aren't legible anyway — skip
    // the network search rather than spending it on content the free user
    // can't read.
    guard !isLocked else { return }
    for name in names {
      let key = name.lowercased()
      if artistImageBackfill[key] != nil { continue }
      if let url = await appleMusicService.bestMatchArtistImageUrl(for: name) {
        let resolved = AppleMusicService.resolvedArtworkURL(url, size: 800)
        artistImageBackfill[key] = resolved
        // ArtistDetailView も同じ URL に解決するので、背景色をここで先読み
        DominantColorCache.shared.prewarm(urlString: resolved, mode: .dominant)
      }
    }
    musicAuthorizationStatus = MusicAuthorization.currentStatus
  }

  private var monthlyChartSection: some View {
    let buckets = StatisticsData.monthlyBuckets(filteredRecords)
    return sectionContainer(title: "MONTHLY LIVES") {
      Chart(buckets) { bucket in
        BarMark(x: .value("Month", bucket.label), y: .value("Lives", bucket.count))
          .foregroundStyle(accentPurple)
          .cornerRadius(4)
      }
      .frame(height: 140)
      .chartYAxis(.hidden)
    }
  }

  private var topVenuesSection: some View {
    let items = StatisticsData.topVenues(filteredRecords)
    return sectionContainer(title: "TOP VENUES") {
      if items.isEmpty {
        emptyRow
      } else {
        VStack(spacing: 12) {
          ForEach(items) { item in
            StatisticsRankingRow(rank: item.rank, name: item.name, detail: "\(item.count) lives", thumbnail: .none)
          }
        }
      }
    }
  }

  private var topSongsSection: some View {
    let items = StatisticsData.topSongs(filteredRecords)
    return sectionContainer(title: "TOP SONGS") {
      if items.isEmpty {
        emptyRow
      } else {
        VStack(spacing: 12) {
          ForEach(items) { item in
            StatisticsRankingRow(
              rank: item.rank,
              name: item.name,
              detail: "\(item.count) plays",
              thumbnail: .artworkUrl(item.artworkUrl)
            )
          }
        }
      }
    }
  }

  private var spendingSection: some View {
    let total = StatisticsData.totalSpending(filteredRecords)
    return sectionContainer(title: "TOTAL SPENDING") {
      HStack {
        Text(priceHidden ? "¥ ••••••" : total.formatted(.currency(code: "JPY").precision(.fractionLength(0))))
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(Color(red: 0.188, green: 0.188, blue: 0.212))
        Spacer()
        Button {
          priceHidden.toggle()
        } label: {
          HugeIconView(icon: priceHidden ? HugeIcons.viewOffSlash : HugeIcons.view, size: 18)
        }
      }
    }
  }

  // MARK: - Shared section chrome

  private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(Color(white: 0.557))
        .tracking(1)
      content()
    }
  }

  private var emptyRow: some View {
    Text("No data yet")
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
  }
}
