import AVFoundation
import CoreMedia
import XCTest
@testable import capa

final class TimecodePreservationTests: XCTestCase {
  func testTimecodeSurvivesCFRRewrite() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let url = tempDir.appendingPathComponent("cfr-tc.mov")
    try await writeTinyVideoWithTimecode(url: url)

    try await VideoCFR.rewriteInPlace(url: url, fps: 60)

    let asset = AVURLAsset(url: url)
    let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)
    XCTAssertEqual(timecodeTracks.count, 1)

    let reader = try AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: timecodeTracks[0], outputSettings: nil)
    out.alwaysCopiesSampleData = false
    XCTAssertTrue(reader.canAdd(out))
    reader.add(out)
    XCTAssertTrue(reader.startReading())
    XCTAssertNotNil(out.copyNextSampleBuffer())
  }
}

private func writeTinyVideoWithTimecode(url: URL) async throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

  let vSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 96,
    AVVideoHeightKey: 64,
  ]
  let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
  videoIn.expectsMediaDataInRealTime = false
  XCTAssertTrue(writer.canAdd(videoIn))
  writer.add(videoIn)

  let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: 96,
    kCVPixelBufferHeightKey as String: 64,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: attrs)

  let tz = TimeZone(secondsFromGMT: 0)!
  let sync = TimecodeSyncContext(syncID: "sync-preserve", startDate: Date(timeIntervalSince1970: 12_345), fps: 60, timeZone: tz)
  let tcIn = sync.makeTimecodeWriterInput()
  XCTAssertTrue(writer.canAdd(tcIn))
  writer.add(tcIn)
  videoIn.addTrackAssociation(withTrackOf: tcIn, type: AVAssetTrack.AssociationType.timecode.rawValue)

  XCTAssertTrue(writer.startWriting())
  writer.startSession(atSourceTime: .zero)

  let pts: [CMTime] = [
    .zero,
    CMTime(value: 1, timescale: 60),
    CMTime(value: 2, timescale: 60),
  ]
  for (idx, t) in pts.enumerated() {
    while !videoIn.isReadyForMoreMediaData {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    let pb = try makePixelBuffer(width: 96, height: 64, shade: UInt8(30 + idx * 50))
    XCTAssertTrue(adaptor.append(pb, withPresentationTime: t))
  }

  let tcSample = try sync.makeTimecodeSampleBuffer(presentationTimeStamp: .zero, duration: CMTime(value: 3, timescale: 60))
  XCTAssertTrue(tcIn.append(tcSample))

  videoIn.markAsFinished()
  tcIn.markAsFinished()
  await withCheckedContinuation { cont in
    writer.finishWriting { cont.resume() }
  }
  XCTAssertEqual(writer.status, .completed)
}

private func makeTempDir() throws -> URL {
  let base = URL(fileURLWithPath: NSTemporaryDirectory())
  let dir = base.appendingPathComponent("capa-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func makePixelBuffer(width: Int, height: Int, shade: UInt8) throws -> CVPixelBuffer {
  var pb: CVPixelBuffer?
  let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]
  let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
  guard status == kCVReturnSuccess, let pixelBuffer = pb else {
    throw NSError(domain: "TimecodePreservationTests", code: 1)
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
  guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    throw NSError(domain: "TimecodePreservationTests", code: 2)
  }
  memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
  return pixelBuffer
}
