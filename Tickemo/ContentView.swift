import SwiftUI

private let accentPurple = Color(red: 0.604, green: 0.486, blue: 0.973)

struct ContentView: View {
  @State private var selectedTab = 0

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        RecordListView()
      }
      .tag(0)
      .tabItem {
        Label("Home", image: selectedTab == 0 ? "Home Active" : "Home")
      }

      CalendarView()
        .tag(1)
        .tabItem {
          Label("Calendar", image: selectedTab == 1 ? "Calendar Active" : "Calendar")
        }

      StatisticsView()
        .tag(2)
        .tabItem {
          Label("Report", image: selectedTab == 2 ? "Chart Active" : "Chart")
        }

      SettingsView()
        .tag(3)
        .tabItem {
          Label("Setting", image: selectedTab == 3 ? "Setting Active" : "Setting")
        }
    }
    .tint(accentPurple)
  }
}

#Preview {
  ContentView()
}
