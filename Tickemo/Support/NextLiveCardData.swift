import Foundation

/// Ports screens/CollectionScreen.tsx's Next Live card logic (the
/// `nextLiveRecord`/`isNextLivePast`/`NextLiveCountdown` computations) as
/// pure, testable functions. Deliberately uses `DateFormatting.utcCalendar`
/// rather than RN's own `new Date(); setHours(0,0,0,0)` (device-local
/// midnight) — this migration has already found and fixed this exact class
/// of bug (local-timezone boundary vs the UTC-anchored date strings stored
/// on the record) multiple times elsewhere, so it's not replicated here.
enum NextLiveCardData {
  /// Selects RN's `nextLiveRecord`: the soonest record whose *date* (not
  /// time-of-day) is today or later, sorted ascending; if none qualify,
  /// falls back to the single most recent record overall (necessarily in
  /// the past, matching RN's `sortedRecords[0]`). This selection is
  /// date-only — RN's own `toTime` helper ignores `startTime` — unlike
  /// `instant(for:)` below, which factors it in for the countdown target.
  static func nextLiveRecord(from records: [CD_ChekiRecord], now: Date = Date()) -> CD_ChekiRecord? {
    let today = jstCalendar.startOfDay(for: now)
    let dated = records.compactMap { record -> (record: CD_ChekiRecord, date: Date)? in
      guard let date = DateFormatting.date(from: record.date) else { return nil }
      return (record, date)
    }

    let upcoming = dated.filter { $0.date >= today }.sorted { $0.date < $1.date }
    if let first = upcoming.first {
      return first.record
    }
    return dated.max { $0.date < $1.date }?.record
  }

  /// The full date+time instant used for the countdown target.
  /// endTime (Show start / 開演) is preferred over startTime (Doors open / 開場),
  /// falling back to startTime when endTime is absent, then defaulting to 18:00.
  static func instant(for record: CD_ChekiRecord) -> Date? {
    guard let day = DateFormatting.date(from: record.date) else { return nil }
    let rawTime: String
    if let t = record.endTime, !t.isEmpty {
      rawTime = t
    } else if let t = record.startTime, !t.isEmpty {
      rawTime = t
    } else {
      rawTime = "18:00"
    }
    let parts = rawTime.split(separator: ":").compactMap { Int($0) }
    guard let hour = parts.first else { return day }
    let minute = parts.count > 1 ? parts[1] : 0
    // 開演時刻はJST（日本時間）で入力されるため、UTCカレンダーで適用すると
    // 9時間ズレる。Asia/Tokyoカレンダーで正しく解釈する。
    return jstCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
  }

  private static let jstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return cal
  }()

  /// Selects the soonest record that hasn't finished *its day* yet, ordered
  /// by countdown target. Returns nil when every record is in the past —
  /// intended for the widget, where showing a long-gone live makes no sense.
  ///
  /// The cutoff is end-of-day rather than `instant(for:) > now` on purpose.
  /// Filtering on the instant makes the widget go blank the moment the live
  /// starts, which is exactly when the user is most likely to look at it,
  /// and it leaves the widget's own "see you next live !!" state
  /// unreachable — `CountdownView` renders that for `remaining <= 0`, which
  /// can only happen if a record whose instant has passed is still
  /// selected. Keeping the live until midnight JST makes both behave.
  // Selects the soonest upcoming record for the widget.
  // Uses the same date >= today (JST) comparison as nextLiveRecord,
  // sorted by countdown target so same-day lives order by showtime.
  // Returns nil when every record is in the past (widget shows empty state).
  static func nextUpcomingRecord(from records: [CD_ChekiRecord], now: Date = Date()) -> CD_ChekiRecord? {
    let today = jstCalendar.startOfDay(for: now)
    return records
      .compactMap { record -> (record: CD_ChekiRecord, date: Date, countdownTarget: Date)? in
        guard let date = DateFormatting.date(from: record.date), date >= today else { return nil }
        return (record, date, instant(for: record) ?? date)
      }
      .min(by: { $0.countdownTarget < $1.countdownTarget })?
      .record
  }

  static func isPast(_ record: CD_ChekiRecord, now: Date = Date()) -> Bool {
    guard let instant = instant(for: record) else { return false }
    return instant.timeIntervalSince(now) <= 0
  }

  /// Mirrors `NextLiveCountdown`'s exact text format: `"D : HH : MM : SS"`
  /// (days unpadded, everything else zero-padded to 2 digits) or, once the
  /// target has passed, the literal lowercase message `"see you next live
  /// !!"` with `isMessage: true` (drives a smaller font at the call site).
  static func countdownText(for record: CD_ChekiRecord, now: Date = Date()) -> (text: String, isMessage: Bool) {
    guard let target = instant(for: record) else {
      return ("see you next live !!", true)
    }
    let diff = target.timeIntervalSince(now)
    guard diff > 0 else {
      return ("see you next live !!", true)
    }
    let totalSeconds = Int(diff.rounded(.down))
    let days = totalSeconds / 86400
    let hours = (totalSeconds % 86400) / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    let text = "\(days) : \(String(format: "%02d", hours)) : \(String(format: "%02d", minutes)) : \(String(format: "%02d", seconds))"
    return (text, false)
  }
}
