import Foundation
import Darwin

enum Ansi {
  static let reset = "\u{001B}[0m"
  static let hideCursor = "\u{001B}[?25l"
  static let showCursor = "\u{001B}[?25h"

  static func fg256(_ n: Int) -> String { "\u{001B}[38;5;\(n)m" }
}

struct Bar {
  enum Style {
    /// A smooth bar with 1/8-cell partial blocks.
    case smooth
    /// A stepped meter (8 levels) using Unicode "height" blocks.
    case steps
  }

  static func render(fraction: Double, width: Int, style: Style) -> String {
    let w = max(1, width)
    let t = max(0.0, min(1.0, fraction))
    switch style {
    case .smooth:
      // Render in 1/8th-cell units for a smoother bar.
      let partial = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
      let units = Int((Double(w) * 8.0 * t).rounded(.toNearestOrAwayFromZero))
      let full = min(w, units / 8)
      let rem = units % 8
      let hasPartial = rem > 0 && full < w
      let rest = w - full - (hasPartial ? 1 : 0)
      return String(repeating: "█", count: full)
        + (hasPartial ? partial[rem] : "")
        + String(repeating: "░", count: max(0, rest))

    case .steps:
      let chars = Array("▁▂▃▄▅▆▇█")
      let idx = min(chars.count - 1, max(0, Int((Double(chars.count - 1) * t).rounded(.toNearestOrAwayFromZero))))
      return String(chars[idx])
    }
  }
}

final class ProgressBar: @unchecked Sendable {
  private let fd: UnsafeMutablePointer<FILE> = stderr
  private let prefix: String
  private let total: Int64
  private var lastLen = 0
  private var lastUnits: Int = -1
  private var active = false

  init(prefix: String, total: Int64) {
    self.prefix = prefix
    self.total = max(1, total)
  }

  func startIfTTY() {
    guard isatty(fileno(fd)) != 0 else { return }
    active = true
    write(Ansi.hideCursor)
  }

  func update(completed: Int64) {
    guard active else { return }
    let clamped = max(0, min(total, completed))

    // Smoothly track bar fill, not just integer percent.
    let width = 24
    let units = Int((Double(clamped) / Double(total)) * Double(width * 8))
    if units == lastUnits { return }
    lastUnits = units

    let pct = Int((Double(clamped) / Double(total)) * 100.0)
    let bar = Bar.render(fraction: Double(clamped) / Double(total), width: width, style: .smooth)
    let lead = prefix.isEmpty ? "" : "\(prefix) "
    let s = "\(lead)[\(bar)] \(pct)%"

    let pad = max(0, lastLen - s.utf8.count)
    lastLen = s.utf8.count
    write("\r" + s + String(repeating: " ", count: pad))
  }

  func stop() {
    guard active else { return }
    active = false
    update(completed: total)
    write("\n")
    write(Ansi.showCursor)
  }

  private func write(_ s: String) {
    s.withCString { cstr in
      fputs(cstr, fd)
      fflush(fd)
    }
  }
}

