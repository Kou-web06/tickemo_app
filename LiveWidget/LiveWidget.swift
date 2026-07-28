//
//  LiveWidget.swift
//  LiveWidget
//
//  Created by Kotaro Miyauchi on 2026/04/07.
//

import WidgetKit
import SwiftUI

// lib/widgetLiveData.ts の WidgetLiveData と対応
struct ArtistInfo: Codable {
    let id: String
    let name: String
    let iconUri: String
}

struct WidgetLiveData: Codable {
    let jacketUri: String
    let liveTitle: String
    let liveDate: String
    let artists: [ArtistInfo]
}

// "2026/05/01" → Date
private func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    for format in ["yyyy/MM/dd", "yyyy-MM-dd"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: string) { return date }
    }
    return nil
}

// 今日の開始から liveDate の開始までの日数差
private func daysUntil(_ dateString: String) -> Int? {
    guard let target = parseDate(dateString) else { return nil }
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let targetDay = cal.startOfDay(for: target)
    return cal.dateComponents([.day], from: today, to: targetDay).day
}

// 翌日の深夜0時
private func nextMidnight() -> Date {
    let cal = Calendar.current
    let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
    return cal.startOfDay(for: tomorrow)
}

struct Provider: TimelineProvider {
    static let appGroup = "group.com.anonymous.Tickemo.widget"
    static let dataKey = "liveWidgetData"

    func loadData() -> WidgetLiveData? {
        guard
            let defaults = UserDefaults(suiteName: Self.appGroup),
            let json = defaults.string(forKey: Self.dataKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(WidgetLiveData.self, from: data)
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), liveData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(SimpleEntry(date: Date(), liveData: loadData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date(), liveData: loadData())
        // カウントダウンは日単位なので深夜0時に更新
        let timeline = Timeline(entries: [entry], policy: .after(nextMidnight()))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let liveData: WidgetLiveData?
}

// MARK: - Small Widget View
struct SmallWidgetView: View {
    let live: WidgetLiveData

    var body: some View {
        let days = daysUntil(live.liveDate)
        VStack(spacing: 2) {
            Spacer()
            countdownLabel(days: days)
            Spacer()
            Text(live.liveTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            if let artist = live.artists.first {
                Text(artist.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    @ViewBuilder
    private func countdownLabel(days: Int?) -> some View {
        if let days {
            if days > 0 {
                VStack(spacing: 0) {
                    Text("あと")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(days)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("日")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if days == 0 {
                Text("TODAY")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.pink)
            } else {
                Text("終了")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("--日")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium Widget View
struct MediumWidgetView: View {
    let live: WidgetLiveData

    var body: some View {
        let days = daysUntil(live.liveDate)
        HStack(spacing: 12) {
            // 左: カウントダウン
            VStack(spacing: 2) {
                if let days {
                    if days > 0 {
                        Text("あと")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(days)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("日")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else if days == 0 {
                        Text("TODAY")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.pink)
                    } else {
                        Text("終了")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80)

            Divider()

            // 右: ライブ情報
            VStack(alignment: .leading, spacing: 4) {
                Text(live.liveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(live.liveDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let artist = live.artists.first {
                    Text(artist.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entry View (サイズ振り分け)
struct LiveWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        if let live = entry.liveData {
            switch family {
            case .systemSmall:
                SmallWidgetView(live: live)
            default:
                MediumWidgetView(live: live)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                Text("次のライブを登録しよう")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

struct LiveWidget: Widget {
    let kind: String = "LiveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                LiveWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LiveWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("次のライブ")
        .description("次に参加するライブまでのカウントダウンを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    LiveWidget()
} timeline: {
    SimpleEntry(date: .now, liveData: WidgetLiveData(
        jacketUri: "",
        liveTitle: "サンプルライブ 2026",
        liveDate: "2026/12/31",
        artists: [ArtistInfo(id: "1", name: "Artist A", iconUri: "")]
    ))
    SimpleEntry(date: .now, liveData: nil)
}

#Preview(as: .systemMedium) {
    LiveWidget()
} timeline: {
    SimpleEntry(date: .now, liveData: WidgetLiveData(
        jacketUri: "",
        liveTitle: "サンプルライブ 2026",
        liveDate: "2026/12/31",
        artists: [ArtistInfo(id: "1", name: "Artist A", iconUri: "")]
    ))
    SimpleEntry(date: .now, liveData: nil)
}
