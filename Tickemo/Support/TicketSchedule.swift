import CoreData
import Foundation

/// チケットの予定（座席発表・チケット申込・支払い期限）の純粋ロジック。
///
/// 「座席番号がわかる日、チケット申込の日時、支払い期限をカレンダーや
/// 通知で知りたい」というフィードバックを受けて追加した Plus 機能。
/// 1公演につき各1つまで、`CD_ChekiRecord` の任意属性
/// （`seatAnnounceAt` / `ticketApplyAt` / `paymentDueAt`）に
/// `DateFormatting.dateTimeFormat`（"yyyy-MM-dd HH:mm"）で保存する。
/// 値は `date` / `startTime` と同じく日本時間の壁時計として扱い、通知の
/// 発火時刻に変換するときだけ Asia/Tokyo で解釈する
/// （`NextLiveCardData.instant` と同じ考え方）。
enum TicketScheduleKind: String, CaseIterable, Identifiable {
  case seatAnnounce
  case ticketApply
  case paymentDue

  var id: String { rawValue }

  var label: String {
    switch self {
    case .seatAnnounce: return "座席発表"
    case .ticketApply: return "チケット申込"
    case .paymentDue: return "支払い期限"
    }
  }
}

struct TicketScheduleEntry: Equatable {
  let kind: TicketScheduleKind
  /// "yyyy-MM-dd"。カレンダーのキー（`CD_ChekiRecord.date` と同じ形式）
  let dateString: String
  /// "HH:mm"
  let timeString: String
  /// 日本時間として解釈した実際の時刻
  let instant: Date
}

enum TicketSchedule {
  struct Reminder: Equatable {
    let kind: TicketScheduleKind
    /// 同じ予定に複数の通知がある場合（支払い期限）の識別用
    let suffix: String
    let title: String
    let body: String
    let fireDate: Date
  }

  static func rawValue(_ kind: TicketScheduleKind, of record: CD_ChekiRecord) -> String? {
    switch kind {
    case .seatAnnounce: return record.seatAnnounceAt
    case .ticketApply: return record.ticketApplyAt
    case .paymentDue: return record.paymentDueAt
    }
  }

  static func setRawValue(_ value: String?, _ kind: TicketScheduleKind, of record: CD_ChekiRecord) {
    switch kind {
    case .seatAnnounce: record.seatAnnounceAt = value
    case .ticketApply: record.ticketApplyAt = value
    case .paymentDue: record.paymentDueAt = value
    }
  }

  /// 保存値を解釈する。壊れた値は予定なしとして扱う。
  static func entry(_ kind: TicketScheduleKind, raw: String?) -> TicketScheduleEntry? {
    guard let wallClock = DateFormatting.dateTime(from: raw) else { return nil }
    let utc = DateFormatting.utcCalendar
    let components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: wallClock)
    guard let instant = jstCalendar.date(from: components) else { return nil }
    return TicketScheduleEntry(
      kind: kind,
      dateString: DateFormatting.string(from: wallClock),
      timeString: DateFormatting.timeString(from: wallClock),
      instant: instant
    )
  }

  /// その公演に登録された予定を時刻順に返す。
  static func entries(for record: CD_ChekiRecord) -> [TicketScheduleEntry] {
    TicketScheduleKind.allCases
      .compactMap { entry($0, raw: rawValue($0, of: record)) }
      .sorted { $0.instant < $1.instant }
  }

  // MARK: - Calendar

  struct CalendarItem: Identifiable {
    let record: CD_ChekiRecord
    let entry: TicketScheduleEntry

    var id: String { "\(record.objectID.uriRepresentation().absoluteString)#\(entry.kind.rawValue)" }
  }

  /// カレンダー用。予定の日付（"yyyy-MM-dd"）ごとに、時刻順で返す。
  static func itemsByDate(records: [CD_ChekiRecord]) -> [String: [CalendarItem]] {
    var map: [String: [CalendarItem]] = [:]
    for record in records {
      for entry in entries(for: record) {
        map[entry.dateString, default: []].append(CalendarItem(record: record, entry: entry))
      }
    }
    return map.mapValues { items in items.sorted { $0.entry.instant < $1.entry.instant } }
  }

  // MARK: - Notifications

  /// 予定1件ぶんの通知。
  /// - 座席発表: その時刻ちょうど
  /// - チケット申込: 30分前
  /// - 支払い期限: 前日19時と、当日の3時間前
  static func reminders(for entry: TicketScheduleEntry, liveName: String) -> [Reminder] {
    switch entry.kind {
    case .seatAnnounce:
      return [Reminder(
        kind: .seatAnnounce,
        suffix: "",
        title: "座席がわかる時間です🎫",
        body: "\(liveName)の座席発表の時間になりました。チケットを確認してみてね！",
        fireDate: entry.instant
      )]
    case .ticketApply:
      return [Reminder(
        kind: .ticketApply,
        suffix: "",
        title: "まもなくチケット申込！",
        body: "\(liveName)のチケット申込は\(entry.timeString)から。準備はOK？",
        fireDate: entry.instant.addingTimeInterval(-30 * 60)
      )]
    case .paymentDue:
      var result: [Reminder] = []
      if let dayBeforeBase = jstCalendar.date(byAdding: .day, value: -1, to: entry.instant),
         let dayBefore = jstCalendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayBeforeBase) {
        result.append(Reminder(
          kind: .paymentDue,
          suffix: "dayBefore",
          title: "明日はチケット代の支払い期限です💳",
          body: "\(liveName)の支払い期限は明日の\(entry.timeString)まで。お忘れなく！",
          fireDate: dayBefore
        ))
      }
      result.append(Reminder(
        kind: .paymentDue,
        suffix: "threeHours",
        title: "支払い期限まであと3時間！",
        body: "\(liveName)の支払い期限は\(entry.timeString)までです。",
        fireDate: entry.instant.addingTimeInterval(-3 * 60 * 60)
      ))
      return result
    }
  }

  static let jstCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()
}
