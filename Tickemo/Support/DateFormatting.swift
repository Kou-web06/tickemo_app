import Foundation

/// `CD_ChekiRecord.date`/`startTime`/`endTime` are stored as plain wall-clock
/// strings (`yyyy-MM-dd` / `HH:mm`), not `Date` attributes, per the Phase 1
/// migration design (avoids timezone-conversion risk on imported legacy
/// data). These formatters are fixed to `en_US_POSIX` + a neutral timezone so
/// parsing/formatting never depends on the device's locale or timezone.
enum DateFormatting {
  static let dateFormat = "yyyy-MM-dd"
  static let timeFormat = "HH:mm"

  /// The single fixed timezone all date/time string conversions use.
  /// SwiftUI views that let the user pick a `date`/`startTime`/`endTime`
  /// value (e.g. RecordFormView's DatePickers) must inject this via
  /// `.environment(\.timeZone, DateFormatting.timeZone)` so what's shown on
  /// screen and what gets parsed/formatted here stay in sync — otherwise
  /// DatePicker interprets/produces Date values in the device's local
  /// timezone, which can shift the stored calendar day by one.
  static let timeZone = TimeZone(identifier: "UTC")!

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = dateFormat
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
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

  /// Parses a `createdAt`/`joinedAt`/`plusStartedAt`-style ISO8601 string
  /// (with fractional seconds, as produced by `isoNow()`). A bare
  /// `ISO8601DateFormatter()` with default options fails to parse these
  /// because it doesn't enable `.withFractionalSeconds` — use this instead
  /// of constructing a formatter ad hoc at each call site.
  static func isoDate(from string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    return isoFormatter.date(from: string)
  }
}
