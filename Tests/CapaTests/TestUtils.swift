import AVFoundation
import CoreMedia
import Foundation

enum TestUtils {
  static func makePCMSampleBuffer(
    pts: CMTime,
    frames: Int,
    channels: Int,
    sampleRate: Double,
    amplitude: Float,
    isSine: Bool = true
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
    guard stDesc == noErr, let fmt else { throw NSError(domain: "TestUtils", code: 30) }

    var samples = Array(repeating: Float(0), count: frames * channels)
    for i in 0..<frames {
      let v = isSine ? (amplitude * sin(Float(i) * 0.01)) : amplitude
      for c in 0..<channels { samples[i * channels + c] = v }
    }

    let dataLen = samples.count * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    let stBlock = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataLen, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: dataLen, flags: 0, blockBufferOut: &block)
    guard stBlock == kCMBlockBufferNoErr, let block else { throw NSError(domain: "TestUtils", code: 31) }

    samples.withUnsafeBytes { bytes in
      _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: dataLen)
    }

    let dur = CMTime(value: 1, timescale: CMTimeScale(sampleRate))
    var timing = CMSampleTimingInfo(duration: dur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var sbuf: CMSampleBuffer?
    let st = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: fmt, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sbuf)
    guard st == noErr, let sbuf else { throw NSError(domain: "TestUtils", code: 32) }
    return sbuf
  }
}
