import Foundation

/// Ports screens/SettingsScreen.tsx's `formatJoinedAt` — a relative-time
/// string ("Xm/Xh/Xd ago", falling back to an absolute "YYYY/MM/DD" past
/// 30 days). Parses via `DateFormatting.isoDate(from:)` (same
/// fractional-seconds ISO8601 format `CD_UserProfile.joinedAt` is stored
/// in). Takes `now` as a parameter for testability, matching this
/// project's existing DI-friendly pure-function convention (e.g.
/// `StatisticsData.attendedRecords(_:now:)`).
enum JoinedDateFormatting {
  static func relativeString(from isoString: String?, now: Date = Date()) -> String {
    guard let isoString, !isoString.isEmpty else { return "-" }
    guard let joinedDate = DateFormatting.isoDate(from: isoString) else { return isoString }

    let diffMinutes = Int((now.timeIntervalSince(joinedDate) / 60).rounded(.down))
    if diffMinutes < 60 {
      return "\(max(diffMinutes, 1))m ago"
    }
    let diffHours = diffMinutes / 60
    if diffHours < 24 {
      return "\(diffHours)h ago"
    }
    let diffDays = diffHours / 24
    if diffDays < 30 {
      return "\(diffDays)d ago"
    }

    // Unlike CD_ChekiRecord.date/startTime/endTime (deliberately UTC-anchored
    // wall-clock strings, see DateFormatting.swift), joinedAt is a real ISO
    // instant, and RN's fallback formatting here uses JS Date's local-time
    // getters (getFullYear/getMonth/getDate) — i.e. "what day was it in the
    // user's own timezone," which is the semantically correct question for
    // a join date. Calendar.current (device-local) is intentional here, not
    // an oversight of the UTC convention used elsewhere in this codebase.
    let components = Calendar.current.dateComponents([.year, .month, .day], from: joinedDate)
    let year = components.year ?? 0
    let month = String(format: "%02d", components.month ?? 0)
    let day = String(format: "%02d", components.day ?? 0)
    return "\(year)/\(month)/\(day)"
  }
}
