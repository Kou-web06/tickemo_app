import SwiftUI

@main
struct TickemoApp: App {
  init() {
    Task { await PurchasesService.shared.configure() }
    // 起動直後から CloudKit の eventChangedNotification を受け取るために
    // 早期にシングルトンを生成する。遅延初期化のまま放置すると、設定画面を
    // 開くまでオブザーバーが登録されず、起動時の import/export イベントを
    // 取りこぼして「未同期」のまま表示され続ける。
    _ = CloudSyncStatusService.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .preferredColorScheme(ThemePreferenceService.shared.colorScheme)
        // Runs before anything can be shown or edited. `runIfNeeded` is
        // idempotent and returns immediately once migration has happened,
        // so attaching it here (rather than to a single screen) costs
        // nothing on subsequent launches.
        .task {
          await MigrationCoordinator.shared.runIfNeeded()
          // After migration, not before: the widget should reflect the
          // imported records rather than the empty store they replaced.
          WidgetReloaderService.startObserving()
        }
    }
  }
}
