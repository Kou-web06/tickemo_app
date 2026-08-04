import WidgetKit
import Foundation

enum WidgetReloaderService {
  private static let appGroup = "group.com.anonymous.Tickemo.widget"
  private static let dataKey = "liveWidgetData"
  private static let coverImageFilename = "widget_cover.jpg"

  /// 次のライブデータを App Group に書き込んでからウィジェットを更新する。
  /// `records` は全件を渡す（選択は内部で行う）。
  static func sync(records: [CD_ChekiRecord]) {
    writeWidgetData(for: NextLiveCardData.nextLiveRecord(from: records))
    WidgetCenter.shared.reloadAllTimelines()
  }

  static func reloadTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
  }

  // MARK: - Private

  private static func writeWidgetData(for record: CD_ChekiRecord?) {
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }

    guard let record else {
      defaults.removeObject(forKey: dataKey)
      clearCoverImage()
      return
    }

    let jacketPath = saveCoverImage(record.coverImageData)
    let artistName = ArtistGrouping.names(for: record).first ?? ""

    // liveTime: endTime（開演）優先、なければ startTime（開場）、両方なければ省略
    let liveTime: String?
    if let t = record.endTime, !t.isEmpty {
      liveTime = t
    } else if let t = record.startTime, !t.isEmpty {
      liveTime = t
    } else {
      liveTime = nil
    }

    var jsonObject: [String: Any] = [
      "jacketUri": jacketPath,
      "liveTitle": record.liveName ?? "",
      "liveDate": record.date ?? "",
      "artists": [["id": record.id?.uuidString ?? "", "name": artistName, "iconUri": ""]],
    ]
    if let liveTime {
      jsonObject["liveTime"] = liveTime
    }

    guard
      let data = try? JSONSerialization.data(withJSONObject: jsonObject),
      let json = String(data: data, encoding: .utf8)
    else { return }
    defaults.set(json, forKey: dataKey)
  }

  /// カバー画像を App Group コンテナに保存し、ファイルパスを返す。
  /// 画像がなければ空文字を返す。
  private static func saveCoverImage(_ imageData: Data?) -> String {
    guard
      let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
      let data = imageData
    else {
      clearCoverImage()
      return ""
    }
    let fileURL = containerURL.appendingPathComponent(coverImageFilename)
    try? data.write(to: fileURL)
    return fileURL.path
  }

  private static func clearCoverImage() {
    guard
      let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    else { return }
    let fileURL = containerURL.appendingPathComponent(coverImageFilename)
    try? FileManager.default.removeItem(at: fileURL)
  }
}
