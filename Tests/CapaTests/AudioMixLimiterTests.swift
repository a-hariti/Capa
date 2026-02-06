import AVFoundation
import CoreMedia
import XCTest
@testable import capa

final class AudioMixLimiterTests: XCTestCase {
  func testSafeMixLimiterKeepsMasterBelowThreshold() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let url = tempDir.appendingPathComponent("src.mov")
    try writeMovie(url: url, micAmplitude: 0.9, sysAmplitude: 0.9)

    try await PostProcess.addMasterAudioTrackIfNeeded(
      url: url,
      includeSystemAudio: true,
      includeMicrophone: true,
      mixConfig: PostProcess.MixConfig(microphoneGainDB: 0, systemGainDB: 0, safeMixLimiter: true)
    )

    let masterPeak = try await peakForAudioTrack(url: url, languageCode: "qaa")
    XCTAssertFalse(masterPeak.clipped)
    // Limiters can't guarantee decoded AAC sample peaks (inter-sample overs), but we should still see
    // a clear reduction vs a hard-clipped 0 dBFS mix.
    XCTAssertLessThanOrEqual(masterPeak.db, -0.5)
  }

  func testPerTrackGainAffectsSourceTracks() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let url = tempDir.appendingPathComponent("src.mov")
    try writeMovie(url: url, micAmplitude: 0.10, sysAmplitude: 0.10)

    try await PostProcess.addMasterAudioTrackIfNeeded(
      url: url,
      includeSystemAudio: true,
      includeMicrophone: true,
      mixConfig: PostProcess.MixConfig(microphoneGainDB: 6, systemGainDB: 0, safeMixLimiter: false)
    )

    let micPeak = try await peakForAudioTrack(url: url, languageCode: "qac")
    let sysPeak = try await peakForAudioTrack(url: url, languageCode: "qab")
    XCTAssertFalse(micPeak.clipped)
    XCTAssertFalse(sysPeak.clipped)
    XCTAssertGreaterThan(micPeak.db - sysPeak.db, 4.5)
  }
}

