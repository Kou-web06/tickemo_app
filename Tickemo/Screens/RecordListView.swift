import SwiftUI
import CoreData

enum RecordFilter: String, CaseIterable {
  case all
  case upcoming
  case past

  var label: String {
    switch self {
    case .all: "All"
    case .upcoming: "Upcoming"
    case .past: "Past"
    }
  }
}

enum RecordViewMode {
  case list
  case grid
}

private struct RecordListScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

/// Matches CollectionScreen.tsx's FREE_TICKET_LIMIT.
private let freeTicketLimit = 3

struct RecordListView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.colorScheme) private var systemColorScheme

  @FetchRequest(
    sortDescriptors: [
      NSSortDescriptor(keyPath: \CD_ChekiRecord.date, ascending: false),
      NSSortDescriptor(keyPath: \CD_ChekiRecord.createdAt, ascending: false),
    ]
  ) private var records: FetchedResults<CD_ChekiRecord>

  @State private var filter: RecordFilter = .all
  @State private var viewMode: RecordViewMode = .list
  @State private var showingCreateSheet = false
  @State private var showingPaywall = false
  // リストを少し下にスクロールしたらフィルタータブをコンパクト化する
  // （ずっとフルサイズで固定だとチケット表示領域を圧迫するため）
  @State private var isFilterBarCompact = false

  private let filterAccent = Color(red: 0.604, green: 0.486, blue: 0.973)
  private let scrollCoordinateSpace = "recordListScroll"

  private var isDarkMode: Bool {
    ThemePreferenceService.shared.effectiveIsDark(systemIsDark: systemColorScheme == .dark)
  }

  private var palette: CollectionPalette { CollectionPalette(isDarkMode: isDarkMode) }

  private var isOverFreeTicketLimit: Bool {
    !PurchasesService.shared.isPremium && records.count >= freeTicketLimit
  }

  private func requestAddTicket() {
    if isOverFreeTicketLimit {
      showingPaywall = true
    } else {
      showingCreateSheet = true
    }
  }

  private let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible())]

  private var artistTiles: [ArtistGrouping.Tile] {
    ArtistGrouping.tiles(from: filteredRecords)
  }

  private static let jstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return cal
  }()

  private var todayJST: Date { Self.jstCalendar.startOfDay(for: Date()) }

  private var filteredRecords: [CD_ChekiRecord] {
    let today = todayJST
    let source: [CD_ChekiRecord]
    switch filter {
    case .all:
      source = Array(records)
    case .upcoming:
      source = records.filter {
        guard let d = DateFormatting.date(from: $0.date) else { return false }
        return d >= today
      }
    case .past:
      source = records.filter {
        guard let d = DateFormatting.date(from: $0.date) else { return false }
        return d < today
      }
    }
    var upcoming: [CD_ChekiRecord] = []
    var past: [CD_ChekiRecord] = []
    for r in source {
      if let d = DateFormatting.date(from: r.date), d >= today {
        upcoming.append(r)
      } else {
        past.append(r)
      }
    }
    upcoming.sort {
      (DateFormatting.date(from: $0.date) ?? .distantPast) < (DateFormatting.date(from: $1.date) ?? .distantPast)
    }
    past.sort {
      (DateFormatting.date(from: $0.date) ?? .distantPast) > (DateFormatting.date(from: $1.date) ?? .distantPast)
    }
    return upcoming + past
  }

  private var nextLiveRecord: CD_ChekiRecord? {
    guard viewMode == .list else { return nil }
    return NextLiveCardData.nextLiveRecord(from: Array(records))
  }

  private var firstUpNextRecordID: NSManagedObjectID? {
    let today = todayJST
    return filteredRecords.first { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return date >= today
    }?.objectID
  }

  private var firstPastEventsRecordID: NSManagedObjectID? {
    let today = todayJST
    return filteredRecords.first { record in
      guard let date = DateFormatting.date(from: record.date) else { return false }
      return date < today
    }?.objectID
  }

  private var ticketWord: String { records.count == 1 ? "Ticket" : "Tickets" }

  var body: some View {
    Group {
      switch viewMode {
      case .list:
        // フィルタータブは常に表示 — 空状態でもここに置くことで、
        // Upcoming/Past が0件でもタブが消えて戻れなくなるのを防ぐ。
        VStack(alignment: .leading, spacing: 0) {
          filterTabBar
            .padding(.horizontal, 16)
            .padding(.top, isFilterBarCompact ? 6 : 12)
            .padding(.bottom, isFilterBarCompact ? 4 : 8)
          if filteredRecords.isEmpty {
            emptyState
          } else {
            listContent
          }
        }
        .onPreferenceChange(RecordListScrollOffsetKey.self) { offset in
          let shouldCompact = offset < -8
          guard shouldCompact != isFilterBarCompact else { return }
          withAnimation(.easeInOut(duration: 0.2)) { isFilterBarCompact = shouldCompact }
        }
      case .grid:
        if artistTiles.isEmpty {
          HugeIconUnavailableView(
            title: "アーティストがまだいません",
            icon: HugeIcons.userMultiple02,
            description: Text("アーティスト名を登録したチケットがここに表示されます")
          )
        } else {
          ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
              ForEach(artistTiles) { tile in
                NavigationLink(value: ArtistRoute(name: tile.name)) {
                  ArtistGridItemView(tile: tile)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(16)
          }
        }
      }
    }
    // 大タイトル → スクロールで自動的にナビバー中央へコンパクト収縮
    .navigationTitle("\(records.count) \(ticketWord)")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          requestAddTicket()
        } label: {
          Image("Ticket add")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
        }
      }
    }
    .navigationDestination(for: CD_ChekiRecord.self) { record in
      RecordDetailView(record: record)
    }
    .navigationDestination(for: ArtistRoute.self) { route in
      ArtistDetailView(artistName: route.name)
    }
    .sheet(isPresented: $showingCreateSheet) {
      RecordFormView(record: nil)
    }
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
    }
    .background(palette.screenBackground)
    .onAppear {
      WidgetReloaderService.sync(records: Array(records))
    }
    .onChange(of: records.count) { _, _ in
      WidgetReloaderService.sync(records: Array(records))
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
      WidgetReloaderService.sync(records: Array(records))
    }
  }

  // MARK: - List mode

  private var filterTabBar: some View {
    HStack(spacing: isFilterBarCompact ? 6 : 8) {
      ForEach(RecordFilter.allCases, id: \.self) { f in
        Button {
          filter = f
        } label: {
          Text(f.label)
            .font(.system(size: isFilterBarCompact ? 11 : 13, weight: .semibold))
            .foregroundStyle(filter == f ? .white : palette.primaryText)
            .padding(.horizontal, isFilterBarCompact ? 12 : 16)
            .padding(.vertical, isFilterBarCompact ? 5 : 7)
            .background {
              Capsule()
                .fill(filter == f ? filterAccent : .clear)
                .overlay {
                  if filter != f {
                    Capsule()
                      .stroke(palette.primaryText.opacity(isDarkMode ? 0.3 : 0.2), lineWidth: 1)
                  }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: filter)
      }
    }
  }

  private var listContent: some View {
    List {
      // フィルタータブのコンパクト化トリガー用、見えない高さ0の計測行
      Color.clear
        .frame(height: 0)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: RecordListScrollOffsetKey.self,
              value: proxy.frame(in: .named(scrollCoordinateSpace)).minY
            )
          }
        )

      // ── NextLiveCard ──
      if let nextLiveRecord {
        NextLiveCardView(record: nextLiveRecord)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        if !PurchasesService.shared.isPremium {
          PaywallBannerView()
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }

      // ── レコード一覧 ──
      ForEach(filteredRecords, id: \.objectID) { record in
        VStack(alignment: .leading, spacing: 8) {
          if record.objectID == firstUpNextRecordID {
            sectionLeadLabel("Up Next")
          } else if record.objectID == firstPastEventsRecordID {
            sectionLeadLabel("Past Events")
          }
          ZStack(alignment: .leading) {
            NavigationLink(value: record) { EmptyView() }.opacity(0)
            RecordRowView(record: record)
          }
        }
        .listRowSeparator(.hidden)
        // チケットは幅からアスペクト比で高さが決まるので、左右インセットを
        // 広げるだけで比率を保ったままひと回り小さく表示される
        .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
          Button(role: .destructive) {
            delete(record)
          } label: {
            HugeIconLabel(icon: HugeIcons.delete02) { Text("削除") }
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
    .coordinateSpace(name: scrollCoordinateSpace)
  }

  private func sectionLeadLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14, weight: .heavy))
      .tracking(0.4)
      .foregroundStyle(palette.primaryText)
  }

  // MARK: - Empty state

  // レコードは存在するが選択中のフィルターに0件、というケース
  // （records.isEmpty ではなく filteredRecords.isEmpty）で "Your collection
  // is empty" と出すのは誤解を招くため、フィルター別の文言に分ける。
  private var emptyStateTitle: String {
    guard records.isEmpty else {
      switch filter {
      case .all: return "コレクションは\nまだ空です"
      case .upcoming: return "開催予定の\nチケットはありません"
      case .past: return "過去の\nチケットはありません"
      }
    }
    return "コレクションは\nまだ空です"
  }

  private var emptyStateDescription: String {
    guard records.isEmpty else {
      switch filter {
      case .all: return "上のボタンから追加しよう"
      case .upcoming: return "今後のライブのチケットがここに表示されます"
      case .past: return "過去のライブのチケットがここに表示されます"
      }
    }
    return "上のボタンから追加しよう"
  }

  private var emptyStateButtonTitle: String {
    records.isEmpty ? "最初のライブを追加" : "チケットを追加"
  }

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 0) {
      Image("TicketEmpty")
        .resizable()
        .scaledToFit()
        .frame(width: 120, height: 120)
        .padding(.bottom, 24)

      Text(emptyStateTitle)
        .font(.system(size: 22, weight: .heavy))
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.center)
        .padding(.bottom, 10)

      Text(emptyStateDescription)
        .font(.system(size: 15))
        .foregroundStyle(palette.emptyText)
        .multilineTextAlignment(.center)
        .padding(.bottom, 24)

      Button {
        requestAddTicket()
      } label: {
        Text(emptyStateButtonTitle)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .padding(.vertical, 14)
          .padding(.horizontal, 24)
          .frame(minWidth: 172)
          .background(Color(hex: "#A328DD"))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 32)
    .padding(.bottom, 120)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func delete(_ record: CD_ChekiRecord) {
    viewContext.delete(record)
    try? viewContext.save()
  }
}
