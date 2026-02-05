import XCTest
@testable import capa

final class GeometryTests: XCTestCase {
  func testComputeCaptureGeometryFallbackOnZeroRect() {
    let geom = computeCaptureGeometry(rect: .zero, scale: 2.0, fallbackLogicalSize: (100, 80))
    XCTAssertEqual(geom.pixelWidth, 100)
    XCTAssertEqual(geom.pixelHeight, 80)
    XCTAssertEqual(geom.pointPixelScale, 1.0)
  }

  func testComputeCaptureGeometryScale() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
    let geom = computeCaptureGeometry(rect: rect, scale: 2.0, fallbackLogicalSize: (1, 1))
    XCTAssertEqual(geom.pixelWidth, 200)
    XCTAssertEqual(geom.pixelHeight, 100)
    XCTAssertEqual(geom.pointPixelScale, 2.0)
  }
}
