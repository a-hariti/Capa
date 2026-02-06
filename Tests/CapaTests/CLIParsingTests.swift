import XCTest
@testable import capa

final class CLIParsingTests: XCTestCase {
  func testParseDisplayIndex() throws {
    let parsed = try Capa.parseAsRoot(["--display-index", "2"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertEqual(cmd.displayIndex, 2)
  }

  func testParseAudioAndFPS() throws {
    let parsed = try Capa.parseAsRoot(["--audio", "system", "--fps", "30"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertEqual(cmd.audioSpec, "system")
    XCTAssertEqual(cmd.fps, 30)
  }

  func testParseAudioFlexibleOrderAndSafeMixOff() throws {
    let parsed = try Capa.parseAsRoot([
      "--audio", "system+++mic",
      "--safe-mix", "off",
    ])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertEqual(cmd.audioSpec, "system+++mic")
    XCTAssertEqual(cmd.safeMixMode, .off)
  }

  func testParseAudioMicOnly() throws {
    let parsed = try Capa.parseAsRoot(["--audio", "mic"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertEqual(cmd.audioSpec, "mic")
  }

  func testParseVFRFlag() throws {
    let parsed = try Capa.parseAsRoot(["--vfr"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertTrue(cmd.keepVFR)
  }

  func testUnknownArgumentThrows() {
    XCTAssertThrowsError(try Capa.parseAsRoot(["--nope"]))
  }

  func testParseProjectName() throws {
    let parsed = try Capa.parseAsRoot(["--project-name", "demo"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertEqual(cmd.projectName, "demo")
  }

  func testEmptyProjectNameThrows() {
    XCTAssertThrowsError(try Capa.parseAsRoot(["--project-name", "   "]))
  }

  func testNoOpenFlagParses() throws {
    let parsed = try Capa.parseAsRoot(["--no-open"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertTrue(cmd.noOpenFlag)
  }

  func testOpenFlagIsNotSupported() {
    XCTAssertThrowsError(try Capa.parseAsRoot(["--open"]))
  }
}
