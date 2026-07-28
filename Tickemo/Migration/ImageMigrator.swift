import Foundation

/// Resolves the `Tickemo/...`-relative image paths found in legacy
/// `ChekiRecord.imageUrls`/`UserProfile.avatarUri` values into raw `Data`,
/// mirroring `lib/icloudImageSync.ts`'s path conventions. Local app-sandbox
/// files are tried first (the common case — Phase 0's TestFlight validation
/// already confirmed the Documents directory survives an RN→Swift in-place
/// update), falling back to the base64-encoded iCloud copy only when the
/// local file is missing (reinstall case).
struct ImageMigrator {
  static let relativePathPrefix = "Tickemo/"

  func isLegacyRelativePath(_ path: String) -> Bool {
    path.hasPrefix(Self.relativePathPrefix)
      && !path.hasPrefix("file://")
      && !path.hasPrefix("http://")
      && !path.hasPrefix("https://")
  }

  func resolveImageData(forRelativePath relativePath: String) async -> Data? {
    guard isLegacyRelativePath(relativePath) else { return nil }

    if let localData = readLocalSandboxFile(relativePath: relativePath) {
      return localData
    }
    return await readICloudFile(relativePath: relativePath)
  }

  private func readLocalSandboxFile(relativePath: String) -> Data? {
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    return try? Data(contentsOf: documentsURL.appendingPathComponent(relativePath))
  }

  private func readICloudFile(relativePath: String) async -> Data? {
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: ICloudFallbackLoader.containerIdentifier) else {
      return nil
    }
    let fileURL = containerURL.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

    await UbiquitousItemDownloader.waitUntilDownloaded(fileURL)
    guard let base64String = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
    return Data(base64Encoded: base64String)
  }
}
