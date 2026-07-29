import Foundation

/// One cell in a 6x7 (42-cell) month grid. `date`/`dateString` are nil for
/// the leading/trailing blank cells before the 1st and after the last day
/// of the month.
struct CalendarDayCell: Identifiable {
  let id: Int
  let date: Date?
  let dateString: String?
}

/// Pure month-grid layout, no SwiftUI/CoreData dependency — always UTC-
/// anchored (via `DateFormatting.utcCalendar`) so which weekday column a
/// day lands in never depends on the device's timezone or locale, matching
/// the convention already established across this migration.
struct CalendarMonth {
  let year: Int
  let month: Int // 1...12
  /// Always exactly 6 rows x 7 columns (Sunday-first), so switching months
  /// never changes the grid's height.
  let weeks: [[CalendarDayCell]]

  private static let monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ]

  var monthTitle: String {
    "\(Self.monthNames[month - 1]) \(year)"
  }

  static func make(year: Int, month: Int) -> CalendarMonth {
    let calendar = DateFormatting.utcCalendar
    var firstOfMonthComponents = DateComponents()
    firstOfMonthComponents.year = year
    firstOfMonthComponents.month = month
    firstOfMonthComponents.day = 1

    guard let firstOfMonth = calendar.date(from: firstOfMonthComponents) else {
      return CalendarMonth(year: year, month: month, weeks: [])
    }

    let weekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
    let leadingBlanks = weekday - 1
    let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

    var cells: [CalendarDayCell] = []
    for _ in 0..<leadingBlanks {
      cells.append(CalendarDayCell(id: cells.count, date: nil, dateString: nil))
    }
    for day in 1...daysInMonth {
      var components = firstOfMonthComponents
      components.day = day
      let date = calendar.date(from: components)
      let dateString = date.map { DateFormatting.string(from: $0) }
      cells.append(CalendarDayCell(id: cells.count, date: date, dateString: dateString))
    }
    while cells.count < 42 {
      cells.append(CalendarDayCell(id: cells.count, date: nil, dateString: nil))
    }

    let weeks = stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    return CalendarMonth(year: year, month: month, weeks: weeks)
  }

  func adding(months delta: Int) -> CalendarMonth {
    let calendar = DateFormatting.utcCalendar
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let currentDate = calendar.date(from: components),
          let newDate = calendar.date(byAdding: .month, value: delta, to: currentDate)
    else {
      return self
    }
    return CalendarMonth.make(
      year: calendar.component(.year, from: newDate),
      month: calendar.component(.month, from: newDate)
    )
  }

  static var current: CalendarMonth {
    let calendar = DateFormatting.utcCalendar
    let today = calendar.startOfDay(for: Date())
    return make(year: calendar.component(.year, from: today), month: calendar.component(.month, from: today))
  }

  var isCurrentMonth: Bool {
    let current = Self.current
    return year == current.year && month == current.month
  }
}
