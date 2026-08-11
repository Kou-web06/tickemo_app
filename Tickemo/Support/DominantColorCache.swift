import SwiftUI
import UIKit

/// カバー画像から抽出したドミナントカラー（RecordDetailView の背景色）。
struct DominantColor: Sendable {
  let color: Color
  let isDark: Bool
}

/// 抽出方法の違い。
/// - vibrant: 彩度の高いクラスタを優先し、彩度・明度をブーストした「映える」色
///   （RecordDetailView の背景ティント用）。
/// - dominant: 画像を最も支配している（最大クラスタの）色をそのまま返す。
///   背景をこの色で塗りつぶし、画像下端のフェードと自然に繋げる用途
///   （ArtistDetailView）。
enum DominantColorMode: Sendable, Hashable {
  case vibrant
  case dominant
}

/// ドミナントカラーの抽出結果をアプリ起動中キャッシュする。
/// 詳細画面を開いてから抽出すると、結果が届くまでデフォルトの白背景が
/// 一瞬見えてしまうため、一覧の行（RecordRowView）が表示された時点で
/// prewarm しておき、詳細画面は初回フレームからキャッシュ済みの色で
/// 描画できるようにする。抽出はランダムサンプリングを含むため、
/// キャッシュには「同じ画像なら開くたびに同じ色になる」副次効果もある。
@MainActor
final class DominantColorCache {
  static let shared = DominantColorCache()

  /// Data.hashValue は先頭数十バイトしか参照しないため、ヘッダーが共通の
  /// JPEG 同士で衝突しうる。サイズ + 先頭・中央・末尾の各 1KB を混ぜた
  /// キーにして、画像データ全体を保持せずに実用上十分な同一性判定を行う。
  private struct Key: Hashable {
    let count: Int
    let digest: Int
    let mode: DominantColorMode

    init(_ data: Data, mode: DominantColorMode) {
      count = data.count
      self.mode = mode
      var hasher = Hasher()
      hasher.combine(count)
      let chunk = 1024
      for start in [0, max(0, count / 2 - chunk / 2), max(0, count - chunk)] {
        let lower = data.startIndex + start
        let upper = min(data.endIndex, lower + chunk)
        data[lower..<upper].withUnsafeBytes { hasher.combine(bytes: $0) }
      }
      digest = hasher.finalize()
    }
  }

  private var entries: [Key: DominantColor] = [:]
  private var inFlight: [Key: Task<DominantColor, Never>] = [:]

  /// 抽出済みの結果を同期的に返す。ビューの init から呼び、初回フレームの
  /// 背景色として使う。
  func cachedColor(for data: Data, mode: DominantColorMode = .vibrant) -> DominantColor? {
    entries[Key(data, mode: mode)]
  }

  /// キャッシュがあれば即返し、なければ抽出して結果を保存する。
  /// 同じ画像への同時リクエストは 1 つの抽出タスクに合流する。
  func color(for data: Data, mode: DominantColorMode = .vibrant) async -> DominantColor {
    let key = Key(data, mode: mode)
    if let hit = entries[key] { return hit }
    if let running = inFlight[key] { return await running.value }

    let task = Task.detached(priority: .userInitiated) {
      DominantColorExtractor.extract(from: data, mode: mode)
    }
    inFlight[key] = task
    let result = await task.value
    entries[key] = result
    inFlight[key] = nil
    return result
  }

  /// 結果を待たずに抽出だけ先に始める（一覧の行が表示された時点で呼ぶ）。
  func prewarm(_ data: Data?, mode: DominantColorMode = .vibrant) {
    guard let data else { return }
    let key = Key(data, mode: mode)
    guard entries[key] == nil, inFlight[key] == nil else { return }
    Task { _ = await color(for: data, mode: mode) }
  }

  // MARK: - リモート画像（URL キー）

  // ArtistDetailView のヒーローのようにリモート URL しか持たない画像用。
  // ダウンロードは URLSession.shared（AsyncImage と同じ URLCache）経由なので
  // 画像の二重取得にはならず、抽出結果は URL 文字列で同期参照できる。

  private struct URLKey: Hashable {
    let urlString: String
    let mode: DominantColorMode
  }

