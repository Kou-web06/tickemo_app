import Foundation

/// 対バン／フェスで「どの曲を誰が演奏したか」を扱う純粋ロジック。
///
/// 以前は `RecordFormView` がアーティストごとに独立したセトリ配列を持ち、
/// 保存時に［アーティスト1の全曲］→［アーティスト2の全曲］の順で flatMap
/// していた。この構造では A→B→A のような交互演奏が原理的に表現できず、
/// さらに再編集時は曲の `artistName`（Apple Music 音源のアーティスト）を
/// 手がかりにバケットへ振り分け直していたため、`artistName` を持たない
/// MC / アンコール行の位置が編集のたびにずれていた。
///
/// 現在はセトリを実際の演奏順どおりの1本のフラットな配列として保持し、
/// 各行が `performerName`（その公演で実際に演奏した出演者）を持つ。
/// 音源のアーティスト（`artistName`）とは役割が別物なので、混同しないこと。
enum SetlistPerformers {
  static func normalized(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    return trimmed
  }

  /// 既存レコードを編集で開くときに、各行の出演者を確定させる。
  ///
  /// 優先順は 1) 保存済みの `performerName`、2) 曲の音源アーティストが
  /// 出演者名と一致すればそれ（表記ゆれは出演者側の表記に寄せる）、
  /// 3) 直前の行から引き継ぎ。3) があるおかげで、`artistName` を持たない
  /// MC / アンコール行や、音源アーティストが出演者と違うカバー曲も、
  /// 直前の曲と同じブロックに素直に収まる。先頭が MC で始まる場合だけは
  /// 引き継ぐ相手がいないので nil のまま（＝どのブロックにも属さない）。
  ///
  /// `stored` / `songArtists` は同じ並び順・同じ要素数の前提。
  static func resolve(stored: [String?], songArtists: [String?], artistNames: [String]) -> [String?] {
    let candidates = artistNames.compactMap(normalized)
    var carried: String?
    return stored.indices.map { index in
      if let explicit = normalized(stored[index]) {
        carried = explicit
        return explicit
      }
      let songArtist = index < songArtists.count ? normalized(songArtists[index]) : nil
      if let songArtist,
         let matched = candidates.first(where: { $0.caseInsensitiveCompare(songArtist) == .orderedSame }) {
        carried = matched
        return matched
      }
      return carried
    }
  }

  /// 出演者が切り替わる位置に出す見出しラベル。切り替わらない行は nil。
  ///
  /// 出演者が実質1組しかいない公演（ワンマンや、対バンでも片方しか
  /// セトリを入れていない場合）では見出しを一切出さない — 全行に同じ
  /// バンド名が並ぶだけで情報量がゼロになるため。
  static func sectionHeaders(for performers: [String?]) -> [String?] {
    guard distinctNames(in: performers).count > 1 else {
      return Array(repeating: nil, count: performers.count)
    }
    var current: String?
    return performers.map { performer in
      guard let performer = normalized(performer) else { return nil }
      guard performer.caseInsensitiveCompare(current ?? "") != .orderedSame else { return nil }
      current = performer
      return performer
    }
  }

  /// 出現順・大文字小文字を無視した重複排除（表記は初出のものを採用）。
  static func distinctNames(in performers: [String?]) -> [String] {
    var seen = Set<String>()
    var order: [String] = []
    for performer in performers.compactMap(normalized) {
      if seen.insert(performer.lowercased()).inserted {
        order.append(performer)
      }
    }
    return order
  }
}
