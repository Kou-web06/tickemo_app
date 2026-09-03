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

  /// RN's persisted spelling — see `date(from:)`.
  private static let dottedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter
  }()

  private static let slashedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy/MM/dd"
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

  /// `ISO8601DateFormatter` is all-or-nothing about fractional seconds, and
  /// legacy `createdAt` values aren't uniformly one or the other (RN wrote
  /// most of them with `toISOString()`, but a few code paths didn't). Kept
  /// as a second attempt rather than replacing the primary formatter so the
  /// common case stays a single parse.
  private static let isoFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  /// Accepts the dotted and slashed spellings as well as the canonical
  /// `yyyy-MM-dd`.
  ///
  /// This is not defensive padding: RN stored every date as `2025.01.12`
  /// (`RecordsContext.tsx`'s `normalizeDateFormat` rewrites `-` to `.` on
  /// both the read and write paths), so *all* migrated records arrive in
  /// the dotted form. It happens to parse today only because ICU tolerates
  /// a mismatched literal separator — undocumented behaviour that would
  /// take every date-dependent screen down with it if it ever tightened.
  /// Listing the formats explicitly makes the support deliberate.
  static func date(from string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    return dateFormatter.date(from: string)
      ?? dottedDateFormatter.date(from: string)
      ?? slashedDateFormatter.date(from: string)
  }

  static func string(from date: Date) -> String {
    dateFormatter.string(from: date)
  }

  /// 表示・書き出し用の "yyyy.MM.dd"。保存形式は `string(from:)` の
  /// "yyyy-MM-dd" のままなので、こちらは人が読む所にだけ使うこと。
  static func dottedString(from date: Date) -> String {
    dottedDateFormatter.string(from: date)
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
      ?? isoFormatterWithoutFractionalSeconds.date(from: string)
  }

  /// Shared UTC-anchored calendar for extracting components (year/month/
  /// day/weekday) from dates parsed via `date(from:)`, matching the
  /// convention already used ad hoc in ArtistGrouping/RecordDetailView/
  /// RecordListView — `Calendar.current` must never be used for this, since
  /// it would reintroduce the local-timezone-vs-UTC-string mismatch bugs
  /// this migration already found and fixed twice.
  static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}
