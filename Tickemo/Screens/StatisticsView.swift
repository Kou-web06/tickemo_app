import SwiftUI
import Charts

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports screens/StatisticsScreen.tsx: a year-chip filter row, a stats strip,
/// TOP ARTISTS/ALL ARTISTS/MONTHLY LIVES/TOP VENUES/TOP SONGS/TOTAL SPENDING
/// sections. All grouping/sorting/tie-expansion logic lives in
/// StatisticsData (pure, unit-tested); this view only lays it out. The
/// monthly bar chart uses Swift Charts rather than RN's
/// react-native-gifted-charts dependency — a single flat bar series needs
/// nothing gifted-charts-specific. Total-spending hide/reveal is a plain
/// non-persisted @State, matching RN's own (non-persisted) toggle exactly.
struct StatisticsView: View {
  @Environment(\.dismiss) private var dismiss
  @FetchRequest(sortDescriptors: []) private var records: FetchedResults<CD_ChekiRecord>

  @State private var selectedYear: Int?
  @State private var priceHidden = false

  private var attendedRecords: [CD_ChekiRecord] {
    StatisticsData.attendedRecords(Array(records), now: Date())
  }

  private var availableYears: [Int] {
    StatisticsData.availableYears(attendedRecords)
  }

  private var filteredRecords: [CD_ChekiRecord] {
    StatisticsData.yearFiltered(attendedRecords, year: selectedYear)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          yearChips
          summarySection
          topArtistsSection
          allArtistsSection
          monthlyChartSection
          topVenuesSection
          topSongsSection
          spendingSection
        }
        .padding(16)
      }
      .navigationTitle("Statistics")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .navigationDestination(for: ArtistRoute.self) { route in
        ArtistDetailView(artistName: route.name)
      }
      .onChange(of: availableYears) { _, years in
        if let year = selectedYear, !years.contains(year) {
          selectedYear = nil
        }
      }
    }
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
              thumbnail: .coverImage(item.coverImageData)
            )
          }
        }
      }
    }
  }

  private var allArtistsSection: some View {
    let items = StatisticsData.allArtists(filteredRecords)
    return sectionContainer(title: "ALL ARTISTS") {
      if items.isEmpty {
        emptyRow
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(items) { entry in
              NavigationLink(value: ArtistRoute(name: entry.name)) {
                ArtistArchiveCardView(entry: entry)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
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
          Image(systemName: priceHidden ? "eye.slash" : "eye")
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
