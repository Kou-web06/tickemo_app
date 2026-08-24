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
  @State private var showSplash = true

  init() {
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
        // スプラッシュ表示中に並列で初回読み込みを完了させる。
        // PurchasesService.configure() の完了（Plus 判定含む）と migration の
        // 完了を待ってからスプラッシュを消す。最低 0.7 秒は表示して
        // ランチスクリーンからの繋ぎが自然に見えるようにする。
        // 初期化タスク: スキップ有無に関わらず必ず完走させる
        .task {
          async let purchases: Void = PurchasesService.shared.configure()
          async let migration: Void = MigrationCoordinator.shared.runIfNeeded()
          _ = await (purchases, migration)
          WidgetReloaderService.startObserving()
          LiveNotificationService.requestAuthorizationIfNeeded()
          LiveNotificationService.startObserving()
        }
        // スプラッシュ表示タスク: 3 秒後に自動で閉じる（スキップ可）
        .task {
          try? await Task.sleep(nanoseconds: 3_000_000_000)
          withAnimation(.easeOut(duration: 0.4)) {
            showSplash = false
          }
        }
        .overlay {
          if showSplash {
            SplashView()
              .transition(.opacity)
              .ignoresSafeArea()
          }
        }
        .animation(.easeOut(duration: 0.4), value: showSplash)
    }
  }
}