  private var urlEntries: [URLKey: DominantColor] = [:]
  private var urlInFlight: [URLKey: Task<DominantColor?, Never>] = [:]

  func cachedColor(forURL urlString: String, mode: DominantColorMode = .vibrant) -> DominantColor? {
    urlEntries[URLKey(urlString: urlString, mode: mode)]
  }

  /// URL の画像を取得して抽出する。ダウンロード・デコードに失敗したら nil
  /// （呼び出し側は現在の背景色を維持する）。
  func color(forURL urlString: String, mode: DominantColorMode = .vibrant) async -> DominantColor? {
    let key = URLKey(urlString: urlString, mode: mode)
    if let hit = urlEntries[key] { return hit }
    if let running = urlInFlight[key] { return await running.value }
    guard let url = URL(string: urlString) else { return nil }

    let task = Task { () -> DominantColor? in
      guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
      return await self.color(for: data, mode: mode)
    }
    urlInFlight[key] = task
    let result = await task.value
    if let result { urlEntries[key] = result }
    urlInFlight[key] = nil
    return result
  }

  /// 結果を待たずにダウンロード＋抽出を先に始める（一覧・グリッドの表示時に呼ぶ）。
  func prewarm(urlString: String?, mode: DominantColorMode = .vibrant) {
    guard let urlString else { return }
    let key = URLKey(urlString: urlString, mode: mode)
    guard urlEntries[key] == nil, urlInFlight[key] == nil else { return }
    Task { _ = await color(forURL: urlString, mode: mode) }
  }
}

/// k-means ベースのドミナントカラー抽出（RecordDetailView から移設）。
enum DominantColorExtractor {
  /// 画像なし・デコード失敗時のデフォルト（ほぼ白のライトグレー）。
  static let fallback = DominantColor(
    color: Color(red: 0.976, green: 0.976, blue: 0.976), isDark: false)

  nonisolated static func extract(from data: Data, mode: DominantColorMode = .vibrant) -> DominantColor {
    guard let uiImage = UIImage(data: data) else { return fallback }

    let pixels = samplePixels(from: uiImage, gridSize: 64)
    guard !pixels.isEmpty else { return fallback }

    let clusters = kMeans(pixels: pixels, k: 6, iterations: 24)

    let (fr, fg, fb): (Float, Float, Float)
    switch mode {
    case .vibrant:
      let best = clusters.max(by: { $0.vibrantScore < $1.vibrantScore })
        ?? clusters.max(by: { $0.size < $1.size })!
      let (h, s, v) = rgbToHsb(r: best.r, g: best.g, b: best.b)
      let boostedS = min(s * 1.5, 1.0)
      let boostedV = max(min(v * 1.1, 1.0), 0.25)
      (fr, fg, fb) = hsbToRgb(h: h, s: boostedS, v: boostedV)
    case .dominant:
      // 最大クラスタ＝画像を最も支配している色を無加工で返す。
      // 背景をこの色で塗ると画像下端のフェードがそのまま背景に溶ける。
      let best = clusters.max(by: { $0.size < $1.size })!
      (fr, fg, fb) = (best.r, best.g, best.b)
    }

    // W3C relative luminance — < 0.5 を暗い背景と判定して白テキストに切り替える
    let luminance = 0.2126 * Double(fr) + 0.7152 * Double(fg) + 0.0722 * Double(fb)
    return DominantColor(
      color: Color(red: Double(fr), green: Double(fg), blue: Double(fb)),
      isDark: luminance < 0.5
    )
  }

  // MARK: - K-means internals

  private struct ColorSample {
    var r, g, b: Float
  }

  private struct ColorCluster {
    var r, g, b: Float
    var size: Int

    var saturation: Float {
      let mx = max(r, g, b), mn = min(r, g, b)
      return mx == 0 ? 0 : (mx - mn) / mx
    }

    var vibrantScore: Float {
      let bri = max(r, g, b)
      let penaltyDark  = bri < 0.12 ? Float(0.05) : 1
      let penaltyLight = bri > 0.96 ? Float(0.15) : 1
      return Float(size) * saturation * penaltyDark * penaltyLight
    }
  }

