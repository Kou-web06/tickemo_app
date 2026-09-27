import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)
// チケットの予定（座席発表・チケット申込・支払い期限）の印。ライブ当日の
// 紫と見分けられる色にしている
private let ticketScheduleColor = Color.orange

/// Ports screens/CalendarScreen.tsx to a month-at-a-time grid (prev/next +
/// Today button) instead of react-native-calendars' 72-month infinite
/// scroll — see the approved plan for why. Weekday labels are a fixed
/// English table (matching RecordDetailView's convention), never a
/// locale-sensitive API, and all date math goes through
/// DateFormatting.utcCalendar — this migration already fixed two separate
/// local-timezone-vs-UTC-string bugs, and the RN source for this exact
/// screen shows three different ad hoc local-timezone anchors fighting the
/// same problem, so this is deliberately not repeated here. Root of the
/// "Calendar" tab (see ContentView), so it self-wraps a NavigationStack for
/// its own title bar but has no dismiss chrome — it's a permanent tab page.
struct CalendarView: View {
  // ContentView が「タブのルートにいるか」を判定してアバターボタンの
  // 表示を切り替えるための、外部から渡されるナビゲーション経路。
  @Binding var path: NavigationPath

  @FetchRequest(sortDescriptors: []) private var records: FetchedResults<CD_ChekiRecord>

  @State private var displayedMonth = CalendarMonth.current
  @State private var selectedDay: SelectedCalendarDay? = SelectedCalendarDay(
    dateString: DateFormatting.string(from: DateFormatting.utcCalendar.startOfDay(for: Date()))
  )

  // 言語設定は廃止し日本語のみに絞った（設定画面の項目も削除済み）
  private let useJapanese = true

  private var weekdayLabels: [String] {
    useJapanese
      ? ["日", "月", "火", "水", "木", "金", "土"]
      : ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
  }

  private var monthTitle: String {
    useJapanese
      ? "\(displayedMonth.year)年\(displayedMonth.month)月"
      : displayedMonth.monthTitle
  }

  private var eventsByDate: [String: CalendarDayEvent] {
    let today = DateFormatting.utcCalendar.startOfDay(for: Date())
    return CalendarEvents.eventsByDate(records: Array(records), today: today)
  }

  private var recordsByDate: [String: [CD_ChekiRecord]] {
    CalendarEvents.recordsByDate(records: Array(records))
  }

  private var scheduleItemsByDate: [String: [TicketSchedule.CalendarItem]] {
    TicketSchedule.itemsByDate(records: Array(records))
  }

  private func hasContent(on dateString: String) -> Bool {
    !(recordsByDate[dateString] ?? []).isEmpty || !(scheduleItemsByDate[dateString] ?? []).isEmpty
  }

