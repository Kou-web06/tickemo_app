import Foundation

/// Falls back to the RN app's iCloud Documents (ubiquity container) sync
/// files when local AsyncStorage data is absent or empty (e.g. after a
/// reinstall). Mirrors `hooks/useCloudSync.ts`'s `/tickemo_data.json` (the
/// only variant actually wired up) and, defensively, the dead-code
/// `/tickemo_kvs.json` variant.
struct ICloudFallbackLoader {
  static let containerIdentifier = PersistenceController.cloudKitContainerIdentifier

  func loadRawStoreJSON() async -> String? {
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
      return nil
    }
    if let dataJSON = await readDownloadedFile(at: containerURL.appendingPathComponent("tickemo_data.json")) {
      return dataJSON
    }
    return await readDownloadedFile(at: containerURL.appendingPathComponent("tickemo_kvs.json"))
  }

  /// Ensures an iCloud file is actually materialized locally before reading
  /// it (files listed in the ubiquity container aren't necessarily
  /// downloaded yet), mirroring what `CloudKitUtils` handles on the JS side.
  private func readDownloadedFile(at url: URL) async -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    await UbiquitousItemDownloader.waitUntilDownloaded(url)
    return try? String(contentsOf: url, encoding: .utf8)
  }
}
