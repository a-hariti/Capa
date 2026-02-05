import Foundation

final class LiveMeters: @unchecked Sendable {
  private let lock = NSLock()
  private var micDB: Float?
  private var systemDB: Float?

  // Simple EMA smoothing so the meter isn't too twitchy.
  private let alpha: Float = 0.20

  func update(source: ScreenRecorder.AudioSource, db: Float) {
    lock.lock()
    defer { lock.unlock() }

    let clamped = max(-80, min(0, db))
    switch source {
    case .microphone:
      micDB = smooth(old: micDB, new: clamped)
    case .system:
      systemDB = smooth(old: systemDB, new: clamped)
    }
  }

  func render(includeMicrophone: Bool, includeSystemAudio: Bool) -> String {
    lock.lock()
    let mic = micDB
    let sys = systemDB
    lock.unlock()

    var parts: [String] = []
    if includeMicrophone {
      parts.append(LoudnessMeter.render(label: "MIC", db: mic, width: 12, style: .smooth))
    }
    if includeSystemAudio {
      parts.append(LoudnessMeter.render(label: "SYS", db: sys, width: 12, style: .smooth))
    }
    return parts.joined(separator: "  ")
  }

  private func smooth(old: Float?, new: Float) -> Float {
    guard let old else { return new }
    return old * (1 - alpha) + new * alpha
  }
}

