import Foundation

/// Falls back to the RN app's iCloud Documents (ubiquity container) sync
/// files when local AsyncStorage data is absent or empty (e.g. after a
/// reinstall). Mirrors `hooks/useCloudSync.ts`'s `/tickemo_data.json` (the
/// only variant actually wired up) and, defensively, the dead-code
/// `/tickemo_kvs.json` variant.
struct ICloudFallbackLoader {
  static let containerIdentifier = PersistenceController.cloudKitContainerIdentifier

  static let candidateFilenames = ["tickemo_data.json", "tickemo_kvs.json"]

  func loadRawStoreJSON() async -> String? {
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
      return nil
    }
    for filename in Self.candidateFilenames {
      if let json = await readDownloadedFile(at: containerURL.appendingPathComponent(filename)) {
        return json
      }
    }
    return nil
  }

  /// Whether a sync file is *listed* in the ubiquity container, without
  /// triggering or waiting on a download. Used as a fast pre-check so a
  /// brand new user isn't held behind migration UI; `loadRawStoreJSON()`
  /// remains the authoritative read.
  func hasCandidateFile() -> Bool {
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
      return false
    }
    return Self.candidateFilenames.contains {
      FileManager.default.fileExists(atPath: containerURL.appendingPathComponent($0).path)
    }
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
