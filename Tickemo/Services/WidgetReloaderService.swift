import CoreData
import WidgetKit
import Foundation
import os

enum WidgetReloaderService {
  private static let appGroup = "group.com.anonymous.Tickemo.widget"
  private static let dataKey = "liveWidgetData"
  private static let coverImageFilename = "widget_cover.jpg"
  private static let log = Logger(subsystem: "com.anonymous.Tickemo", category: "WidgetSync")

  /// 次のライブデータを App Group に書き込んでからウィジェットを更新する。
  /// `records` は全件を渡す（選択は内部で行う）。
  static func sync(records: [CD_ChekiRecord]) {
    let record = NextLiveCardData.nextUpcomingRecord(from: records)
    log.info("sync: \(records.count) records → selected: \(record?.liveName ?? "nil", privacy: .public)")
    writeWidgetData(for: record)
    // WidgetCenter は必ずメインスレッドで呼ぶ。syncFromStore のように
    // バックグラウンドキューから呼ばれる場合でも安全に動作させる。
    DispatchQueue.main.async {
      WidgetCenter.shared.reloadAllTimelines()
      log.info("sync: reloadAllTimelines dispatched")
    }
  }

  static func reloadTimelines() {
    DispatchQueue.main.async {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  // MARK: - Store-driven sync

  /// Fetches the records itself and syncs.
  ///
  /// This exists because driving the widget from `RecordListView`'s view
  /// lifecycle alone silently misses the cases that matter most: a record
  /// arriving from CloudKit, the legacy migration writing on a background
  /// context, or an edit made while the Home tab has never been
  /// constructed. In all of those the widget keeps showing stale data (or
  /// the "次のライブを登録しよう" empty state) until the user happens to
  /// visit Home, which looks exactly like the widget being broken.
  static func syncFromStore(
    container: NSPersistentContainer = PersistenceController.shared.container
  ) {
    log.info("syncFromStore: starting fetch")
    let context = container.newBackgroundContext()
    context.perform {
      let request = CD_ChekiRecord.fetchRequest()
      request.relationshipKeyPathsForPrefetching = ["images"]
      do {
        let records = try context.fetch(request)
        log.info("syncFromStore: fetched \(records.count) records")
        sync(records: records)
      } catch {
        log.error("syncFromStore: fetch failed — \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Starts watching the store so the widget tracks it without any view
  /// being on screen. Idempotent; safe to call on every launch.
  @MainActor
  static func startObserving(
    container: NSPersistentContainer = PersistenceController.shared.container
  ) {
    guard observers.isEmpty else { return }

    // `object: nil` on purpose — background contexts (migration import,
    // duplicate sweep) save too, and those are precisely the ones the
    // view-scoped observer couldn't see.
    observers.append(
      NotificationCenter.default.addObserver(
        forName: .NSManagedObjectContextDidSave,
        object: nil,
        queue: .main
      ) { [container] _ in
        MainActor.assumeIsolated { scheduleSync(container: container) }
      }
    )

    // Fires when CloudKit imports another device's changes.
    observers.append(
      NotificationCenter.default.addObserver(
        forName: .NSPersistentStoreRemoteChange,
        object: container.persistentStoreCoordinator,
        queue: .main
      ) { [container] _ in
        MainActor.assumeIsolated { scheduleSync(container: container) }
      }
    )

    syncFromStore(container: container)
  }

  private static var observers: [NSObjectProtocol] = []
  private static var pendingSync: DispatchWorkItem?

  /// Coalesces the burst of saves a batched migration import produces into
  /// one write.
  @MainActor
  private static func scheduleSync(container: NSPersistentContainer) {
    pendingSync?.cancel()
    let work = DispatchWorkItem { syncFromStore(container: container) }
    pendingSync = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  // MARK: - Private

  private static func writeWidgetData(for record: CD_ChekiRecord?) {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      log.error("writeWidgetData: UserDefaults(suiteName:) returned nil — App Group not configured?")
      return
    }

    guard let record else {
      log.info("writeWidgetData: no upcoming live — clearing widget data")
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
    else {
      log.error("writeWidgetData: JSON serialization failed")
      return
    }
    defaults.set(json, forKey: dataKey)
    defaults.synchronize()
    log.info("writeWidgetData: wrote data for '\(record.liveName ?? "", privacy: .public)' on \(record.date ?? "", privacy: .public)")
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