  @Environment(\.appFontChoice) private var appFont
  @Environment(\.appBgColor) private var bgColor
  @Environment(\.colorScheme) private var systemColorScheme

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  // Home/MyPage タブと揃えたデフォルト背景（#F3F2F8）。ダークモードは
  // 既存どおり systemBackground のまま変更しない。
  private var defaultScreenBackground: Color {
    isDarkMode ? Color(.systemBackground) : Color(hex: "#F3F2F8")
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(spacing: 16) {
          header
          weekdayRow
          grid

          if let day = selectedDay, hasContent(on: day.dateString) {
            dayEventsSection(day: day)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .animation(.spring(duration: 0.3), value: selectedDay?.dateString)
      }
      .navigationTitle(useJapanese ? "カレンダー" : "Calendar")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: CD_ChekiRecord.self) { record in
        RecordDetailView(record: record)
      }
      // RecordDetailView の #artist カードからの遷移先。RecordListView が
      // ホーム側のスタックに登録しているのと同じもので、カレンダー側の
      // スタックにも要る。
      .navigationDestination(for: ArtistRoute.self) { route in
        ArtistDetailView(artistName: route.name)
      }
      .background((bgColor ?? defaultScreenBackground).ignoresSafeArea())
    }
  }

  private var header: some View {
    HStack {
      Button {
        displayedMonth = displayedMonth.adding(months: -1)
        selectedDay = nil
      } label: {
        HugeIconView(icon: HugeIcons.arrowLeft01, size: 20)
      }

      Spacer()

      VStack(spacing: 2) {
        Text(monthTitle)
          .font(appFont.bold(18))
        if !displayedMonth.isCurrentMonth {
          Button(useJapanese ? "今日" : "Today") {
            displayedMonth = .current
            selectedDay = SelectedCalendarDay(
              dateString: DateFormatting.string(from: DateFormatting.utcCalendar.startOfDay(for: Date()))
            )
          }
          .font(appFont.bold(12))
          .foregroundStyle(accentPurple)
        }
      }

      Spacer()

      Button {
        displayedMonth = displayedMonth.adding(months: 1)
        selectedDay = nil
      } label: {
        HugeIconView(icon: HugeIcons.arrowRight01, size: 20)
      }
    }
  }

  private var weekdayRow: some View {
    HStack {
      ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
        Text(label)
          .font(appFont.bold(11))
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
      let hasSchedule = !(scheduleItemsByDate[dateString] ?? []).isEmpty
      let isToday = DateFormatting.utcCalendar.isDate(date, inSameDayAs: DateFormatting.utcCalendar.startOfDay(for: Date()))
      let isSelected = selectedDay?.dateString == dateString
      let dayNumber = DateFormatting.utcCalendar.component(.day, from: date)

      Button {
        guard event != nil || hasSchedule else { return }
        selectedDay = (selectedDay?.dateString == dateString) ? nil : SelectedCalendarDay(dateString: dateString)
      } label: {
        VStack(spacing: 4) {
          Text("\(dayNumber)")
            .font((isToday || isSelected) ? appFont.bold(14) : appFont.regular(14))
            .foregroundStyle(
              isSelected ? .white :
              isToday ? accentPurple :
              isWeekend ? Color.secondary : Color.primary
            )
            .frame(width: 28, height: 28)
            .background(
              isSelected ? accentPurple :
              isToday ? accentPurple.opacity(0.15) : Color.clear
            )
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
              if hasSchedule {
                Circle()
                  .fill(ticketScheduleColor)
                  .frame(width: 6, height: 6)
                  .offset(x: 2, y: -1)
              }
            }

          thumbnailOrDot(for: event)
        }
      }
      .buttonStyle(.plain)
      .disabled(event == nil && !hasSchedule)
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

  // MARK: - Inline day events

  private func formattedDayHeader(_ dateString: String) -> String {
    guard useJapanese, let date = DateFormatting.date(from: dateString) else { return dateString }
    let cal = DateFormatting.utcCalendar
    let month = cal.component(.month, from: date)
    let day = cal.component(.day, from: date)
    let weekdayIndex = cal.component(.weekday, from: date) - 1
    let jpWeekdays = ["日", "月", "火", "水", "木", "金", "土"]
    return "\(month)月\(day)日（\(jpWeekdays[weekdayIndex])）"
  }

  private func dayEventsSection(day: SelectedCalendarDay) -> some View {
    let dayRecords = recordsByDate[day.dateString] ?? []
    return VStack(alignment: .leading, spacing: 12) {
      Text(formattedDayHeader(day.dateString))
        .font(appFont.bold(12))
        .foregroundStyle(Color.secondary)
        .tracking(0.5)
        .padding(.top, 4)

      ForEach(scheduleItemsByDate[day.dateString] ?? [], id: \.id) { item in
        NavigationLink(value: item.record) {
          scheduleRow(item)
        }
        .buttonStyle(.plain)
      }

      ForEach(dayRecords, id: \.objectID) { record in
        NavigationLink(value: record) {
          RecordRowView(record: record)
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// チケットの予定1件。タップでそのライブの詳細へ
  private func scheduleRow(_ item: TicketSchedule.CalendarItem) -> some View {
    HStack(spacing: 10) {
      Text(item.entry.kind.label)
        .font(appFont.bold(11))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(ticketScheduleColor))
      Text(item.entry.timeString)
        .font(appFont.bold(14))
        .foregroundStyle(Color.primary)
      Text(item.record.liveName?.isEmpty == false ? item.record.liveName! : "-")
        .font(appFont.regular(14))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
      Spacer(minLength: 0)
      HugeIconView(icon: HugeIcons.arrowRight01, size: 14)
        .foregroundStyle(Color.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    .contentShape(Rectangle())
  }
}
