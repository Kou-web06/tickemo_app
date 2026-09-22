import SwiftUI
import UIKit
import os

final class TickemoAppDelegate: NSObject, UIApplicationDelegate {
  private static let logger = Logger(subsystem: "com.anonymous.Tickemo", category: "RemoteNotifications")

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // NSPersistentCloudKitContainer が自前で張る CloudKit のサブスクリプション
    // 通知を実際に受け取れるようにするための土台。これが無いと、他デバイス
    // での変更はこのデバイスのアプリを開いた時にしか反映されない
    // （UIBackgroundModes の remote-notification と対で必要）。
    application.registerForRemoteNotifications()
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Self.logger.info("Registered for remote notifications")
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // シミュレータや、プロビジョニングが揃っていないビルドではここに来る。
    // CloudKit のプッシュ経由の即時同期が効いていないことのわかりやすい
    // 手がかりになるので、握りつぶさずログに残す。
    Self.logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // CloudKit のサイレントプッシュはペイロード自体を自分でパースする必要は
    // ない — NSPersistentCloudKitContainer が既に張っているサブスクリプション
    // が、プロセスが起こされたこのタイミングで自律的にインポートを進める。
    // ここでの役目はアプリを一瞬起こして机上に上げることそのもの。
    completionHandler(.newData)
  }

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
