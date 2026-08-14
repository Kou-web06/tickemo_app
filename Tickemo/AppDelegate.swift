import SwiftUI
import UIKit

final class TickemoAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = TickemoSceneDelegate.self
    return configuration
  }
}

/// Only the UIKit scene delegate receives `UIApplicationShortcutItem` taps
/// (cold launch via `willConnectTo`, warm/background via
/// `performActionFor`); SwiftUI's `App` protocol has no equivalent hook, so
/// this forwards both into `ShortcutItemService` for `ContentView` to react to.
final class TickemoSceneDelegate: NSObject, UIWindowSceneDelegate {
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let shortcutItem = connectionOptions.shortcutItem {
      ShortcutItemService.shared.handle(shortcutItem)
    }
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    ShortcutItemService.shared.handle(shortcutItem)
    completionHandler(true)
  }
}

@main
struct TickemoApp: App {
  @UIApplicationDelegateAdaptor(TickemoAppDelegate.self) private var appDelegate

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
          LiveNotificationService.requestAuthorizationIfNeeded()
          LiveNotificationService.startObserving()
        }
    }
  }
}
