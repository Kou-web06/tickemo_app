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
    let today = DateFormatting.utcCalendar.startOfDay(for: now)
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

  /// The full date+startTime instant, defaulting startTime to 18:00 when
  /// absent or unparseable — CollectionScreen.tsx's own bespoke default for
  /// this specific card, distinct from StatisticsData.recordInstant's
  /// midnight default used elsewhere for a different feature.
  static func instant(for record: CD_ChekiRecord) -> Date? {
    guard let day = DateFormatting.date(from: record.date) else { return nil }
    let startTime = (record.startTime?.isEmpty == false) ? record.startTime! : "18:00"
    let parts = startTime.split(separator: ":").compactMap { Int($0) }
    guard let hour = parts.first else { return day }
    let minute = parts.count > 1 ? parts[1] : 0
    return DateFormatting.utcCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
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
