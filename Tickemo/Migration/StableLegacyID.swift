import Foundation
import CryptoKit

/// Maps a legacy record's string `id` onto the `UUID` used by
/// `CD_ChekiRecord.id`/`CD_SetlistItem.id`.
///
/// RN generated ids with `Date.now().toString()`-style helpers in some code
/// paths and `crypto.randomUUID()` in others, so a real user's store can
/// contain ids that don't parse as UUIDs. The previous behaviour — mint a
/// fresh `UUID()` whenever parsing failed — made the import
/// non-idempotent: every re-run produced a brand new row for the same
/// legacy record. Hashing instead keeps the mapping stable across runs and
/// across devices, which is what both the upsert and the duplicate sweeper
/// rely on.
enum StableLegacyID {
  static func uuid(for legacyID: String) -> UUID {
    if let parsed = UUID(uuidString: legacyID) {
      return parsed
    }

    var bytes = Array(SHA256.hash(data: Data(legacyID.utf8)).prefix(16))
    // Shape the digest into a valid RFC 4122 v5-style UUID so nothing
    // downstream (CloudKit, Core Data, debugging tools) sees a malformed
    // value. The bits sacrificed here don't meaningfully affect collision
    // odds at this scale.
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80

    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
