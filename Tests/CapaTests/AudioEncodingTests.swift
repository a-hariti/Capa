import AVFoundation
import XCTest
@testable import capa

final class AudioEncodingTests: XCTestCase {
  func testAACSettingsOverrideSampleRateAndChannels() {
    let baseline: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 48_000,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey: 128_000,
    ]

    let s = AudioEncoding.aacSettings(sampleRate: 24_000, channels: 1, baseline: baseline)
    XCTAssertEqual(s[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
    XCTAssertEqual(s[AVSampleRateKey] as? Double, 48_000)
    XCTAssertEqual(s[AVNumberOfChannelsKey] as? Int, 1)
    XCTAssertEqual(s[AVEncoderBitRateKey] as? Int, 96_000)
    XCTAssertNil(s[AVChannelLayoutKey])
  }

  func testAACSettingsDefaultValues() {
    let s = AudioEncoding.aacSettings(sampleRate: 44100, channels: 2, baseline: nil)
    XCTAssertEqual(s[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
    XCTAssertEqual(s[AVSampleRateKey] as? Double, 48_000.0)
    XCTAssertEqual(s[AVNumberOfChannelsKey] as? Int, 2)
    XCTAssertEqual(s[AVEncoderBitRateKey] as? Int, 128_000)
  }

  func testAACSettingsHighBitrateClamping() {
    let baseline: [String: Any] = [
      AVEncoderBitRateKey: 192_000
    ]
    let s = AudioEncoding.aacSettings(sampleRate: 48_000, channels: 1, baseline: baseline)
    XCTAssertEqual(s[AVEncoderBitRateKey] as? Int, 96_000)
  }
}