  /// CGContext で gridSize×gridSize にダウンサンプルし、下端ほど高確率でサンプリングする。
  /// 行位置 t (0=上端, 1=下端) に対して t² の確率でピクセルを採用するため、
  /// 下端付近のピクセルが k-means のクラスタリングに強く影響する。
  private nonisolated static func samplePixels(
    from uiImage: UIImage, gridSize: Int
  ) -> [ColorSample] {
    var raw = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
    guard
      let cgImage = uiImage.cgImage,
      let ctx = CGContext(
        data: &raw,
        width: gridSize, height: gridSize,
        bitsPerComponent: 8,
        bytesPerRow: gridSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return [] }

    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

    var samples: [ColorSample] = []
    samples.reserveCapacity(gridSize * gridSize / 2)

    for y in 0..<gridSize {
      let t = Float(y) / Float(gridSize - 1)
      let rate = t * t
      for x in 0..<gridSize {
        guard Float.random(in: 0...1) < rate else { continue }
        let o = (y * gridSize + x) * 4
        guard raw[o + 3] > 25 else { continue }
        samples.append(ColorSample(
          r: Float(raw[o]) / 255,
          g: Float(raw[o + 1]) / 255,
          b: Float(raw[o + 2]) / 255
        ))
      }
    }
    return samples
  }

  private nonisolated static func kMeans(pixels: [ColorSample], k: Int, iterations: Int) -> [ColorCluster] {
    guard pixels.count >= k else {
      return pixels.map { ColorCluster(r: $0.r, g: $0.g, b: $0.b, size: 1) }
    }

    var centroids: [ColorSample] = [pixels[Int.random(in: 0..<pixels.count)]]
    while centroids.count < k {
      let dists = pixels.map { p in centroids.map { distSq(p, $0) }.min()! }
      let total = dists.reduce(Float(0), +)
      guard total > 0 else { centroids.append(pixels[Int.random(in: 0..<pixels.count)]); continue }
      var pick = Float.random(in: 0..<total)
      var chosen = pixels.last!
      for (p, d) in zip(pixels, dists) { pick -= d; if pick <= 0 { chosen = p; break } }
      centroids.append(chosen)
    }

    var assignments = [Int](repeating: 0, count: pixels.count)

    for _ in 0..<iterations {
      for (i, p) in pixels.enumerated() {
        var minD = Float.infinity, best = 0
        for (j, c) in centroids.enumerated() {
          let d = distSq(p, c); if d < minD { minD = d; best = j }
        }
        assignments[i] = best
      }
      var sums = [(r: Float, g: Float, b: Float, n: Int)](repeating: (0, 0, 0, 0), count: k)
      for (i, p) in pixels.enumerated() {
        let j = assignments[i]
        sums[j].r += p.r; sums[j].g += p.g; sums[j].b += p.b; sums[j].n += 1
      }
      for j in 0..<k where sums[j].n > 0 {
        let n = Float(sums[j].n)
        centroids[j] = ColorSample(r: sums[j].r / n, g: sums[j].g / n, b: sums[j].b / n)
      }
    }

    var sizes = [Int](repeating: 0, count: k)
    for a in assignments { sizes[a] += 1 }
    return zip(centroids, sizes).map { ColorCluster(r: $0.r, g: $0.g, b: $0.b, size: $1) }
  }

  private nonisolated static func distSq(_ a: ColorSample, _ b: ColorSample) -> Float {
    let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
    return dr * dr + dg * dg + db * db
  }

  private nonisolated static func rgbToHsb(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    let s: Float = mx == 0 ? 0 : d / mx
    var h: Float = 0
    if d > 0 {
      switch mx {
      case r:  h = (g - b) / d + (g < b ? 6 : 0)
      case g:  h = (b - r) / d + 2
      default: h = (r - g) / d + 4
      }
      h /= 6
    }
    return (h, s, mx)
  }

  private nonisolated static func hsbToRgb(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float) {
    guard s > 0 else { return (v, v, v) }
    let i = Int(h * 6) % 6
    let f = h * 6 - floor(h * 6)
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch i {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
  }
}
