import SwiftUI

struct SelectedCalendarDay: Identifiable {
  let dateString: String
  var id: String { dateString }
}

/// Day-tap sheet for CalendarView. Unlike CalendarScreen.tsx's static
/// inline modal list, this reuses RecordRowView and lets tapping a record
/// push to RecordDetailView — a natural improvement given SwiftUI's
/// sheet+NavigationStack composition, matching the precedent already set
/// by ArtistDetailView reusing RecordRowView with real navigation.
struct CalendarDayEventsView: View {
  let dateString: String
  let records: [CD_ChekiRecord]

  var body: some View {
    NavigationStack {
      List(records, id: \.objectID) { record in
        NavigationLink(value: record) {
          RecordRowView(record: record)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      }
      .listStyle(.plain)
      .navigationTitle(dateString)
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: CD_ChekiRecord.self) { record in
        RecordDetailView(record: record)
      }
    }
  }
}
