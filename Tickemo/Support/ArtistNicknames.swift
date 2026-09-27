import Foundation

/// アーティストの「あだ名」（ユーザーが付ける表示名）の純粋ロジック。
///
/// Apple Music 検索で登録した名前は海外アーティストでもカタカナ表記に
/// なることがあり、「自分の好きな表記・あだ名で表示したい」という要望を
/// 受けて追加した。記録側の `artist` / `artists`（＝検索で確定した正式名）
/// は一切書き換えず、表示の直前にだけ差し替える。そのため Report の集計、
/// アーティスト詳細への遷移、Apple Music の写真・曲検索、セトリの出演者
/// 突き合わせは従来どおり正式名で動く。
///
/// 対応表のキーは正式名を trim + lowercased したもので、
/// `ArtistGrouping` のグルーピング規則（大文字小文字を区別しない）と揃えて
/// いる — Collection / Report で1枚のタイルにまとまるアーティストには
/// 必ず同じあだ名が出る。
enum ArtistNicknames {
  static func key(for artistName: String) -> String? {
    let trimmed = artistName.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed.lowercased()
  }

  static func nickname(for artistName: String, in nicknames: [String: String]) -> String? {
    guard let key = key(for: artistName) else { return nil }
    return nicknames[key]
  }

  /// 表示用の名前。あだ名があればそれ、無ければ正式名をそのまま返す。
  static func displayName(for artistName: String, in nicknames: [String: String]) -> String {
    nickname(for: artistName, in: nicknames) ?? artistName
  }

  /// あだ名を設定した後の対応表を返す。空欄、または正式名と完全に同じ
  /// 文字列なら「あだ名なし」に戻す（大文字小文字だけ変えたいケースは
  /// あだ名として残す）。
  static func updating(_ nicknames: [String: String], artistName: String, nickname: String?) -> [String: String] {
    guard let key = key(for: artistName) else { return nicknames }
    var updated = nicknames
    let trimmedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let trimmedName = artistName.trimmingCharacters(in: .whitespaces)
    if trimmedNickname.isEmpty || trimmedNickname == trimmedName {
      updated.removeValue(forKey: key)
    } else {
      updated[key] = trimmedNickname
    }
    return updated
  }
}
