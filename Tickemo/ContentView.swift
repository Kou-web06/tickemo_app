import SwiftUI

struct ContentView: View {
  private let appleMusicService = AppleMusicService()
  @State private var isAuthorized = false

  #if DEBUG
  @State private var migrationSummaryText: String?
  @State private var isMigrating = false
  #endif

  var body: some View {
    VStack(spacing: 16) {
      Text("Tickemo (Swift Shell)")
        .font(.title2)
      Text(isAuthorized ? "Apple Music: Authorized" : "Apple Music: Not authorized")
        .foregroundStyle(.secondary)
      Button("Test Apple Music Auth") {
        Task {
          isAuthorized = await appleMusicService.authorize()
        }
      }

      #if DEBUG
      Divider()
      Button("Run Data Migration (Debug)") {
        runDebugMigration()
      }
      .disabled(isMigrating)

      if isMigrating {
        ProgressView()
      }

      if let migrationSummaryText {
        ScrollView {
          Text(migrationSummaryText)
            .font(.system(.footnote, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(.horizontal)
      }
      #endif
    }
    .padding()
  }

  #if DEBUG
  private func runDebugMigration() {
    isMigrating = true
    migrationSummaryText = nil
    Task {
      let importer = DataMigrationImporter()
      importer.resetMigrationFlag()
      let summary = await importer.run()
      migrationSummaryText = """
      source: \(summary.source)
      records: \(summary.recordCount)
      setlist items: \(summary.setlistItemCount)
      images: \(summary.imageCount)
      profile imported: \(summary.profileImported)
      error: \(summary.error ?? "none")
      """
      isMigrating = false
    }
  }
  #endif
}

#Preview {
  ContentView()
}
