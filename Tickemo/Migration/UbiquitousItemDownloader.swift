import Foundation

/// Shared polling helper: iCloud Documents files listed in a ubiquity
/// container aren't necessarily materialized locally yet, so callers must
/// trigger a download and wait before reading. Used by both
/// `ICloudFallbackLoader` (JSON sync files) and `ImageMigrator` (image files).
enum UbiquitousItemDownloader {
  static func waitUntilDownloaded(_ url: URL, timeout: TimeInterval = 30) async {
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
      if status == .current {
        return
      }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
  }
}
