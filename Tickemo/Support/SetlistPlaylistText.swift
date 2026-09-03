import Foundation

/// セットリストを他の音楽プレイヤーへ持ち出すためのテキスト化。
///
/// Apple Music へのプレイリスト作成（ApplePlaylistExporter）だけだと、
/// 加入していない人や別のプレイヤーを使っている人が取り残されるので、
/// 「どこにでも貼れる曲リスト」も併せて出せるようにする。素の文字列に
/// しておけば、コピーでも共有シートでもそのまま流せる。
enum SetlistPlaylistText {
  /// Apple Music に作るプレイリストの名前。ライブ名が空のチケットもある
  /// ので、その場合は会場・日付で識別できる名前に落とす。
  static func playlistName(liveName: String?, venue: String?, date: String?) -> String {
    let trimmedLive = liveName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedVenue = venue?.trimmingCharacters(in: .whitespacesAndNewlines)
    let dotted = dottedDate(from: date)

    let base = [trimmedLive, trimmedVenue].compactMap { $0 }.first { !$0.isEmpty }
      ?? "セットリスト"
    guard let dotted else { return base }
    return "\(base)（\(dotted)）"
  }

  /// 貼り付け用の曲リスト。1行目にライブ名、2行目に日付と会場を置き、
  /// 空行のあとに通し番号つきの曲を並べる。
  ///
  /// MC / アンコールの区切り行は出さない — プレイヤーに貼る用途なので、
  /// 曲名以外が混ざると邪魔になるため。アーティスト名は曲カードや
  /// プロバイダー検索と同じ規則（実際に歌った人を優先）で決める。
  static func songList(
    liveName: String?,
    venue: String?,
    date: String?,
    songs: [(songName: String?, performerName: String?, artistName: String?)]
  ) -> String {
    var lines: [String] = []

    let trimmedLive = liveName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmedLive, !trimmedLive.isEmpty {
      lines.append(trimmedLive)
    }

    let trimmedVenue = venue?.trimmingCharacters(in: .whitespacesAndNewlines)
    let subtitle = [dottedDate(from: date), trimmedVenue?.isEmpty == false ? trimmedVenue : nil]
      .compactMap { $0 }
      .joined(separator: " / ")
    if !subtitle.isEmpty {
      lines.append(subtitle)
    }

    if !lines.isEmpty {
      lines.append("")
    }

    var number = 0
    for song in songs {
      guard let name = song.songName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
        continue
      }
      number += 1
      let artist = SetlistPerformers.displayName(
        performer: song.performerName,
        songArtist: song.artistName
      )
      let numbered = String(format: "%02d. %@", number, name)
      lines.append(artist.map { "\(numbered) - \($0)" } ?? numbered)
    }

    return lines.joined(separator: "\n")
  }

  /// `CD_ChekiRecord.date` は "yyyy-MM-dd" の壁時計文字列。表示用の
  /// "yyyy.MM.dd" に直すが、パースできない値はそのまま返さず捨てる
  /// （壊れた日付を書き出しに混ぜない）。
  private static func dottedDate(from raw: String?) -> String? {
    guard let raw, let date = DateFormatting.date(from: raw) else { return nil }
    return DateFormatting.dottedString(from: date)
  }
}
