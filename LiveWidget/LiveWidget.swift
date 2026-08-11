import WidgetKit
import SwiftUI
import UIKit
import os

// lib/widgetLiveData.ts の WidgetLiveData と対応
struct ArtistInfo: Codable {
  let id: String
  let name: String
  let iconUri: String
}

struct WidgetLiveData: Codable {
  let jacketUri: String
  let liveTitle: String
  let liveDate: String    // "yyyy-MM-dd"
  let liveTime: String?   // "HH:mm" 開演時刻（nil = 時刻不明）
  let artists: [ArtistInfo]
}

// MARK: - Constants

private let appGroup = "group.com.anonymous.Tickemo.widget"
private let dataKey = "liveWidgetData"
private let coverImageFilename = "widget_cover.jpg"

// MARK: - Helpers

private func appGroupContainerURL() -> URL? {
  FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
}

private func targetDate(from live: WidgetLiveData) -> Date? {
  // ライブ日付・開演時刻はどちらも日本時間（JST, UTC+9）で入力されるため
  // UTC で処理すると9時間ズレる。Asia/Tokyo で統一する。
  let jst = TimeZone(identifier: "Asia/Tokyo")!
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = jst
  // "yyyy.MM.dd" is RN's persisted spelling, which every migrated record
  // still carries — see DateFormatting.date(from:) in the app target.
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = jst
  for fmt in ["yyyy-MM-dd", "yyyy.MM.dd", "yyyy/MM/dd"] {
    formatter.dateFormat = fmt
    if let day = formatter.date(from: live.liveDate) {
      if let timeStr = live.liveTime, !timeStr.isEmpty {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        if let hour = parts.first {
          let minute = parts.count > 1 ? parts[1] : 0
          return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
      }
      // 時刻不明の場合は23:59にしておくことで、ライブ当日の終わりまでカウントダウンを維持する
      return cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    }
  }
  return nil
}

private func daysFromEntryDate(_ entryDate: Date, toTarget target: Date) -> Int {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
  let from = cal.startOfDay(for: entryDate)
  let to = cal.startOfDay(for: target)
  return max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
}

private func nextMidnight(after date: Date = Date()) -> Date {
  let cal = Calendar.current
  return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: date)!)
}

private func formattedDate(_ raw: String) -> String {
  let jst = TimeZone(identifier: "Asia/Tokyo")!
  let parser = DateFormatter()
  parser.locale = Locale(identifier: "en_US_POSIX")
  parser.timeZone = jst
  for fmt in ["yyyy-MM-dd", "yyyy.MM.dd", "yyyy/MM/dd"] {
    parser.dateFormat = fmt
    if let date = parser.date(from: raw) {
      let display = DateFormatter()
      display.locale = Locale(identifier: "ja_JP")
      display.timeZone = jst
      display.dateFormat = "M/d"
      return display.string(from: date)
    }
  }
  return raw
}

// MARK: - Entry

struct SimpleEntry: TimelineEntry {
  let date: Date
  let liveData: WidgetLiveData?
  let coverImage: UIImage?
  let targetDate: Date?
  let daysRemaining: Int?
}

// MARK: - Provider

private let widgetLog = Logger(subsystem: "com.anonymous.Tickemo.LiveWidget", category: "WidgetSync")

