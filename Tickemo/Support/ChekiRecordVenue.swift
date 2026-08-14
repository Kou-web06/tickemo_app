import CoreLocation

extension CD_ChekiRecord {
  /// nil for every record saved before venue search existed, or whenever
  /// the typed venue text didn't get resolved to a map result — callers
  /// (RecordDetailView's venue section) treat that as "no map to show"
  /// rather than falling back to a placeholder pin.
  var venueCoordinate: CLLocationCoordinate2D? {
    guard let venueLatitude, let venueLongitude else { return nil }
    return CLLocationCoordinate2D(latitude: venueLatitude.doubleValue, longitude: venueLongitude.doubleValue)
  }
}
