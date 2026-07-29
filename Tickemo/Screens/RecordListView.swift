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

struct RecordListView: View {
  @Environment(\.managedObjectContext) private var viewContext

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
  @State private var showingSettings = false
  @State private var showingCalendar = false
  #if DEBUG
  @State private var showingDebugSheet = false
  #endif

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
    // record.date is parsed as a UTC calendar day (see DateFormatting), so
    // "today" must be computed the same way — using the device's local
    // calendar here would shift the upcoming/past boundary by the device's
    // UTC offset.
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = DateFormatting.timeZone
    let today = utcCalendar.startOfDay(for: Date())
    return records.filter { record in
      guard let date = DateFormatting.date(from: record.date) else { return filter == .all }
      switch filter {
      case .all: return true
      case .upcoming: return date >= today
      case .past: return date < today
      }
    }
  }

  var body: some View {
    Group {
      switch viewMode {
      case .list:
        if filteredRecords.isEmpty {
          emptyState
        } else {
          List {
            ForEach(filteredRecords, id: \.objectID) { record in
              NavigationLink(value: record) {
                RecordRowView(record: record)
              }
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  delete(record)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
          .listStyle(.plain)
        }
      case .grid:
        if artistTiles.isEmpty {
          ContentUnavailableView(
            "No Artists Yet",
            systemImage: "person.2",
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
      #if DEBUG
      ToolbarItem(placement: .topBarLeading) {
        Button {
          showingDebugSheet = true
        } label: {
          Image(systemName: "wrench.and.screwdriver")
        }
      }
      #endif
      ToolbarItem(placement: .primaryAction) {
        Button {
          viewMode = (viewMode == .list) ? .grid : .list
        } label: {
          Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          requestAddTicket()
        } label: {
          Image(systemName: "plus")
        }
      }
      ToolbarItem(placement: .topBarLeading) {
        Button {
          showingSettings = true
        } label: {
          Image(systemName: "gearshape")
        }
      }
      ToolbarItem(placement: .topBarLeading) {
        Button {
          showingCalendar = true
        } label: {
          Image(systemName: "calendar")
        }
      }
    }
    .sheet(isPresented: $showingCreateSheet) {
      RecordFormView(record: nil)
    }
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
    .sheet(isPresented: $showingCalendar) {
      CalendarView()
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
    }
    #if DEBUG
    .sheet(isPresented: $showingDebugSheet) {
      DebugToolsView()
    }
    #endif
  }

  @ViewBuilder
  private var emptyState: some View {
    if records.isEmpty {
      ContentUnavailableView {
        Label("No Tickets Yet", systemImage: "ticket")
      } description: {
        Text("Add your first live ticket to get started.")
      } actions: {
        Button("Add Ticket") { requestAddTicket() }
      }
    } else {
      ContentUnavailableView(
        "No \(filter.label) Tickets",
        systemImage: "ticket",
        description: Text("No tickets match this filter.")
      )
    }
  }

  private func delete(_ record: CD_ChekiRecord) {
    viewContext.delete(record)
    try? viewContext.save()
  }
}
