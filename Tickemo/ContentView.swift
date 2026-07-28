import SwiftUI

struct ContentView: View {
  private let appleMusicService = AppleMusicService()
  @State private var isAuthorized = false

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
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
