import XCTest
@testable import capa

final class LiveMetersTests: XCTestCase {
  func testLiveMetersUpdateAndRender() {
    let meters = LiveMeters()

    // Initially zeroed
    let initial = meters.render(includeMicrophone: true, includeSystemAudio: true)
    XCTAssertTrue(initial.contains("--dB"))

    // Update mic
    meters.update(source: .microphone, peak: AudioPeak(db: -10, clipped: false))
    let afterMic = meters.render(includeMicrophone: true, includeSystemAudio: false)
    XCTAssertTrue(afterMic.contains("-10dB"))
    XCTAssertFalse(afterMic.contains("!"))

    // Update with clipping
    meters.update(source: .microphone, peak: AudioPeak(db: 0, clipped: true))
    let afterClip = meters.render(includeMicrophone: true, includeSystemAudio: false)
    XCTAssertTrue(afterClip.contains("!"))

    // Zero it
    meters.zero()
    let afterZero = meters.render(includeMicrophone: true, includeSystemAudio: true)
    XCTAssertTrue(afterZero.contains("--dB"))
  }
}
