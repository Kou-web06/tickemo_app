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
    .navigationTitle(artistName)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: artistName) {
      guard heroImageUrl == nil, backfillImageUrl == nil else { return }
      guard let url = await appleMusicService.bestMatchArtistImageUrl(for: artistName) else { return }
      backfillImageUrl = AppleMusicService.resolvedArtworkURL(url, size: 900)
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

  @ViewBuilder
  private var hero: some View {
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
      .frame(height: 260)
      .frame(maxWidth: .infinity)
      .clipped()

      LinearGradient(
        colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
        startPoint: .bottom,
        endPoint: .top
      )
      .frame(height: 140)

      Text(artistName)
        .font(.system(size: 26, weight: .black))
        .foregroundStyle(.white)
        .padding(16)
    }
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
        .foregroundStyle(Color(white: 0.557))
        .tracking(1)
      Text(value)
        .font(.system(size: 17, weight: .heavy))
        .foregroundStyle(Color(red: 0.188, green: 0.188, blue: 0.212))
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
            .foregroundStyle(Color(white: 0.557))

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
