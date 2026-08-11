import Foundation

/// Writes an untouched copy of the legacy payload to the app sandbox before
/// the importer parses or writes anything.
///
/// The importer never deletes the RN app's AsyncStorage files or the
/// ubiquity container's `tickemo_data.json`, so in principle the originals
/// are always still there. This exists for the cases where that isn't true
/// in practice: the AsyncStorage files are inside the same sandbox the user
/// can clear from Settings, and the ubiquity copy can be evicted or
/// overwritten by a device still running the RN build. A local snapshot
/// costs a few hundred KB and turns "the import produced something wrong"
/// from unrecoverable into a support question.
///
/// Snapshots are kept, not rotated away — there is at most one per import
/// attempt and the whole point is that they outlive the thing that failed.
struct LegacyDataBackup {
  static let directoryName = "LegacyMigrationBackup"

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  var directoryURL: URL? {
    guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    return support.appendingPathComponent(Self.directoryName, isDirectory: true)
  }

  /// Returns the URL written, or nil if no directory was reachable. Failure
  /// is deliberately non-fatal: refusing to migrate because a *backup*
  /// couldn't be written would strand the user's data in the old format for
  /// no benefit.
  @discardableResult
  func store(rawJSON: String, source: String, now: Date = Date()) -> URL? {
    guard let directoryURL else { return nil }

    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
      return nil
    }

    let stamp = Self.timestampFormatter.string(from: now)
    let slug = source
      .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let fileURL = directoryURL.appendingPathComponent("legacy-\(stamp)-\(slug).json")

    do {
      try rawJSON.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      return nil
    }

    // The snapshot is a recovery artifact, not user content: keep it out of
    // iCloud backups so it can't inflate a user's backup size, and mark it
    // as ineligible for purge-on-low-storage would be wrong here (we want
    // it to survive), so only the backup exclusion is set.
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableURL = fileURL
    try? mutableURL.setResourceValues(resourceValues)

    return fileURL
  }

  func existingBackups() -> [URL] {
    guard let directoryURL,
          let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
          )
    else { return [] }
    return contents
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
  }

  /// Fixed to POSIX/UTC so filenames sort chronologically regardless of the
  /// device's locale or calendar (a Japanese-locale device otherwise
  /// resolves `yyyy` against the Japanese era).
  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}
