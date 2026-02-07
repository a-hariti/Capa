import XCTest
@testable import capa

final class OutputDirectoryTests: XCTestCase {
  func testDefaultRecordingDirectory() {
    let url = Capa.defaultRecordingDirectory

    // When building/testing via SwiftPM, DEBUG is usually defined, the #else path is hit with test -c release.
#if DEBUG
    let expectedSuffix = "/recs"
    XCTAssertTrue(url.path.hasSuffix(expectedSuffix), "Expected path to end with \(expectedSuffix), but got \(url.path)")
#else
    let home = NSHomeDirectory()
    let expected = home + "/Movies/Capa"
    XCTAssertEqual(url.path, expected)
#endif
  }
}
