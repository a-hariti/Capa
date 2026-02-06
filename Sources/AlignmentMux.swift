@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Adds the screen recording's "Master (Mixed)" audio track to a secondary recording (e.g. camera),
/// so editors can align clips using a shared reference mix.
///
/// The secondary file keeps its own audio as the first track; the master mix is appended as another track.
enum AlignmentMux {
  static func addMasterAlignmentTrack(cameraURL: URL, screenURL: URL) async throws {
    let cameraAsset = AVURLAsset(url: cameraURL)
    let screenAsset = AVURLAsset(url: screenURL)

    let screenAudio = try await screenAsset.loadTracks(withMediaType: .audio)
    let master = try await findMasterTrack(in: screenAudio)
    guard let master else { return } // no master; nothing to do

    let tmpURL = cameraURL.deletingLastPathComponent()
      .appendingPathComponent(".capa-align-\(UUID().uuidString).mov")

    try await rewrite(cameraAsset: cameraAsset, screenAsset: screenAsset, masterTrack: master, outputURL: tmpURL)

    let fm = FileManager.default
    _ = try? fm.replaceItemAt(cameraURL, withItemAt: tmpURL, backupItemName: nil, options: .usingNewMetadataOnly)
  }

  // MARK: - Implementation

  private static func findMasterTrack(in tracks: [AVAssetTrack]) async throws -> AVAssetTrack? {
    for t in tracks {
      let tag = (try? await t.load(.extendedLanguageTag)) ?? nil
      let code = (try? await t.load(.languageCode)) ?? nil
      if tag == "qaa-x-capa-master" || code == "qaa" {
        return t
      }
    }
    return nil
  }

