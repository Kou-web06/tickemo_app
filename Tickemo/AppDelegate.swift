import SwiftUI

@main
struct TickemoApp: App {
  init() {
    Task { await PurchasesService.shared.configure() }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
  }
}
