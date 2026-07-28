import CoreData

struct PersistenceController {
  static let shared = PersistenceController()

  static let cloudKitContainerIdentifier = "iCloud.com.anonymous.Tickemo"

  let container: NSPersistentCloudKitContainer

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

    container.loadPersistentStores { _, error in
      if let error {
        fatalError("Failed to load Core Data store: \(error)")
      }
    }

    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
  }
}
