import CloudKit
import CoreData
import os

struct PersistenceController {
  static let shared = PersistenceController()

  static let cloudKitContainerIdentifier = "iCloud.com.anonymous.Tickemo"

  private static let logger = Logger(subsystem: "com.anonymous.Tickemo", category: "Persistence")

  let container: NSPersistentCloudKitContainer

  /// False when the store had to be opened without CloudKit because
  /// attaching it failed. The app still works fully; it just isn't syncing.
  private(set) var isCloudKitEnabled: Bool

  /// Set when a store file that wouldn't open was moved aside. Surfaced in
  /// Settings so the situation isn't invisible.
  private(set) var quarantinedStoreURL: URL?

  init(inMemory: Bool = false) {
    StringArrayTransformer.register()

    container = NSPersistentCloudKitContainer(name: "Tickemo")

    guard let description = container.persistentStoreDescriptions.first else {
      fatalError("No persistent store description found for Tickemo model")
    }

    if inMemory {
      description.url = URL(fileURLWithPath: "/dev/null")
    } else {
      description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        containerIdentifier: Self.cloudKitContainerIdentifier
      )
    }

    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

    var loadError = Self.load(container)
    isCloudKitEnabled = !inMemory && loadError == nil
    quarantinedStoreURL = nil

    // A CloudKit misconfiguration — an entitlement pointing at the wrong
    // container, a schema that was never deployed to Production, an account
    // in a bad state — must not cost the user access to their own tickets.
    // Falling back to a local-only store keeps every record readable and
    // editable; sync resumes on a later launch once the cause is fixed.
    if loadError != nil, !inMemory {
      Self.logger.error("Store failed to load with CloudKit attached: \(String(describing: loadError))")
      description.cloudKitContainerOptions = nil
      loadError = Self.load(container)
      if loadError == nil {
        Self.logger.warning("Opened Tickemo store without CloudKit sync")
      }
    }

    // Still failing means the store file itself is unreadable (corruption,
    // or a model it doesn't match). Move it aside rather than delete it —
    // the user's data may be recoverable from it, and CloudKit will
    // repopulate a fresh store on this device anyway.
    if loadError != nil, !inMemory, let storeURL = description.url {
      quarantinedStoreURL = Self.quarantine(storeURL)
      if quarantinedStoreURL != nil {
        loadError = Self.load(container)
        if loadError == nil {
          Self.logger.warning("Recovered by quarantining the unreadable store at \(storeURL.path)")
        }
      }
    }

    if let loadError {
      fatalError("Failed to load Core Data store: \(loadError)")
    }

    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
  }

  /// Development-only. `NSPersistentCloudKitContainer` creates record types
  /// lazily in the **Development** CloudKit environment as it first exports
  /// each entity, and never in Production — Production schemas are only
  /// changed by an explicit deploy from the CloudKit console. Calling this
  /// pushes the whole model up front so nothing is missing from the
  /// Development schema at deploy time.
  ///
  /// See `docs/cloudkit-schema-deployment.md` for the full sequence; in
  /// particular this only reaches Development when the build's
  /// `com.apple.developer.icloud-container-environment` entitlement says
  /// `Development`.
  /// `dryRun` validates the managed object model against CloudKit's rules
  /// without any network traffic. Run it first when the real thing fails:
  /// if the dry run passes, the model is fine and the problem is the
  /// account, the entitlement or the network — which is a completely
  /// different thing to go fix.
  func initializeCloudKitSchema(dryRun: Bool = false) async throws {
    let container = container
    let options: NSPersistentCloudKitContainerSchemaInitializationOptions = dryRun ? [.dryRun] : []

    // `initializeCloudKitSchema` blocks its calling thread for the whole
    // upload, and internally waits on CloudKit operations with a 30s
    // budget. Calling it on the main thread starves whatever it's waiting
    // for and turns a slow network into a guaranteed timeout, so it has to
    // run on a background thread.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try container.initializeCloudKitSchema(options: options)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// The iCloud account state this container would actually sync against.
  /// A `.noAccount`/`.restricted` device explains a schema timeout on its
  /// own, without any of the schema itself being wrong.
  func cloudKitAccountStatus() async -> String {
    do {
      let status = try await CKContainer(identifier: Self.cloudKitContainerIdentifier).accountStatus()
      return CloudKitInspector.describe(status)
    } catch {
      return "error: \(error.localizedDescription)"
    }
  }

  private static func load(_ container: NSPersistentCloudKitContainer) -> Error? {
    var caught: Error?
    container.loadPersistentStores { _, error in
      caught = error
    }
    return caught
  }

  /// Renames the store (and its `-wal`/`-shm` siblings) out of the way,
  /// returning the new location. Deliberately never deletes.
  private static func quarantine(_ storeURL: URL) -> URL? {
    let fileManager = FileManager.default
    let suffix = "quarantined-\(Int(Date().timeIntervalSince1970))"
    let destination = storeURL.deletingLastPathComponent()
      .appendingPathComponent("\(storeURL.lastPathComponent).\(suffix)")

    do {
      try fileManager.moveItem(at: storeURL, to: destination)
    } catch {
      logger.error("Could not quarantine unreadable store: \(error.localizedDescription)")
      return nil
    }

    for sidecar in ["-wal", "-shm"] {
      let sidecarURL = URL(fileURLWithPath: storeURL.path + sidecar)
      guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
      try? fileManager.moveItem(
        at: sidecarURL,
        to: URL(fileURLWithPath: destination.path + sidecar)
      )
    }

    return destination
  }
}
