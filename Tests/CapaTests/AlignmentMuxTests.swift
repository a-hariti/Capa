import AVFoundation
import CoreMedia
import XCTest
@testable import capa

final class AlignmentMuxTests: XCTestCase {
  func testCameraGetsMasterAsSecondAudioTrack() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let screenURL = tempDir.appendingPathComponent("screen.mov")
    let cameraURL = tempDir.appendingPathComponent("camera.mov")

    // Screen: 1 video + 2 audio (mic + system), so PostProcess will generate master.
    try writeMovie(url: screenURL, videoSize: (160, 90), audioTracks: 2)
    // Camera: 1 video + 1 audio (mic).
    try writeMovie(url: cameraURL, videoSize: (80, 60), audioTracks: 1)

    try await PostProcess.addMasterAudioTrackIfNeeded(
      url: screenURL,
      includeSystemAudio: true,
      includeMicrophone: true
    )
    try await AlignmentMux.addMasterAlignmentTrack(cameraURL: cameraURL, screenURL: screenURL)

    let cam = AVURLAsset(url: cameraURL)
    let a = try await cam.loadTracks(withMediaType: .audio)
    XCTAssertEqual(a.count, 2)

    let tag0 = try? await a[0].load(.extendedLanguageTag)
    let tag1 = try? await a[1].load(.extendedLanguageTag)
    XCTAssertEqual(tag0 ?? "", "qac-x-capa-mic")
    XCTAssertEqual(tag1 ?? "", "qaa-x-capa-master")
  }
}

private func makeTempDir() throws -> URL {
  let base = URL(fileURLWithPath: NSTemporaryDirectory())
  let dir = base.appendingPathComponent("capa-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func writeMovie(url: URL, videoSize: (Int, Int), audioTracks: Int) throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

  let vSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: videoSize.0,
    AVVideoHeightKey: videoSize.1,
  ]
  let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
  vIn.expectsMediaDataInRealTime = false
  let vAttrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: videoSize.0,
    kCVPixelBufferHeightKey as String: videoSize.1,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]
  let vAd = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: vAttrs)
  guard writer.canAdd(vIn) else { throw NSError(domain: "AlignmentMuxTests", code: 1) }
  writer.add(vIn)

  let sampleRate: Double = 48_000
  let channels = 2
  let aSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: channels,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
  ]

  var aInputs: [AVAssetWriterInput] = []
  for idx in 0..<audioTracks {
    let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
    aIn.expectsMediaDataInRealTime = false
    if idx == 0 {
      aIn.metadata = [trackTitle("Microphone")]
      aIn.languageCode = "qac"
      aIn.extendedLanguageTag = "qac-x-capa-mic"
    } else if idx == 1 {
      aIn.metadata = [trackTitle("System Audio")]
      aIn.languageCode = "qab"
      aIn.extendedLanguageTag = "qab-x-capa-system"
    } else {
      aIn.metadata = [trackTitle("Audio \(idx + 1)")]
    }
    guard writer.canAdd(aIn) else { throw NSError(domain: "AlignmentMuxTests", code: 2) }
    writer.add(aIn)
    aInputs.append(aIn)
  }

  guard writer.startWriting() else { throw writer.error ?? NSError(domain: "AlignmentMuxTests", code: 3) }
  writer.startSession(atSourceTime: .zero)

  // Video frames.
  let pts: [CMTime] = [
    .zero,
    CMTime(seconds: 0.05, preferredTimescale: 600),
    CMTime(seconds: 0.20, preferredTimescale: 600),
  ]
  for (i, t) in pts.enumerated() {
    while !vIn.isReadyForMoreMediaData {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
    let pb = try makePixelBuffer(width: videoSize.0, height: videoSize.1, shade: UInt8(40 + i * 40))
    guard vAd.append(pb, withPresentationTime: t) else {
      throw writer.error ?? NSError(domain: "AlignmentMuxTests", code: 4)
    }
  }

  // Audio: write a few chunks on each track.
  var audioPTS = CMTime.zero
  let framesPerChunk = 1024
  let chunkDur = CMTime(value: CMTimeValue(framesPerChunk), timescale: CMTimeScale(sampleRate))
  for _ in 0..<8 {
    for (idx, aIn) in aInputs.enumerated() {
      while !aIn.isReadyForMoreMediaData {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
      }
      let amp: Float = (idx == 0) ? 0.05 : 0.20
      let sbuf = try makePCMSampleBuffer(pts: audioPTS, frames: framesPerChunk, channels: channels, sampleRate: sampleRate, amplitude: amp)
      guard aIn.append(sbuf) else {
        throw writer.error ?? NSError(domain: "AlignmentMuxTests", code: 5)
      }
    }
    audioPTS = audioPTS + chunkDur
  }

  vIn.markAsFinished()
  for aIn in aInputs { aIn.markAsFinished() }

  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()
  if writer.status == .failed {
    throw writer.error ?? NSError(domain: "AlignmentMuxTests", code: 6)
  }
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
    throw NSError(domain: "AlignmentMuxTests", code: 10)
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
  guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    throw NSError(domain: "AlignmentMuxTests", code: 11)
  }
  memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
  return pixelBuffer
}

private func makePCMSampleBuffer(
  pts: CMTime,
  frames: Int,
  channels: Int,
  sampleRate: Double,
  amplitude: Float
) throws -> CMSampleBuffer {
  var asbd = AudioStreamBasicDescription(
    mSampleRate: sampleRate,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: UInt32(channels * MemoryLayout<Float>.size),
    mFramesPerPacket: 1,
    mBytesPerFrame: UInt32(channels * MemoryLayout<Float>.size),
    mChannelsPerFrame: UInt32(channels),
    mBitsPerChannel: 32,
    mReserved: 0
  )

  var fmt: CMAudioFormatDescription?
  let stDesc = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
  guard stDesc == noErr, let fmt else { throw NSError(domain: "AlignmentMuxTests", code: 30) }

  var samples = Array(repeating: Float(0), count: frames * channels)
  for i in 0..<frames {
    let v = amplitude * sin(Float(i) * 0.01)
    for c in 0..<channels { samples[i * channels + c] = v }
  }

  let dataLen = samples.count * MemoryLayout<Float>.size
  var block: CMBlockBuffer?
  let stBlock = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataLen, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: dataLen, flags: 0, blockBufferOut: &block)
  guard stBlock == kCMBlockBufferNoErr, let block else { throw NSError(domain: "AlignmentMuxTests", code: 31) }

  samples.withUnsafeBytes { bytes in
    _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: dataLen)
  }

  let dur = CMTime(value: 1, timescale: CMTimeScale(sampleRate))
  var timing = CMSampleTimingInfo(duration: dur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
  var sbuf: CMSampleBuffer?
  let st = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: fmt, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sbuf)
  guard st == noErr, let sbuf else { throw NSError(domain: "AlignmentMuxTests", code: 32) }
  return sbuf
}

private func trackTitle(_ title: String) -> AVMetadataItem {
  let item = AVMutableMetadataItem()
  item.identifier = .quickTimeUserDataTrackName
  item.value = title as NSString
  item.dataType = kCMMetadataBaseDataType_UTF8 as String
  return item
}