private func makeTempDir() throws -> URL {
  let base = URL(fileURLWithPath: NSTemporaryDirectory())
  let dir = base.appendingPathComponent("capa-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func writeMovie(url: URL, micAmplitude: Float, sysAmplitude: Float) throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

  // Minimal video track so PostProcess has something to passthrough.
  let vSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 160,
    AVVideoHeightKey: 90,
  ]
  let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
  vIn.expectsMediaDataInRealTime = false
  let vAttrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: 160,
    kCVPixelBufferHeightKey as String: 90,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
  ]
  let vAd = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: vAttrs)

  // Two PCM audio tracks (float interleaved), 48kHz stereo.
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
  let micIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
  micIn.expectsMediaDataInRealTime = false
  let sysIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
  sysIn.expectsMediaDataInRealTime = false

  for input in [vIn, micIn, sysIn] {
    guard writer.canAdd(input) else {
      throw NSError(domain: "AudioMixLimiterTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
    }
    writer.add(input)
  }

  guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "AudioMixLimiterTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "startWriting failed"])
  }
  writer.startSession(atSourceTime: .zero)

  // Video: a few frames.
  let vPTS: [CMTime] = [
    .zero,
    CMTime(seconds: 0.20, preferredTimescale: 600),
    CMTime(seconds: 0.40, preferredTimescale: 600),
  ]
  for (i, t) in vPTS.enumerated() {
    while !vIn.isReadyForMoreMediaData {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
    let pb = try makePixelBuffer(width: 160, height: 90, shade: UInt8(40 + i * 30))
    guard vAd.append(pb, withPresentationTime: t) else {
      throw writer.error ?? NSError(domain: "AudioMixLimiterTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "append video failed"])
    }
  }

  // Audio: 1 second in 1024-frame chunks.
  var audioPTS = CMTime.zero
  let framesPerChunk = 1024
  let chunkDur = CMTime(value: CMTimeValue(framesPerChunk), timescale: CMTimeScale(sampleRate))
  let chunks = Int((sampleRate / Double(framesPerChunk)).rounded(.up))
  for _ in 0..<chunks {
    while !micIn.isReadyForMoreMediaData || !sysIn.isReadyForMoreMediaData {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
    }
    let mic = try makePCMSampleBuffer(pts: audioPTS, frames: framesPerChunk, channels: channels, sampleRate: sampleRate, amplitude: micAmplitude)
    let sys = try makePCMSampleBuffer(pts: audioPTS, frames: framesPerChunk, channels: channels, sampleRate: sampleRate, amplitude: sysAmplitude)
    guard micIn.append(mic) else {
      throw writer.error ?? NSError(domain: "AudioMixLimiterTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "append mic failed"])
    }
    guard sysIn.append(sys) else {
      throw writer.error ?? NSError(domain: "AudioMixLimiterTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "append sys failed"])
    }
    audioPTS = audioPTS + chunkDur
  }

  vIn.markAsFinished()
  micIn.markAsFinished()
  sysIn.markAsFinished()

  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  if writer.status == .failed {
    throw writer.error ?? NSError(domain: "AudioMixLimiterTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
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
    throw NSError(domain: "AudioMixLimiterTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed"])
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

  guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
    throw NSError(domain: "AudioMixLimiterTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "No base address"])
  }
  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  memset(base, Int32(shade), bytesPerRow * height)
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
  let stDesc = CMAudioFormatDescriptionCreate(
    allocator: kCFAllocatorDefault,
    asbd: &asbd,
    layoutSize: 0,
    layout: nil,
    magicCookieSize: 0,
    magicCookie: nil,
    extensions: nil,
    formatDescriptionOut: &fmt
  )
  guard stDesc == noErr, let fmt else {
    throw NSError(domain: "AudioMixLimiterTests", code: Int(stDesc), userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format description"])
  }

  var samples = Array(repeating: Float(0), count: frames * channels)
  for i in 0..<samples.count { samples[i] = amplitude }
  let dataLen = samples.count * MemoryLayout<Float>.size

  var block: CMBlockBuffer?
  let stBlock = CMBlockBufferCreateWithMemoryBlock(
    allocator: kCFAllocatorDefault,
    memoryBlock: nil,
    blockLength: dataLen,
    blockAllocator: kCFAllocatorDefault,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: dataLen,
    flags: 0,
    blockBufferOut: &block
  )
  guard stBlock == kCMBlockBufferNoErr, let block else {
    throw NSError(domain: "AudioMixLimiterTests", code: Int(stBlock), userInfo: [NSLocalizedDescriptionKey: "Failed to create block buffer"])
  }

  samples.withUnsafeBytes { bytes in
    _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: dataLen)
  }

  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
    presentationTimeStamp: pts,
    decodeTimeStamp: .invalid
  )
  var sbuf: CMSampleBuffer?
  let st = CMSampleBufferCreateReady(
    allocator: kCFAllocatorDefault,
    dataBuffer: block,
    formatDescription: fmt,
    sampleCount: frames,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 0,
    sampleSizeArray: nil,
    sampleBufferOut: &sbuf
  )
  guard st == noErr, let sbuf else {
    throw NSError(domain: "AudioMixLimiterTests", code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Failed to create audio sample buffer"])
  }
  return sbuf
}

private func peakForAudioTrack(url: URL, languageCode: String) async throws -> AudioPeak {
  let asset = AVURLAsset(url: url)
  let tracks = try await asset.loadTracks(withMediaType: .audio)
  var chosen: AVAssetTrack?
  for t in tracks {
    let code = (try? await t.load(.languageCode)) ?? nil
    if code == languageCode {
      chosen = t
      break
    }
  }
  guard let track = chosen else {
    throw NSError(domain: "AudioMixLimiterTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing audio track \(languageCode)"])
  }

  let reader = try AVAssetReader(asset: asset)
  let pcm: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 48_000,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsNonInterleaved: false,
  ]
  let out = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
  out.alwaysCopiesSampleData = false
  guard reader.canAdd(out) else {
    throw NSError(domain: "AudioMixLimiterTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Cannot add reader output"])
  }
  reader.add(out)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "AudioMixLimiterTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"])
  }

  var best = AudioPeak(db: -80, clipped: false)
  while let sbuf = out.copyNextSampleBuffer() {
    if let p = AudioLevels.peak(from: sbuf) {
      if p.db > best.db { best.db = p.db }
      if p.clipped { best.clipped = true }
    }
  }
  return best
}
