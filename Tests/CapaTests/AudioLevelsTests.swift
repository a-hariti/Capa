import AVFoundation
import XCTest
import CoreMedia
@testable import capa

final class AudioLevelsTests: XCTestCase {
    func testPeakDBFSForSilence() throws {
      let sampleRate: Double = 48_000
      let channels = 1
      let frames = 1024
      let sbuf = try TestUtils.makePCMSampleBuffer(pts: .zero, frames: frames, channels: channels, sampleRate: sampleRate, amplitude: 0)

      let peak = AudioLevels.peak(from: sbuf)
      XCTAssertNotNil(peak)
      // Silence should be around -180dB (our floor is eps=1e-9 which is -180dB)
      XCTAssertLessThan(peak?.db ?? 0, -100)
      XCTAssertFalse(peak?.clipped ?? true)
    }

    func testPeakDBFSForFullScale() throws {
      let sampleRate: Double = 48_000
      let channels = 1
      let frames = 1024
      let sbuf = try TestUtils.makePCMSampleBuffer(pts: .zero, frames: frames, channels: channels, sampleRate: sampleRate, amplitude: 1.0)

      let peak = AudioLevels.peak(from: sbuf)
      XCTAssertNotNil(peak)
      XCTAssertEqual(peak?.db ?? -1, 0, accuracy: 0.1)
      XCTAssertTrue(peak?.clipped ?? false)
    }

    func testPeakDBFSForHalfScale() throws {
      let sampleRate: Double = 48_000
      let channels = 1
      let frames = 1024
      let sbuf = try TestUtils.makePCMSampleBuffer(pts: .zero, frames: frames, channels: channels, sampleRate: sampleRate, amplitude: 0.5)

      let peak = AudioLevels.peak(from: sbuf)
      XCTAssertNotNil(peak)
      // 0.5 amplitude is -6dB
      XCTAssertEqual(peak?.db ?? -1, -6, accuracy: 0.1)
      XCTAssertFalse(peak?.clipped ?? true)
    }
  }

