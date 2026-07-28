import Foundation

/// Backs the `artists`/`artistImageUrls` Transformable attributes on `CD_ChekiRecord`.
/// Registered once at app startup via `StringArrayTransformer.register()`.
final class StringArrayTransformer: NSSecureUnarchiveFromDataTransformer {
  static let name = NSValueTransformerName(rawValue: "StringArrayTransformer")

  override static var allowedTopLevelClasses: [AnyClass] {
    [NSArray.self, NSString.self]
  }

  static func register() {
    ValueTransformer.setValueTransformer(StringArrayTransformer(), forName: name)
  }
}
