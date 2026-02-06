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

  func testParseSystemAudioAndFPS() throws {
    let parsed = try Capa.parseAsRoot(["--system-audio", "--fps", "30"])
    guard let cmd = parsed as? Capa else {
      return XCTFail("Failed to parse as Capa")
    }
    XCTAssertTrue(cmd.systemAudioFlag)
    XCTAssertEqual(cmd.fps, 30)
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