struct Provider: TimelineProvider {
  func loadData() -> WidgetLiveData? {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      widgetLog.error("loadData: UserDefaults(suiteName:) returned nil — App Group not accessible")
      return nil
    }
    guard let json = defaults.string(forKey: dataKey) else {
      widgetLog.warning("loadData: key '\(dataKey)' not found in App Group defaults")
      return nil
    }
    guard let data = json.data(using: .utf8) else {
      widgetLog.error("loadData: failed to convert JSON string to Data")
      return nil
    }
    do {
      let result = try JSONDecoder().decode(WidgetLiveData.self, from: data)
      widgetLog.info("loadData: decoded live '\(result.liveTitle, privacy: .public)' on \(result.liveDate, privacy: .public)")
      return result
    } catch {
      widgetLog.error("loadData: JSON decode failed — \(error.localizedDescription, privacy: .public) | raw: \(json, privacy: .public)")
      return nil
    }
  }

  func loadCoverImage() -> UIImage? {
    guard let url = appGroupContainerURL() else { return nil }
    return UIImage(contentsOfFile: url.appendingPathComponent(coverImageFilename).path)
  }

  func makeEntry(at date: Date, liveData: WidgetLiveData?, coverImage: UIImage?) -> SimpleEntry {
    let target = liveData.flatMap { targetDate(from: $0) }
    let days = target.map { daysFromEntryDate(date, toTarget: $0) }
    return SimpleEntry(date: date, liveData: liveData, coverImage: coverImage, targetDate: target, daysRemaining: days)
  }

  func placeholder(in context: Context) -> SimpleEntry {
    SimpleEntry(date: Date(), liveData: nil, coverImage: nil, targetDate: nil, daysRemaining: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
    let live = loadData()
    completion(makeEntry(at: Date(), liveData: live, coverImage: loadCoverImage()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
    widgetLog.info("getTimeline: called")
    let liveData = loadData()
    let coverImage = loadCoverImage()
    let now = Date()
    widgetLog.info("getTimeline: liveData=\(liveData?.liveTitle ?? "nil", privacy: .public)")

    // 今の表示エントリ
    var entries: [SimpleEntry] = [makeEntry(at: now, liveData: liveData, coverImage: coverImage)]

    // 深夜0時ごとのエントリ（「X日」更新）＋24時間前エントリ（タイマー切り替え）
    if let target = liveData.flatMap({ targetDate(from: $0) }), target > now {
      var candidateDates: [Date] = []

      // 24時間前の切り替えポイント
      let switchPoint = target.addingTimeInterval(-86400)
      if switchPoint > now {
        candidateDates.append(switchPoint)
      }

      // ターゲットまでの深夜0時
      var midnight = nextMidnight(after: now)
      while midnight < target {
        candidateDates.append(midnight)
        midnight = nextMidnight(after: midnight)
      }

      candidateDates.sort()
      for date in candidateDates {
        entries.append(makeEntry(at: date, liveData: liveData, coverImage: coverImage))
      }
    }

    let target = liveData.flatMap { targetDate(from: $0) }
    // `.after(past_date)` causes RBSAssertionErrorDomain Code=2 — the system
    // can't acquire a process assertion for a deadline already in the past.
    // If the target has passed, fall back to next midnight so WidgetKit doesn't
    // spin in a tight retry loop.
    let policy: TimelineReloadPolicy
    if let target, target > now {
      policy = .after(target)
    } else {
      policy = .after(nextMidnight())
    }
    widgetLog.info("getTimeline: policy=\(target.map { "after \($0)" } ?? "nextMidnight", privacy: .public)")
    completion(Timeline(entries: entries, policy: policy))
  }
}

// MARK: - Background view (shared between small/medium)

struct WidgetBackgroundView: View {
  let coverImage: UIImage?

  var body: some View {
    ZStack {
      if let coverImage {
        Image(uiImage: coverImage)
          .resizable()
          .scaledToFill()
      } else {
        LinearGradient(
          colors: [Color(red: 0.14, green: 0.07, blue: 0.26), Color(red: 0.06, green: 0.05, blue: 0.14)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      // 下部テキストを読みやすくするグラデーション
      LinearGradient(
        colors: [.black.opacity(0.70), .clear],
        startPoint: .bottom,
        endPoint: .init(x: 0.5, y: 0.32)
      )
    }
  }
}

// MARK: - Countdown subview

private struct CountdownView: View {
  let entryDate: Date
  let targetDate: Date?
  let daysRemaining: Int?
  let smallFont: Bool

  var body: some View {
    Group {
      if let target = targetDate {
        let remaining = target.timeIntervalSince(entryDate)
        if remaining <= 0 {
          // 終演後
          Text("see you\nnext live !!")
            .font(.system(size: smallFont ? 14 : 16, weight: .black))
            .foregroundStyle(Color(red: 1.0, green: 0.87, blue: 0.15))
            .multilineTextAlignment(.leading)
        } else if remaining < 86400 {
          // 24時間以内：時分秒カウントダウン
          Text(target, style: .timer)
            .font(.system(size: smallFont ? 28 : 34, weight: .black, design: .monospaced))
            .foregroundStyle(.white)
            .monospacedDigit()
        } else {
          // 24時間以上：「X日」
          let days = daysRemaining ?? 0
          HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text("\(days)")
              .font(.system(size: smallFont ? 46 : 54, weight: .black, design: .default))
              .foregroundStyle(.white)
            Text("日")
              .font(.system(size: smallFont ? 14 : 16, weight: .bold))
              .foregroundStyle(.white.opacity(0.78))
          }
        }
      } else {
        Text("-- 日")
          .font(.system(size: smallFont ? 42 : 50, weight: .bold, design: .default))
          .foregroundStyle(.white.opacity(0.45))
      }
    }
  }
}

// MARK: - Small Widget content

struct SmallWidgetView: View {
  let entry: SimpleEntry
  let live: WidgetLiveData

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Spacer()
      CountdownView(
        entryDate: entry.date,
        targetDate: entry.targetDate,
        daysRemaining: entry.daysRemaining,
        smallFont: true
      )
      Text(live.liveTitle)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Medium Widget content

struct MediumWidgetView: View {
  let entry: SimpleEntry
  let live: WidgetLiveData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Spacer()
      CountdownView(
        entryDate: entry.date,
        targetDate: entry.targetDate,
        daysRemaining: entry.daysRemaining,
        smallFont: false
      )
      Text(live.liveTitle)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(2)
      HStack(spacing: 8) {
        if let artist = live.artists.first, !artist.name.isEmpty {
          Text(artist.name)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.60))
            .lineLimit(1)
        }
        Spacer()
        Text(formattedDate(live.liveDate))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.white.opacity(0.55))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Entry view

struct LiveWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: SimpleEntry

  var body: some View {
    if let live = entry.liveData {
      switch family {
      case .systemSmall:
        SmallWidgetView(entry: entry, live: live)
      default:
        MediumWidgetView(entry: entry, live: live)
      }
    } else {
      VStack(spacing: 6) {
        Image(systemName: "ticket")
          .font(.title2)
        Text("次のライブを登録しよう")
          .font(.caption)
          .multilineTextAlignment(.center)
      }
      .foregroundStyle(.white.opacity(0.6))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// MARK: - Widget

struct LiveWidget: Widget {
  let kind: String = "LiveWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      if #available(iOS 17.0, *) {
        LiveWidgetEntryView(entry: entry)
          .containerBackground(for: .widget) {
            WidgetBackgroundView(coverImage: entry.coverImage)
          }
      } else {
        ZStack(alignment: .bottomLeading) {
          WidgetBackgroundView(coverImage: entry.coverImage)
          LiveWidgetEntryView(entry: entry)
            .padding(16)
        }
      }
    }
    .configurationDisplayName("次のライブ")
    .description("次に参加するライブまでのカウントダウンを表示します。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
  LiveWidget()
} timeline: {
  SimpleEntry(
    date: .now,
    liveData: WidgetLiveData(
      jacketUri: "", liveTitle: "LIVE TOUR 2026 -FINAL-",
      liveDate: "2026-12-31", liveTime: "18:00",
      artists: [ArtistInfo(id: "1", name: "アーティスト名", iconUri: "")]
    ),
    coverImage: nil,
    targetDate: Calendar.current.date(byAdding: .day, value: 60, to: .now),
    daysRemaining: 60
  )
  SimpleEntry(date: .now, liveData: nil, coverImage: nil, targetDate: nil, daysRemaining: nil)
}

#Preview(as: .systemMedium) {
  LiveWidget()
} timeline: {
  SimpleEntry(
    date: .now,
    liveData: WidgetLiveData(
      jacketUri: "", liveTitle: "LIVE TOUR 2026 -FINAL-",
      liveDate: "2026-12-31", liveTime: "18:00",
      artists: [ArtistInfo(id: "1", name: "アーティスト名", iconUri: "")]
    ),
    coverImage: nil,
    targetDate: Calendar.current.date(byAdding: .day, value: 60, to: .now),
    daysRemaining: 60
  )
  SimpleEntry(date: .now, liveData: nil, coverImage: nil, targetDate: nil, daysRemaining: nil)
}
