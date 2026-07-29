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

struct RecordListView: View {
  @Environment(\.managedObjectContext) private var viewContext

  @FetchRequest(
    sortDescriptors: [
      NSSortDescriptor(keyPath: \CD_ChekiRecord.date, ascending: false),
      NSSortDescriptor(keyPath: \CD_ChekiRecord.createdAt, ascending: false),
    ]
  ) private var records: FetchedResults<CD_ChekiRecord>

  @State private var filter: RecordFilter = .all
  @State private var showingCreateSheet = false
  #if DEBUG
  @State private var showingDebugSheet = false
  #endif

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
          showingCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(isPresented: $showingCreateSheet) {
      RecordFormView(record: nil)
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
        Button("Add Ticket") { showingCreateSheet = true }
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
