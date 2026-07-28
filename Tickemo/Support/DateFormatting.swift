import Foundation

/// `CD_ChekiRecord.date`/`startTime`/`endTime` are stored as plain wall-clock
/// strings (`yyyy-MM-dd` / `HH:mm`), not `Date` attributes, per the Phase 1
/// migration design (avoids timezone-conversion risk on imported legacy
/// data). These formatters are fixed to `en_US_POSIX` + a neutral timezone so
/// parsing/formatting never depends on the device's locale or timezone.
enum DateFormatting {
  static let dateFormat = "yyyy-MM-dd"
  static let timeFormat = "HH:mm"

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = dateFormat
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = timeFormat
    return formatter
  }()

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func date(from string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    return dateFormatter.date(from: string)
  }

  static func string(from date: Date) -> String {
    dateFormatter.string(from: date)
  }

  static func time(from string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    return timeFormatter.date(from: string)
  }

  static func timeString(from date: Date) -> String {
    timeFormatter.string(from: date)
  }

  static func isoNow() -> String {
    isoFormatter.string(from: Date())
  }
}
