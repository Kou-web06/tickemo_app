import WidgetKit

enum WidgetReloaderService {
  static func reloadTimelines() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}
