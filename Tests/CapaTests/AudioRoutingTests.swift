import XCTest
@testable import capa

final class AudioRoutingTests: XCTestCase {
  func testParsesMicSystemInAnyOrder() throws {
    let a = try AudioRouting.parse("mic+system")
    let b = try AudioRouting.parse("system+++mic")
    XCTAssertEqual(a, .micAndSystem)
    XCTAssertEqual(b, .micAndSystem)
  }

  func testParsesNone() throws {
    XCTAssertEqual(try AudioRouting.parse("none"), .none)
  }

  func testRejectsUnknownToken() {
    XCTAssertThrowsError(try AudioRouting.parse("music"))
  }
}
