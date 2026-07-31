import SwiftUI
import CoreData

enum RecordFilter: String, CaseIterable {
  case all
  case upcoming
  case past

  var label: String {
    switch self {
    case .all: "All"
    case .upcoming: "Upcoming"
    case .past: "Past"
    }
  }
}

enum RecordViewMode {
  case list
  case grid
}

/// Matches CollectionScreen.tsx's FREE_TICKET_LIMIT.
private let freeTicketLimit = 3

/// Ports screens/CollectionScreen.tsx. This is the "Home" tab's root
/// screen (see ContentView's TabView) — Settings/Calendar/Statistics moved
/// out to their own tabs, so this view's toolbar now only keeps the
/// actions that are specific to the Home tab itself (view-mode toggle,
/// add-ticket FAB). RN's own All/Upcoming/Past filter dropdown is kept
/// too, but as this screen's existing working segmented Picker: migration
/// research found RN's real filter dropdown UI has no reachable way to
/// open it (dead code), so its filtering logic exists in RN but is never
/// actually usable — replacing a working control with an unreachable one
/// would be a pure regression for zero fidelity benefit.
struct RecordListView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.colorScheme) private var systemColorScheme

  @FetchRequest(
    sortDescriptors: [
      NSSortDescriptor(keyPath: \CD_ChekiRecord.date, ascending: false),
      NSSortDescriptor(keyPath: \CD_ChekiRecord.createdAt, ascending: false),
    ]
  ) private var records: FetchedResults<CD_ChekiRecord>

  @State private var filter: RecordFilter = .all
  @State private var viewMode: RecordViewMode = .list
  @State private var showingCreateSheet = false
  @State private var showingPaywall = false

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: CollectionPalette { CollectionPalette(isDarkMode: isDarkMode) }

  private var isOverFreeTicketLimit: Bool {
    !PurchasesService.shared.isPremium && records.count >= freeTicketLimit
  }

  private func requestAddTicket() {
    if isOverFreeTicketLimit {
      showingPaywall = true
    } else {
      showingCreateSheet = true
    }
  }

  private let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible())]

  private var artistTiles: [ArtistGrouping.Tile] {
    ArtistGrouping.tiles(from: filteredRecords)
  }

  private var filteredRecords: [CD_ChekiRecord] {
    guard filter != .all else { return Array(records) }
    let today = DateFormatting.utcCalendar.startOfDay(for: Date())
    return records.filter { record in
      guard let date = DateFormatting.date(from: record.date) else { return filter == .all }
      switch filter {
      case .all: return true
      case .upcoming: return date >= today
      case .past: return date < today
      }
    }
  }

  // Ports RN's `nextLiveRecord` — always derived from ALL records, not the
  // current filter selection, so the card keeps showing the true next/last
  // live regardless of which segment is picked. Hidden entirely in Grid
  // mode, matching RN's `!isGridLayout`.
  private var nextLiveRecord: CD_ChekiRecord? {
    guard viewMode == .list else { return nil }
    return NextLiveCardData.nextLiveRecord(from: Array(records))
  }

  // RN's `firstSectionLabelRecordIds`: since `filteredRecords` is already
  // sorted farthest-future-first (matching the FetchRequest's descending
  // date sort), the first record satisfying each condition marks the
  // *start* of that segment in the combined list — not literally "the
  // next show" — matching RN's one-time section-divider semantics.
  private var firstUpNextRecordID: NSManagedObjectID? {
    let today = DateFormatting.utcCalendar.startOfDay(for: Date())
    return filteredRecords.first { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return date >= today
    }?.objectID
  }

  private var firstPastEventsRecordID: NSManagedObjectID? {
    let today = DateFormatting.utcCalendar.startOfDay(for: Date())
    return filteredRecords.first { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return date < today
    }?.objectID
  }

  var body: some View {
    Group {
      switch viewMode {
      case .list:
        if filteredRecords.isEmpty {
          emptyState
        } else {
          listContent
        }
      case .grid:
        if artistTiles.isEmpty {
          HugeIconUnavailableView(
            title: "No Artists Yet",
            icon: HugeIcons.userMultiple02,
            description: Text("Tickets with an artist name will show up here.")
          )
        } else {
          ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
              ForEach(artistTiles) { tile in
                NavigationLink(value: ArtistRoute(name: tile.name)) {
                  ArtistGridItemView(tile: tile)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(16)
          }
        }
      }
    }
    .safeAreaInset(edge: .top) {
      Picker("Filter", selection: $filter) {
        ForEach(RecordFilter.allCases, id: \.self) { filter in
          Text(filter.label).tag(filter)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.top, 8)
    }
    .navigationTitle("Collection")
    .navigationDestination(for: CD_ChekiRecord.self) { record in
      RecordDetailView(record: record)
    }
    .navigationDestination(for: ArtistRoute.self) { route in
      ArtistDetailView(artistName: route.name)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          viewMode = (viewMode == .list) ? .grid : .list
        } label: {
          HugeIconView(icon: viewMode == .list ? HugeIcons.userMultiple02 : HugeIcons.ticket01, size: 18)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          requestAddTicket()
        } label: {
          HugeIconView(icon: HugeIcons.add01, size: 18, weight: 2)
        }
      }
    }
    .sheet(isPresented: $showingCreateSheet) {
      RecordFormView(record: nil)
    }
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
    .background(palette.screenBackground)
  }

  // MARK: - List mode

  private var listContent: some View {
    List {
      if let nextLiveRecord {
        NextLiveCardView(record: nextLiveRecord)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        if !PurchasesService.shared.isPremium {
          PaywallBannerView()
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }

      ForEach(filteredRecords, id: \.objectID) { record in
        VStack(alignment: .leading, spacing: 8) {
          if record.objectID == firstUpNextRecordID {
            sectionLeadLabel("Up Next")
          } else if record.objectID == firstPastEventsRecordID {
            sectionLeadLabel("Past Events")
          }
          ZStack(alignment: .leading) {
            NavigationLink(value: record) { EmptyView() }.opacity(0)
            RecordRowView(record: record)
          }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
          Button(role: .destructive) {
            delete(record)
          } label: {
            HugeIconLabel(icon: HugeIcons.delete02) { Text("Delete") }
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func sectionLeadLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14, weight: .heavy))
      .tracking(0.4)
      .foregroundStyle(palette.primaryText)
  }

  // MARK: - Empty state

  // RN's renderEmptyState shows this exact same copy/image/button whenever
  // filteredRecords is empty — there's no separate "no results for this
  // filter" variant, unlike this view's earlier (pre-parity) behavior.
  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 0) {
      Image("TicketEmpty")
        .resizable()
        .scaledToFit()
        .frame(width: 120, height: 120)
        .padding(.bottom, 24)

      // RN hardcodes this text to a fixed light-mode color even in dark
      // mode (buildCollectionPalette defines an adaptive `emptyText` key
      // that the empty-state JSX never actually references) — judged an
      // oversight rather than a deliberate design choice, so this uses the
      // adaptive palette colors instead of replicating the miss.
      Text("Your collection\nis empty")
        .font(.system(size: 22, weight: .heavy))
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.center)
        .padding(.bottom, 10)

      Text("Add from the button above")
        .font(.system(size: 15))
        .foregroundStyle(palette.emptyText)
        .multilineTextAlignment(.center)
        .padding(.bottom, 24)

      Button {
        requestAddTicket()
      } label: {
        Text("Add your first live")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .padding(.vertical, 14)
          .padding(.horizontal, 24)
          .frame(minWidth: 172)
          .background(Color(hex: "#A328DD"))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 32)
    .padding(.bottom, 120)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func delete(_ record: CD_ChekiRecord) {
    viewContext.delete(record)
    try? viewContext.save()
  }
}
