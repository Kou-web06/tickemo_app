import Foundation

enum CalendarEventType {
  case past
  case future
}

struct CalendarDayEvent {
  let type: CalendarEventType
  let coverImageData: Data?
}

/// Ports CalendarScreen.tsx's `eventsByDate`/`recordsByDate` derivation.
/// Keys are the records' own `.date` strings used as-is — no round-trip
/// through `Date` for the key itself, since the string is already the
/// canonical identity for "which day this record belongs to".
enum CalendarEvents {
  /// `today` is an explicit parameter (not computed internally via
  /// `Date()`) so this stays a pure, unit-testable function of its inputs.
  static func eventsByDate(records: [CD_ChekiRecord], today: Date) -> [String: CalendarDayEvent] {
    var map: [String: CalendarDayEvent] = [:]
    for record in records {
      guard let dateString = record.date, let date = DateFormatting.date(from: dateString) else { continue }
      let type: CalendarEventType = date < today ? .past : .future
      if let existing = map[dateString] {
        // First record for a date wins the type (every record sharing a
        // date key computes the same type anyway, since it's derived from
        // that date alone) — only backfill a missing cover image.
        if existing.coverImageData == nil, let cover = record.coverImageData {
          map[dateString] = CalendarDayEvent(type: existing.type, coverImageData: cover)
        }
      } else {
        map[dateString] = CalendarDayEvent(type: type, coverImageData: record.coverImageData)
      }
    }
    return map
  }

  static func recordsByDate(records: [CD_ChekiRecord]) -> [String: [CD_ChekiRecord]] {
    var map: [String: [CD_ChekiRecord]] = [:]
    for record in records {
      guard let dateString = record.date else { continue }
      map[dateString, default: []].append(record)
    }
    return map
  }
}
