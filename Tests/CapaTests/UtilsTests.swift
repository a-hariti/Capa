import XCTest
@testable import capa

final class UtilsTests: XCTestCase {
  func testSanitizeProjectName() {
    XCTAssertEqual(Utils.sanitizeProjectName("  hello  "), "hello")
    XCTAssertEqual(Utils.sanitizeProjectName(""), "capa")
    XCTAssertEqual(Utils.sanitizeProjectName("   "), "capa")
    XCTAssertEqual(Utils.sanitizeProjectName("my/project:name"), "my-project-name")
  }

  func testSlugifyFilenameStem() {
    XCTAssertEqual(Utils.slugifyFilenameStem("My Camera!"), "my-camera")
    XCTAssertEqual(Utils.slugifyFilenameStem("FaceTime HD Camera (Built-in)"), "facetime-hd-camera-built-in")
    XCTAssertEqual(Utils.slugifyFilenameStem(""), "camera")
    XCTAssertEqual(Utils.slugifyFilenameStem("!!!"), "camera")
    XCTAssertEqual(Utils.slugifyFilenameStem("---"), "camera")
  }

  func testAbbreviateHomePath() {
    let home = NSHomeDirectory()
    XCTAssertEqual(Utils.abbreviateHomePath(home), "~")
    XCTAssertEqual(Utils.abbreviateHomePath(home + "/Downloads"), "~/Downloads")
    XCTAssertEqual(Utils.abbreviateHomePath("/usr/local/bin"), "/usr/local/bin")
  }

  func testEnsureUniqueProjectDir() throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    let baseName = "test-project"
    let (name1, dir1) = Utils.ensureUniqueProjectDir(parent: tempDir, name: baseName, expectedFilenames: [])
    XCTAssertEqual(name1, baseName)
    XCTAssertEqual(dir1.lastPathComponent, baseName)

    // Create a file in it to make it non-empty
    try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
    try "hello".write(to: dir1.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    let (name2, dir2) = Utils.ensureUniqueProjectDir(parent: tempDir, name: baseName, expectedFilenames: [])
    XCTAssertEqual(name2, "\(baseName)-2")
    XCTAssertEqual(dir2.lastPathComponent, "\(baseName)-2")
  }
}
