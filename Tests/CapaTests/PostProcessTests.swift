import XCTest
@testable import capa

final class PostProcessTests: XCTestCase {
  func testMixConfigGainLinear() {
    let config = PostProcess.MixConfig(microphoneGainDB: 6, systemGainDB: -6, safeMixLimiter: true)

    XCTAssertEqual(config.gainLinear(for: .microphone), 1.9952623, accuracy: 0.001) // +6dB is ~2x
    XCTAssertEqual(config.gainLinear(for: .system), 0.5011872, accuracy: 0.001)   // -6dB is ~0.5x
    XCTAssertEqual(config.gainLinear(for: .unknown), 1.0)

    let defaultUnits = PostProcess.MixConfig()
    XCTAssertEqual(defaultUnits.gainLinear(for: .microphone), 1.0)
    XCTAssertEqual(defaultUnits.gainLinear(for: .system), 1.0)
  }
}
