import AVFoundation
import CoreMedia
import XCTest
@testable import capa

final class VideoCFRTests: XCTestCase {
  func testRewriteToCFR60() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let srcURL = tempDir.appendingPathComponent("vfr.mov")
    let outURL = srcURL

    let pts: [CMTime] = [
      .zero,
      CMTime(seconds: 0.05, preferredTimescale: 600),
      CMTime(seconds: 0.20, preferredTimescale: 600)
    ]

    try writeVFRMovie(url: srcURL, pts: pts, size: (160, 90))

    try await VideoCFR.rewriteInPlace(url: outURL, fps: 60)

    let asset = AVURLAsset(url: outURL)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      XCTFail("Missing video track after CFR rewrite")
      return
    }

    let reader = try AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    out.alwaysCopiesSampleData = false
    XCTAssertTrue(reader.canAdd(out))
    reader.add(out)
    XCTAssertTrue(reader.startReading())

    var secs: [Double] = []
    while let sbuf = out.copyNextSampleBuffer() {
      let s = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sbuf))
      if s.isFinite {
        secs.append(s)
      }
    }

    XCTAssertGreaterThan(secs.count, 2)

    let expected = 1.0 / 60.0
    var deltas: [Double] = []
    for i in 1..<min(secs.count, 240) {
      let dt = secs[i] - secs[i - 1]
      if dt > 0 {
        deltas.append(dt)
      }
    }

    XCTAssertGreaterThan(deltas.count, 3)
    for dt in deltas.prefix(120) {
      XCTAssertLessThan(abs(dt - expected), 0.002, "Frame delta drifted: \(dt)")
    }
  }
}

private func makeTempDir() throws -> URL {
  let base = URL(fileURLWithPath: NSTemporaryDirectory())
  let dir = base.appendingPathComponent("capa-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func writeVFRMovie(url: URL, pts: [CMTime], size: (Int, Int)) throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

  let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: size.0,
    AVVideoHeightKey: size.1
  ]

  let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
  input.expectsMediaDataInRealTime = false
  let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: size.0,
    kCVPixelBufferHeightKey as String: size.1,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
  ]
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

  guard writer.canAdd(input) else {
    throw NSError(domain: "VideoCFRTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
  }
  writer.add(input)

  guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "VideoCFRTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "startWriting failed"])
  }
  writer.startSession(atSourceTime: .zero)

  for (i, t) in pts.enumerated() {
    while !input.isReadyForMoreMediaData {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    let pb = try makePixelBuffer(width: size.0, height: size.1, shade: UInt8(40 + i * 20))
    guard adaptor.append(pb, withPresentationTime: t) else {
      throw writer.error ?? NSError(domain: "VideoCFRTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "append failed"])
    }
  }

  input.markAsFinished()
  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  if writer.status == .failed {
    throw writer.error ?? NSError(domain: "VideoCFRTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "finishWriting failed"])
  }
}

private func makePixelBuffer(width: Int, height: Int, shade: UInt8) throws -> CVPixelBuffer {
  var pb: CVPixelBuffer?
  let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
  ]
  let status = CVPixelBufferCreate(
    kCFAllocatorDefault,
    width,
    height,
    kCVPixelFormatType_32BGRA,
    attrs as CFDictionary,
    &pb
  )
  guard status == kCVReturnSuccess, let pixelBuffer = pb else {
    throw NSError(domain: "VideoCFRTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed"])
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

  guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    throw NSError(domain: "VideoCFRTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "No base address"])
  }

  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let total = bytesPerRow * height
  memset(base, Int32(shade), total)
  return pixelBuffer
}
