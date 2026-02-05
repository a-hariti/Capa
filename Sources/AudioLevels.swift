import AudioToolbox
import CoreMedia

enum AudioLevels {
  /// Computes a peak level in dBFS (0 dBFS is full-scale).
  /// Returns `nil` if the sample buffer doesn't contain readable PCM.
  static func peakDBFS(from sampleBuffer: CMSampleBuffer) -> Float? {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
    guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee else { return nil }

    var block: CMBlockBuffer?
    var abl = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer())
    var sizeNeeded: Int = 0

    let st = withUnsafeMutablePointer(to: &abl) { ablPtr in
      withUnsafeMutablePointer(to: &block) { blockPtr in
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
          sampleBuffer,
          bufferListSizeNeededOut: &sizeNeeded,
          bufferListOut: ablPtr,
          bufferListSize: MemoryLayout<AudioBufferList>.size,
          blockBufferAllocator: kCFAllocatorDefault,
          blockBufferMemoryAllocator: kCFAllocatorDefault,
          flags: 0,
          blockBufferOut: blockPtr
        )
      }
    }
    guard st == noErr else { return nil }
    guard abl.mNumberBuffers >= 1 else { return nil }
    let buf = abl.mBuffers
    guard let mData = buf.mData, buf.mDataByteSize > 0 else { return nil }

    let eps: Float = 1e-9
    var peak: Float = 0

    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    if isFloat {
      let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
      let p = mData.bindMemory(to: Float.self, capacity: n)
      for i in 0..<n {
        peak = max(peak, abs(p[i]))
      }
    } else {
      // Most common non-float case is signed Int16 PCM.
      let n = Int(buf.mDataByteSize) / MemoryLayout<Int16>.size
      let p = mData.bindMemory(to: Int16.self, capacity: n)
      for i in 0..<n {
        peak = max(peak, abs(Float(p[i])) / 32768.0)
      }
    }

    return 20.0 * log10(max(eps, peak))
  }
}

