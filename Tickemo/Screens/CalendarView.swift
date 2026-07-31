import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

/// Ports screens/CalendarScreen.tsx to a month-at-a-time grid (prev/next +
/// Today button) instead of react-native-calendars' 72-month infinite
/// scroll — see the approved plan for why. Weekday labels are a fixed
/// English table (matching RecordDetailView's convention), never a
/// locale-sensitive API, and all date math goes through
/// DateFormatting.utcCalendar — this migration already fixed two separate
/// local-timezone-vs-UTC-string bugs, and the RN source for this exact
/// screen shows three different ad hoc local-timezone anchors fighting the
/// same problem, so this is deliberately not repeated here.
struct CalendarView: View {
  @Environment(\.dismiss) private var dismiss
  @FetchRequest(sortDescriptors: []) private var records: FetchedResults<CD_ChekiRecord>

  @State private var displayedMonth = CalendarMonth.current
  @State private var selectedDay: SelectedCalendarDay?

  private static let weekdayAbbreviations = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

  private var eventsByDate: [String: CalendarDayEvent] {
    let today = DateFormatting.utcCalendar.startOfDay(for: Date())
    return CalendarEvents.eventsByDate(records: Array(records), today: today)
  }

  private var recordsByDate: [String: [CD_ChekiRecord]] {
    CalendarEvents.recordsByDate(records: Array(records))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        header
        weekdayRow
        grid
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .navigationTitle("Calendar")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedDay) { day in
        CalendarDayEventsView(dateString: day.dateString, records: recordsByDate[day.dateString] ?? [])
      }
    }
  }

  private var header: some View {
    HStack {
      Button {
        displayedMonth = displayedMonth.adding(months: -1)
      } label: {
        HugeIconView(icon: HugeIcons.arrowLeft01, size: 20)
      }

      Spacer()

      VStack(spacing: 2) {
        Text(displayedMonth.monthTitle)
          .font(.system(size: 18, weight: .bold))
        if !displayedMonth.isCurrentMonth {
          Button("Today") {
            displayedMonth = .current
          }
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(accentPurple)
        }
      }

      Spacer()

      Button {
        displayedMonth = displayedMonth.adding(months: 1)
      } label: {
        HugeIconView(icon: HugeIcons.arrowRight01, size: 20)
      }
    }
  }

  private var weekdayRow: some View {
    HStack {
      ForEach(Array(Self.weekdayAbbreviations.enumerated()), id: \.offset) { index, label in
        Text(label)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(index == 0 || index == 6 ? Color.secondary : Color.primary)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var grid: some View {
    VStack(spacing: 6) {
      ForEach(Array(displayedMonth.weeks.enumerated()), id: \.offset) { _, week in
        HStack(spacing: 6) {
          ForEach(Array(week.enumerated()), id: \.offset) { columnIndex, cell in
            dayCell(cell, isWeekend: columnIndex == 0 || columnIndex == 6)
              .frame(maxWidth: .infinity)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func dayCell(_ cell: CalendarDayCell, isWeekend: Bool) -> some View {
    if let date = cell.date, let dateString = cell.dateString {
      let event = eventsByDate[dateString]
      let isToday = DateFormatting.utcCalendar.isDate(date, inSameDayAs: DateFormatting.utcCalendar.startOfDay(for: Date()))
      let dayNumber = DateFormatting.utcCalendar.component(.day, from: date)

      Button {
        guard event != nil else { return }
        selectedDay = SelectedCalendarDay(dateString: dateString)
      } label: {
        VStack(spacing: 4) {
          Text("\(dayNumber)")
            .font(.system(size: 14, weight: isToday ? .bold : .regular))
            .foregroundStyle(isToday ? accentPurple : (isWeekend ? Color.secondary : Color.primary))
            .frame(width: 28, height: 28)
            .background(isToday ? accentPurple.opacity(0.15) : Color.clear)
            .clipShape(Circle())

          thumbnailOrDot(for: event)
        }
      }
      .buttonStyle(.plain)
      .disabled(event == nil)
    } else {
      Color.clear.frame(height: 44)
    }
  }

  @ViewBuilder
  private func thumbnailOrDot(for event: CalendarDayEvent?) -> some View {
    switch event?.type {
    case .past:
      if let data = event?.coverImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 20, height: 20)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } else {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color(.systemGray4))
          .frame(width: 20, height: 20)
      }
    case .future:
      Circle()
        .fill(accentPurple)
        .frame(width: 6, height: 6)
        .frame(height: 20)
    case nil:
      Color.clear.frame(width: 20, height: 20)
    }
  }
}
