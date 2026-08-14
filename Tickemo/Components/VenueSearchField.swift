import SwiftUI
import MapKit

/// Reconnects RecordFormView's venue field to MapKit search, resolving a
/// real coordinate for VenueMapCardView. Deliberately NOT the same
/// "search-only, must pick a suggestion" shape as ArtistSearchField:
/// `name` stays a plain, always-editable TextField (free text still saves
/// fine, matching the field's pre-existing behavior) — the dropdown is a
/// convenience on top, not a requirement. Picking a suggestion fills the
/// exact name and resolves `coordinate`; editing the text afterward clears
/// `coordinate` again so a stale, mismatched pin can never be saved.
struct VenueSearchField: View {
  @Binding var name: String
  @Binding var coordinate: CLLocationCoordinate2D?
  @Binding var address: String?
  var placeholder: String = "会場名"

  @StateObject private var completerDelegate = VenueSearchCompleterDelegate()
  // Set right before select() programmatically writes `name`, so the
  // resulting onChange doesn't re-trigger a search against the name we
  // just picked (which would otherwise flash the dropdown open again).
  @State private var suppressNextQueryUpdate = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        HugeIconView(icon: HugeIcons.search01, size: 16)
          .foregroundStyle(Color(white: 0.6))
        TextField(placeholder, text: $name)
          .onChange(of: name) { _, newValue in
            guard !suppressNextQueryUpdate else {
              suppressNextQueryUpdate = false
              return
            }
            coordinate = nil
            address = nil
            completerDelegate.updateQuery(newValue)
          }
      }
      if !completerDelegate.results.isEmpty {
        dropdown
      }
    }
  }

  private var dropdown: some View {
    VStack(spacing: 0) {
      ForEach(Array(completerDelegate.results.enumerated()), id: \.offset) { index, result in
        Button {
          select(result)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(.primary)
            if !result.subtitle.isEmpty {
              Text(result.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if index < completerDelegate.results.count - 1 {
          Divider()
        }
      }
    }
  }

  private func select(_ completion: MKLocalSearchCompletion) {
    suppressNextQueryUpdate = true
    name = completion.title
    // MKLocalSearchCompleter's own subtitle is already a formatted address
    // for POI results — available immediately, no need to wait on the
    // async MKLocalSearch resolution below just to show it.
    address = completion.subtitle.isEmpty ? nil : completion.subtitle
    completerDelegate.results = []

    Task {
      let request = MKLocalSearch.Request(completion: completion)
      let response = try? await MKLocalSearch(request: request).start()
      coordinate = response?.mapItems.first?.placemark.coordinate
    }
  }
}

/// MKLocalSearchCompleterDelegate is callback-based, not async/await —
/// this just republishes its results as @Published for VenueSearchField to
/// observe. Region is biased to Japan, matching AppleMusicService's
/// storefront="jp" precedent (this app's userbase/content is Japan-focused
/// regardless of device locale).
final class VenueSearchCompleterDelegate: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
  @Published var results: [MKLocalSearchCompletion] = []
  private let completer = MKLocalSearchCompleter()

  override init() {
    super.init()
    completer.delegate = self
    completer.resultTypes = [.pointOfInterest, .address]
    completer.region = MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 36.2048, longitude: 138.2529),
      latitudinalMeters: 2_000_000,
      longitudinalMeters: 2_000_000
    )
  }

  func updateQuery(_ query: String) {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
      results = []
      return
    }
    completer.queryFragment = query
  }

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    results = completer.results
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    results = []
  }
}
