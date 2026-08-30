import SwiftUI
import MapKit

/// Default-styled MapKit card for RecordDetailView's venue section — the
/// whole card opens the venue in Maps when tapped. The map itself doesn't
/// accept gestures (`interactionModes: []`); the tap target is the enclosing
/// Button, not the map's own pan/zoom handling. Bottom fade + name/address
/// overlay mirrors the jacket-photo treatment used elsewhere in
/// RecordDetailView (fading into the record's dominant color, not a flat
/// black), rendered as an actual glass surface rather than a plain gradient.
struct VenueMapCardView: View {
  let venueName: String
  let address: String?
  let coordinate: CLLocationCoordinate2D
  let tintColor: Color

  private var cameraPosition: MapCameraPosition {
    .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
  }

  @Environment(\.appFontChoice) private var appFont

  var body: some View {
    Button(action: openInMaps) {
      ZStack(alignment: .bottomLeading) {
        Map(initialPosition: cameraPosition, interactionModes: []) {
          Marker(venueName, coordinate: coordinate)
        }
        .allowsHitTesting(false)

        glassFade
          .frame(height: 130)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

        VStack(alignment: .leading, spacing: 2) {
          Text(venueName)
            .font(appFont.bold(18))
            .foregroundStyle(.white)
            .lineLimit(1)
          if let address, !address.isEmpty {
            Text(address)
              .font(appFont.regular(13))
              .foregroundStyle(.white.opacity(0.85))
              .lineLimit(1)
          }
        }
        .padding(16)
      }
      .frame(height: 220)
      .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    .buttonStyle(.plain)
  }

  /// Real Liquid Glass on iOS 26+ (tinted with the jacket's dominant color,
  /// same source `RecordDetailView` uses for the setlist card/song rows),
  /// with a plain Material tint as the pre-26 fallback. Masked so it fades
  /// out toward the top instead of ending in a hard edge.
  @ViewBuilder
  private var glassFade: some View {
    Group {
      if #available(iOS 26.0, *) {
        Rectangle()
          .fill(.clear)
          .glassEffect(.regular.tint(tintColor.opacity(0.75)), in: Rectangle())
      } else {
        Rectangle()
          .fill(.ultraThinMaterial)
          .overlay(tintColor.opacity(0.6))
      }
    }
    .mask(
      LinearGradient(colors: [.black, .black.opacity(0.9), .clear], startPoint: .bottom, endPoint: .top)
    )
    .allowsHitTesting(false)
  }

  private func openInMaps() {
    let placemark = MKPlacemark(coordinate: coordinate)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = venueName
    mapItem.openInMaps()
  }
}
