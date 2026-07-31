import SwiftUI

/// Bottom tab bar: Home/Calendar/Report/Settings. RN's own FloatingTabBar
/// only has 3 tabs (Home/Calendar/Statistics) plus a separate floating
/// "My Page" button for Settings — this app folds Settings into the tab bar
/// as a 4th tab instead, per explicit direction, using a standard system
/// TabView rather than reproducing RN's custom floating-pill chrome (this
/// migration's established pattern of adapting to native platform
/// conventions rather than copying RN's bespoke UI verbatim).
struct ContentView: View {
  var body: some View {
    TabView {
      NavigationStack {
        RecordListView()
      }
      .tabItem {
        HugeIconTabLabel(icon: HugeIcons.home05, title: "Home")
      }

      CalendarView()
        .tabItem {
          HugeIconTabLabel(icon: HugeIcons.calendar03, title: "Calendar")
        }

      StatisticsView()
        .tabItem {
          HugeIconTabLabel(icon: HugeIcons.gridView, title: "Report")
        }

      SettingsView()
        .tabItem {
          HugeIconTabLabel(icon: HugeIcons.settings03, title: "Settings")
        }
    }
  }
}

#Preview {
  ContentView()
}
