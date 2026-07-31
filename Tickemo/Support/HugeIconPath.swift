import SwiftUI

/// Minimal SVG path-data (`d` attribute) parser for HugeIcons' 24x24
/// stroke-style icons. Supports the commands actually observed across the
/// icons this app uses — M/L/H/V/C/S/Q/T/Z, both absolute and relative —
/// plus a defensive (non-curved) fallback for A/a (elliptical arc), which
/// was never observed in the sampled icon set but is handled gracefully
/// rather than silently dropping path data if a future icon happens to use
/// one.
enum HugeIconPath {
  static func parse(_ d: String) -> Path {
    var path = Path()
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    // Reflected control point for smooth curve commands (S/T); nil resets
    // to the current point when the previous command wasn't a curve.
    var lastControl: CGPoint?
    var lastCommandWasCurve = false

    var index = d.startIndex
    var command: Character?

    func skipSeparators() {
      while index < d.endIndex, " ,\n\t\r".contains(d[index]) {
        index = d.index(after: index)
      }
    }

    func parseNumber() -> Double? {
      skipSeparators()
      guard index < d.endIndex else { return nil }
      var end = index
      if d[end] == "+" || d[end] == "-" { end = d.index(after: end) }
      var sawDigitOrDot = false
      while end < d.endIndex, d[end].isNumber || d[end] == "." {
        sawDigitOrDot = true
        end = d.index(after: end)
      }
      if end < d.endIndex, d[end] == "e" || d[end] == "E" {
        var expEnd = d.index(after: end)
        if expEnd < d.endIndex, d[expEnd] == "+" || d[expEnd] == "-" {
          expEnd = d.index(after: expEnd)
        }
        var sawExpDigit = false
        while expEnd < d.endIndex, d[expEnd].isNumber {
          sawExpDigit = true
          expEnd = d.index(after: expEnd)
        }
        if sawExpDigit { end = expEnd }
      }
      guard sawDigitOrDot, end > index else { return nil }
      let value = Double(d[index..<end])
      index = end
      return value
    }

    func parsePoint() -> CGPoint? {
      guard let x = parseNumber(), let y = parseNumber() else { return nil }
      return CGPoint(x: x, y: y)
    }

    func rel(_ p: CGPoint) -> CGPoint { CGPoint(x: current.x + p.x, y: current.y + p.y) }

    while true {
      skipSeparators()
      guard index < d.endIndex else { break }
      if d[index].isLetter {
        command = d[index]
        index = d.index(after: index)
      }
      guard let cmd = command else { break }
      let isCurveCmd = "CcSsQqTt".contains(cmd)

      switch cmd {
      case "M":
        guard let p = parsePoint() else { return path }
        current = p; subpathStart = p
        path.move(to: p)
        command = "L"
      case "m":
        guard let p = parsePoint() else { return path }
        current = rel(p); subpathStart = current
        path.move(to: current)
        command = "l"
      case "L":
        guard let p = parsePoint() else { return path }
        path.addLine(to: p); current = p
      case "l":
        guard let p = parsePoint() else { return path }
        current = rel(p); path.addLine(to: current)
      case "H":
        guard let x = parseNumber() else { return path }
        current = CGPoint(x: x, y: current.y); path.addLine(to: current)
      case "h":
        guard let dx = parseNumber() else { return path }
        current = CGPoint(x: current.x + dx, y: current.y); path.addLine(to: current)
      case "V":
        guard let y = parseNumber() else { return path }
        current = CGPoint(x: current.x, y: y); path.addLine(to: current)
      case "v":
        guard let dy = parseNumber() else { return path }
        current = CGPoint(x: current.x, y: current.y + dy); path.addLine(to: current)
      case "C":
        guard let c1 = parsePoint(), let c2 = parsePoint(), let p = parsePoint() else { return path }
        path.addCurve(to: p, control1: c1, control2: c2)
        current = p; lastControl = c2
      case "c":
        guard let c1r = parsePoint(), let c2r = parsePoint(), let pr = parsePoint() else { return path }
        let c1 = rel(c1r), c2 = rel(c2r), p = rel(pr)
        path.addCurve(to: p, control1: c1, control2: c2)
        current = p; lastControl = c2
      case "S":
        guard let c2 = parsePoint(), let p = parsePoint() else { return path }
        let c1 = lastCommandWasCurve ? reflect(lastControl, over: current) : current
        path.addCurve(to: p, control1: c1, control2: c2)
        current = p; lastControl = c2
      case "s":
        guard let c2r = parsePoint(), let pr = parsePoint() else { return path }
        let c2 = rel(c2r), p = rel(pr)
        let c1 = lastCommandWasCurve ? reflect(lastControl, over: current) : current
        path.addCurve(to: p, control1: c1, control2: c2)
        current = p; lastControl = c2
      case "Q":
        guard let c = parsePoint(), let p = parsePoint() else { return path }
        path.addQuadCurve(to: p, control: c)
        current = p; lastControl = c
      case "q":
        guard let cr = parsePoint(), let pr = parsePoint() else { return path }
        let c = rel(cr), p = rel(pr)
        path.addQuadCurve(to: p, control: c)
        current = p; lastControl = c
      case "T":
        guard let p = parsePoint() else { return path }
        let c = lastCommandWasCurve ? reflect(lastControl, over: current) : current
        path.addQuadCurve(to: p, control: c)
        current = p; lastControl = c
      case "t":
        guard let pr = parsePoint() else { return path }
        let p = rel(pr)
        let c = lastCommandWasCurve ? reflect(lastControl, over: current) : current
        path.addQuadCurve(to: p, control: c)
        current = p; lastControl = c
      case "A", "a":
        // Not observed in any icon this app uses; approximated as a
        // straight line to the arc's endpoint rather than dropping the
        // remaining path data if one is ever encountered.
        guard let _ = parseNumber(), let _ = parseNumber(), let _ = parseNumber(),
              let _ = parseNumber(), let _ = parseNumber(), let p = parsePoint()
        else { return path }
        current = cmd == "a" ? rel(p) : p
        path.addLine(to: current)
      case "Z", "z":
        path.closeSubpath()
        current = subpathStart
        command = nil
      default:
        return path
      }

      lastCommandWasCurve = isCurveCmd
    }
    return path
  }

  private static func reflect(_ point: CGPoint?, over pivot: CGPoint) -> CGPoint {
    guard let point else { return pivot }
    return CGPoint(x: 2 * pivot.x - point.x, y: 2 * pivot.y - point.y)
  }
}