  private static func rewrite(cameraAsset: AVAsset, screenAsset: AVAsset, masterTrack: AVAssetTrack, outputURL: URL) async throws {
    let cameraReader = try AVAssetReader(asset: cameraAsset)
    let screenReader = try AVAssetReader(asset: screenAsset)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

    struct Pipe {
      let out: AVAssetReaderTrackOutput
      let input: AVAssetWriterInput
      let title: String
      var seed: CMSampleBuffer?
      var done = false
      var signaled = false
    }

    // Video passthrough (preserve all video tracks).
    var pipes: [Pipe] = []

    let videoTracks = try await cameraAsset.loadTracks(withMediaType: .video)
    for (i, t) in videoTracks.enumerated() {
      let title = (videoTracks.count == 1) ? "Camera" : "Video \(i + 1)"

      let out = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
      out.alwaysCopiesSampleData = false
      guard cameraReader.canAdd(out) else {
        throw NSError(domain: "AlignmentMux", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video reader output"])
      }
      cameraReader.add(out)

      let hint = (try await t.load(.formatDescriptions)).first
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
      input.expectsMediaDataInRealTime = false
      input.transform = try await t.load(.preferredTransform)
      input.metadata = [trackTitle(title)]
      guard writer.canAdd(input) else {
        throw NSError(domain: "AlignmentMux", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video writer input"])
      }
      writer.add(input)

      pipes.append(Pipe(out: out, input: input, title: title))
    }

    // Preserve timecode tracks (passthrough).
    let timecodeTracks = try await cameraAsset.loadTracks(withMediaType: .timecode)
    var timecodeInputs: [AVAssetWriterInput] = []
    if !timecodeTracks.isEmpty {
      for (i, t) in timecodeTracks.enumerated() {
        let out = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
        out.alwaysCopiesSampleData = false
        if cameraReader.canAdd(out) { cameraReader.add(out) }

        let hint = (try await t.load(.formatDescriptions)).first
        let input = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: hint)
        input.expectsMediaDataInRealTime = false
        input.metadata = [trackTitle(timecodeTracks.count == 1 ? "Timecode" : "Timecode \(i + 1)")]
        input.languageCode = (try? await t.load(.languageCode)) ?? nil
        input.extendedLanguageTag = (try? await t.load(.extendedLanguageTag)) ?? nil
        if writer.canAdd(input) {
          writer.add(input)
          timecodeInputs.append(input)
          pipes.append(Pipe(out: out, input: input, title: "Timecode"))
        }
      }

      if let tcIn = timecodeInputs.first {
        for i in 0..<min(videoTracks.count, pipes.count) {
          if pipes[i].input.mediaType == .video {
            pipes[i].input.addTrackAssociation(withTrackOf: tcIn, type: AVAssetTrack.AssociationType.timecode.rawValue)
          }
        }
      }
    }

    // Existing audio passthrough (keep secondary recording's own audio first).
    let audioTracks = try await cameraAsset.loadTracks(withMediaType: .audio)
    for (i, t) in audioTracks.enumerated() {
      let title = (audioTracks.count == 1) ? "Microphone" : "Audio \(i + 1)"

      let out = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
      out.alwaysCopiesSampleData = false
      if cameraReader.canAdd(out) { cameraReader.add(out) }

      let hint = (try await t.load(.formatDescriptions)).first
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
      input.expectsMediaDataInRealTime = false
      input.metadata = [trackTitle(title)]
      input.languageCode = (try? await t.load(.languageCode)) ?? nil
      input.extendedLanguageTag = (try? await t.load(.extendedLanguageTag)) ?? nil
      guard writer.canAdd(input) else {
        throw NSError(domain: "AlignmentMux", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio writer input"])
      }
      writer.add(input)

      pipes.append(Pipe(out: out, input: input, title: title))
    }

    // Add master audio from the screen recording.
    do {
      let out = AVAssetReaderTrackOutput(track: masterTrack, outputSettings: nil)
      out.alwaysCopiesSampleData = false
      guard screenReader.canAdd(out) else {
        throw NSError(domain: "AlignmentMux", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot add master audio reader output"])
      }
      screenReader.add(out)

      let hint = (try await masterTrack.load(.formatDescriptions)).first
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
      input.expectsMediaDataInRealTime = false
      input.metadata = [trackTitle("Master (Mixed)")]
      input.languageCode = "qaa"
      input.extendedLanguageTag = "qaa-x-capa-master"
      guard writer.canAdd(input) else {
        throw NSError(domain: "AlignmentMux", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot add master audio writer input"])
      }
      writer.add(input)

      pipes.append(Pipe(out: out, input: input, title: "Master (Mixed)"))
    }

    guard cameraReader.startReading() else {
      throw cameraReader.error ?? NSError(domain: "AlignmentMux", code: 7, userInfo: [NSLocalizedDescriptionKey: "Camera reader failed to start"])
    }
    guard screenReader.startReading() else {
      throw screenReader.error ?? NSError(domain: "AlignmentMux", code: 10, userInfo: [NSLocalizedDescriptionKey: "Screen reader failed to start"])
    }
    guard writer.startWriting() else {
      throw writer.error ?? NSError(domain: "AlignmentMux", code: 8, userInfo: [NSLocalizedDescriptionKey: "Writer failed to start"])
    }

    // Seed all pipes to determine a common session start time.
    var minPTS: CMTime?
    for i in pipes.indices {
      if let first = pipes[i].out.copyNextSampleBuffer() {
        pipes[i].seed = first
        let pts = CMSampleBufferGetPresentationTimeStamp(first)
        if let m = minPTS {
          if pts < m { minPTS = pts }
        } else {
          minPTS = pts
        }
      }
    }
    guard let startPTS = minPTS else {
      throw NSError(domain: "AlignmentMux", code: 9, userInfo: [NSLocalizedDescriptionKey: "No samples to mux"])
    }

    writer.startSession(atSourceTime: startPTS)

    let q = DispatchQueue(label: "capa.alignmux")

    final class State: @unchecked Sendable {
      let writer: AVAssetWriter
      let cameraReader: AVAssetReader
      let screenReader: AVAssetReader
      var pipes: [Pipe]
      var failure: Error?

      init(writer: AVAssetWriter, cameraReader: AVAssetReader, screenReader: AVAssetReader, pipes: [Pipe]) {
        self.writer = writer
        self.cameraReader = cameraReader
        self.screenReader = screenReader
        self.pipes = pipes
      }

      func failIfNeeded() -> Bool {
        if failure != nil { return true }
        if writer.status == .failed {
          failure = writer.error ?? NSError(domain: "AlignmentMux", code: 20, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
          return true
        }
        if cameraReader.status == .failed {
          failure = cameraReader.error ?? NSError(domain: "AlignmentMux", code: 21, userInfo: [NSLocalizedDescriptionKey: "Camera reader failed"])
          return true
        }
        if screenReader.status == .failed {
          failure = screenReader.error ?? NSError(domain: "AlignmentMux", code: 24, userInfo: [NSLocalizedDescriptionKey: "Screen reader failed"])
          return true
        }
        return false
      }

      func step(i: Int) {
        if pipes[i].done { return }
        if failIfNeeded() {
          pipes[i].input.markAsFinished()
          pipes[i].done = true
          return
        }

        while pipes[i].input.isReadyForMoreMediaData {
          if failIfNeeded() { break }
          let sbuf: CMSampleBuffer?
          if let seed = pipes[i].seed {
            sbuf = seed
            pipes[i].seed = nil
          } else {
            sbuf = pipes[i].out.copyNextSampleBuffer()
          }
          guard let sbuf else {
            pipes[i].input.markAsFinished()
            pipes[i].done = true
            return
          }
          if !pipes[i].input.append(sbuf) {
            failure = writer.error ?? NSError(domain: "AlignmentMux", code: 22, userInfo: [NSLocalizedDescriptionKey: "Append failed (\(pipes[i].title))"])
            pipes[i].input.markAsFinished()
            pipes[i].done = true
            return
          }
        }
      }
    }

    let state = State(writer: writer, cameraReader: cameraReader, screenReader: screenReader, pipes: pipes)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
      final class AwaitState: @unchecked Sendable {
        let cont: CheckedContinuation<Void, any Error>
        let state: State
        var remaining: Int
        var finished = false

        init(cont: CheckedContinuation<Void, any Error>, state: State, remaining: Int) {
          self.cont = cont
          self.state = state
          self.remaining = remaining
        }
      }

      let awaitState = AwaitState(cont: cont, state: state, remaining: state.pipes.count)

      let finish: @Sendable (Error?) -> Void = { error in
        guard !awaitState.finished else { return }
        awaitState.finished = true
        if let error {
          awaitState.cont.resume(throwing: error)
        } else {
          awaitState.cont.resume(returning: ())
        }
      }

      let partDone: @Sendable () -> Void = {
        awaitState.remaining -= 1
        if awaitState.remaining <= 0 {
          finish(awaitState.state.failure)
        }
      }

      for i in 0..<state.pipes.count {
        state.pipes[i].input.requestMediaDataWhenReady(on: q) {
          state.step(i: i)
          if let err = state.failure { finish(err); return }
          if state.pipes[i].done && !state.pipes[i].signaled {
            state.pipes[i].signaled = true
            partDone()
          }
        }
      }
    }

    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      writer.finishWriting { cont.resume(returning: ()) }
    }

    if writer.status == .failed {
      throw writer.error ?? NSError(domain: "AlignmentMux", code: 23, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
    }
  }

  private static func trackTitle(_ title: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = .quickTimeUserDataTrackName
    item.value = title as NSString
    item.dataType = kCMMetadataBaseDataType_UTF8 as String
    return item
  }
}
