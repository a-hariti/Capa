import XCTest
import AVFoundation
@testable import capa

final class ModelTests: XCTestCase {
  func testAudioRoutingParsing() {
    XCTAssertEqual(AudioRouting(argument: "mic"), .mic)
    XCTAssertEqual(AudioRouting(argument: "sys"), .system)
    XCTAssertEqual(AudioRouting(argument: "system"), .system)
    XCTAssertEqual(AudioRouting(argument: "mic+sys"), AudioRouting.micAndSystem)
    XCTAssertEqual(AudioRouting(argument: "sys+mic"), AudioRouting.micAndSystem)
    XCTAssertEqual(AudioRouting(argument: "none"), AudioRouting.none)
    XCTAssertEqual(AudioRouting(argument: ""), AudioRouting.none)
    XCTAssertNil(AudioRouting(argument: "invalid"))
  }

  func testCameraSelectionParsing() {
    if case .index(let i) = CameraSelection(argument: "0") {
      XCTAssertEqual(i, 0)
    } else {
      XCTFail()
    }

    if case .id(let s) = CameraSelection(argument: "my-camera-id") {
      XCTAssertEqual(s, "my-camera-id")
    } else {
      XCTFail()
    }
  }

  func testDisplaySelectionParsing() {
    if case .index(let i) = DisplaySelection(argument: "1") {
      XCTAssertEqual(i, 1)
    } else {
      XCTFail()
    }

    // Since Int(value) succeeds for any UInt32 string on 64-bit, it will be .index.
    if case .index(let i) = DisplaySelection(argument: "12345") {
      XCTAssertEqual(i, 12345)
    } else {
      XCTFail()
    }
  }

  func testFPSSelectionParsing() {
    if case .cfr(let fps) = FPSSelection(argument: "60") {
      XCTAssertEqual(fps, 60)
    } else {
      XCTFail()
    }

    if case .vfr = FPSSelection(argument: "vfr") {
      // success
    } else {
      XCTFail()
    }
  }

  func testParseCodec() {
    XCTAssertEqual(parseCodec("h264"), .h264)
    XCTAssertEqual(parseCodec("avc"), .h264)
    XCTAssertEqual(parseCodec("hevc"), .hevc)
    XCTAssertEqual(parseCodec("h265"), .hevc)
    XCTAssertNil(parseCodec("prores"))
  }
}
