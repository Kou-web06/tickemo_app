import SwiftUI

@main
struct TickemoApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
  }
}
