import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// All AVAssetWriter state and sample access stays on one serial queue.
/// Kept separate from the capture service so real encoding can be verified with synthetic samples.
final class RecordingWriter: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    // Encoder discovery/startWriting may wait on native media services or storage.
    // Keep that work off the UI actor, including before the first sample arrives.
    static let preparationQueue = DispatchQueue(label: "app.ezsnapshot.recording.prepare", qos: .userInitiated)

    static func prepare(url: URL, width: Int, height: Int, fps: Int, captureAudio: Bool) async throws -> RecordingWriter {
        try await withCheckedThrowingContinuation { continuation in
            preparationQueue.async {
                do {
                    continuation.resume(returning: try RecordingWriter(url: url, width: width, height: height,
                                                                        fps: fps, captureAudio: captureAudio))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    let queue = DispatchQueue(label: "app.ezsnapshot.recording.writer", qos: .userInitiated)
    var onStreamFailure: ((Error) -> Void)?
    var onWriterFailure: ((Error) -> Void)?

    private let url: URL
    private let width: Int
    private let height: Int
    private let frameInterval: CMTime
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var firstSourceTime: CMTime?
    private var firstHostTime: CMTime?
    private var lastVideoTime = CMTime.invalid
    private var lastVideo: CMSampleBuffer?
    private var pendingVideo: CMSampleBuffer?
    private var pendingAudio: [CMSampleBuffer] = []
    private var lastAudioTime = CMTime.invalid
    private var audioWasWritten = false
    private var acceptingSamples = true
    private var writerFailure: Error?
    private var failureWasReported = false
    private var retryTimer: DispatchSourceTimer?
    private var finishing = false

    init(url: URL, width: Int, height: Int, fps: Int, captureAudio: Bool) throws {
        self.url = url
        self.width = width
        self.height = height
        frameInterval = CMTime(value: 1, timescale: Int32(fps))
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        assetWriter.shouldOptimizeForNetworkUse = true
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(40_000_000, max(2_000_000, width * height * fps / 5)),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(videoInput) else {
            throw RecordingServiceError.failed("macOS could not configure the H.264 video encoder.")
        }
        assetWriter.add(videoInput)
        if captureAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else {
                throw RecordingServiceError.failed("macOS could not configure the AAC audio encoder.")
            }
            assetWriter.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        super.init()
        guard assetWriter.startWriting() else {
            let error = assetWriter.error ?? RecordingServiceError.failed("The recording file could not be opened.")
            assetWriter.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.drainPendingSamples() }
        retryTimer = timer
        timer.resume()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard acceptingSamples, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let value = attachments.first?[.status] as? NSNumber,
                  let status = SCFrameStatus(rawValue: value.intValue),
                  status == .complete || status == .started,
                  CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            appendVideo(sampleBuffer)
        case .audio: appendAudio(sampleBuffer)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The main-actor service suppresses duplicates and decides whether to save a partial clip.
        onStreamFailure?(error)
    }

    /// Called on queue. A single latest pending frame bounds memory under encoder backpressure.
    func appendVideo(_ sample: CMSampleBuffer) {
        guard acceptingSamples, !finishing, writerFailure == nil,
              CMSampleBufferGetImageBuffer(sample) != nil else { return }
        pendingVideo = sample
        drainPendingSamples()
    }

    /// Called on queue. Audio may arrive before the first video frame; preserve a bounded startup buffer.
    func appendAudio(_ sample: CMSampleBuffer) {
        guard acceptingSamples, !finishing, writerFailure == nil, audioInput != nil else { return }
        pendingAudio.append(sample)
        if pendingAudio.count > 100 { pendingAudio.removeFirst(pendingAudio.count - 100) }
        drainPendingSamples()
    }

    private func drainPendingSamples() {
        guard writerFailure == nil, !finishing else { return }
        if assetWriter.status == .failed {
            fail(assetWriter.error ?? RecordingServiceError.failed("The video encoder stopped unexpectedly."))
            return
        }
        if let sample = pendingVideo {
            let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
            guard sourceTime.isValid, sourceTime.isNumeric else { pendingVideo = nil; return }
            if firstSourceTime == nil {
                firstSourceTime = sourceTime
                firstHostTime = CMClockGetTime(CMClockGetHostTimeClock())
                assetWriter.startSession(atSourceTime: .zero)
            }
            // Starting the session must precede the readiness check. A native encoder
            // may remain not-ready until it has an active timeline.
            guard videoInput.isReadyForMoreMediaData else { return }
            pendingVideo = nil
            let relativeTime = CMTimeSubtract(sourceTime, firstSourceTime!)
            if relativeTime >= .zero, !lastVideoTime.isValid || relativeTime > lastVideoTime {
                do {
                    let retimed = try Self.retimed(sample, to: relativeTime)
                    guard videoInput.append(retimed) else {
                        fail(assetWriter.error ?? RecordingServiceError.failed("A video frame could not be encoded."))
                        return
                    }
                    lastVideoTime = relativeTime
                    lastVideo = retimed
                } catch { fail(error); return }
            }
        }
        guard let sourceStart = firstSourceTime, let audioInput else { return }
        while !pendingAudio.isEmpty, audioInput.isReadyForMoreMediaData {
            let sample = pendingAudio.removeFirst()
            let relativeTime = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), sourceStart)
            // Discard pre-video audio instead of producing negative MP4 timestamps.
            guard relativeTime.isValid, relativeTime.isNumeric, relativeTime >= .zero,
                  !lastAudioTime.isValid || relativeTime > lastAudioTime else { continue }
            do {
                let retimed = try Self.retimed(sample, to: relativeTime)
                guard audioInput.append(retimed) else {
                    fail(assetWriter.error ?? RecordingServiceError.failed("The system audio could not be encoded."))
                    return
                }
                lastAudioTime = relativeTime
                audioWasWritten = true
            } catch { fail(error); return }
        }
    }

    func finish(stopHostTime: CMTime) async throws -> RecordingResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.finishing else {
                    continuation.resume(throwing: RecordingServiceError.notRecording)
                    return
                }
                self.acceptingSamples = false
                let deadline = DispatchTime.now() + .seconds(5)
                self.prepareToFinish(stopHostTime: stopHostTime, deadline: deadline, continuation: continuation)
            }
        }
    }

    private func prepareToFinish(stopHostTime: CMTime, deadline: DispatchTime,
                                 continuation: CheckedContinuation<RecordingResult, Error>) {
        drainPendingSamples()
        if let writerFailure {
            finishing = true
            stopTimer()
            assetWriter.cancelWriting()
            continuation.resume(throwing: writerFailure)
            return
        }
        if lastVideo == nil, pendingVideo != nil, DispatchTime.now() < deadline {
            queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
                self.prepareToFinish(stopHostTime: stopHostTime, deadline: deadline, continuation: continuation)
            }
            return
        }
        guard let firstHostTime, let lastVideo else {
            finishing = true
            stopTimer()
            assetWriter.cancelWriting()
            continuation.resume(throwing: RecordingServiceError.noVideo)
            return
        }
        // A static screen may only deliver one complete frame. Hold it until the actual stop time.
        let wallDuration = CMTimeSubtract(stopHostTime, firstHostTime)
        let endTime = CMTimeMaximum(frameInterval, CMTimeMaximum(wallDuration, CMTimeAdd(lastVideoTime, frameInterval)))
        let finalFrameTime = CMTimeMaximum(lastVideoTime, CMTimeSubtract(endTime, frameInterval))
        let needsFinalFrame = finalFrameTime > lastVideoTime
        let needsSilence = audioInput != nil && !audioWasWritten
        let ready = pendingVideo == nil && pendingAudio.isEmpty
            && (!needsFinalFrame || videoInput.isReadyForMoreMediaData)
            && (!needsSilence || audioInput?.isReadyForMoreMediaData == true)
        guard ready else {
            if DispatchTime.now() >= deadline {
                finishing = true
                stopTimer()
                assetWriter.cancelWriting()
                continuation.resume(throwing: RecordingServiceError.failed("The recording encoder did not finish in time."))
            } else {
                queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
                    self.prepareToFinish(stopHostTime: stopHostTime, deadline: deadline, continuation: continuation)
                }
            }
            return
        }
        finishing = true
        stopTimer()
        do {
            if needsFinalFrame {
                let heldFrame = try Self.retimed(lastVideo, to: finalFrameTime)
                guard videoInput.append(heldFrame) else {
                    throw assetWriter.error ?? RecordingServiceError.failed("The last video frame could not be saved.")
                }
            }
            if needsSilence, let audioInput {
                // ScreenCaptureKit can send no audio samples for a silent source. A valid silent
                // AAC seed avoids finishing an empty configured audio input.
                guard audioInput.append(try Self.silentAudioSample()) else {
                    throw assetWriter.error ?? RecordingServiceError.failed("The silent audio track could not be saved.")
                }
            }
            assetWriter.endSession(atSourceTime: endTime)
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
            assetWriter.finishWriting {
                self.queue.async {
                    guard self.assetWriter.status == .completed else {
                        continuation.resume(throwing: self.assetWriter.error ?? RecordingServiceError.failed("The recording file did not finish saving."))
                        return
                    }
                    continuation.resume(returning: RecordingResult(url: self.url, pixelWidth: self.width,
                                                                   pixelHeight: self.height, duration: endTime.seconds))
                }
            }
        } catch {
            assetWriter.cancelWriting()
            continuation.resume(throwing: error)
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.acceptingSamples = false
                self.finishing = true
                self.stopTimer()
                if self.assetWriter.status == .writing || self.assetWriter.status == .unknown { self.assetWriter.cancelWriting() }
                self.pendingVideo = nil
                self.pendingAudio.removeAll()
                self.lastVideo = nil
                try? FileManager.default.removeItem(at: self.url)
                continuation.resume()
            }
        }
    }

    private func stopTimer() {
        retryTimer?.cancel()
        retryTimer = nil
    }

    private func fail(_ error: Error) {
        writerFailure = error
        guard !failureWasReported else { return }
        failureWasReported = true
        onWriterFailure?(error)
    }

    private static func retimed(_ sample: CMSampleBuffer, to time: CMTime) throws -> CMSampleBuffer {
        var count = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard status == noErr, count > 0 else { throw RecordingServiceError.failed("The recording sample timing is invalid.") }
        var entries = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        status = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &entries, entriesNeededOut: &count)
        guard status == noErr else { throw RecordingServiceError.failed("The recording sample timing could not be read.") }
        let offset = CMTimeSubtract(time, CMSampleBufferGetPresentationTimeStamp(sample))
        for index in entries.indices {
            entries[index].presentationTimeStamp = CMTimeAdd(entries[index].presentationTimeStamp, offset)
            if entries[index].decodeTimeStamp.isValid { entries[index].decodeTimeStamp = CMTimeAdd(entries[index].decodeTimeStamp, offset) }
        }
        var output: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                                                      sampleTimingEntryCount: entries.count, sampleTimingArray: &entries,
                                                      sampleBufferOut: &output)
        guard status == noErr, let output else { throw RecordingServiceError.failed("The recording sample timing could not be synchronized.") }
        return output
    }

    private static func silentAudioSample() throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
            mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw RecordingServiceError.failed("The silent audio format could not be created.") }
        let frames = 1_024
        let byteCount = frames * 8
        var block: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw RecordingServiceError.failed("The silent audio buffer could not be created.") }
        let zeros = [UInt8](repeating: 0, count: byteCount)
        status = zeros.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount) }
        guard status == noErr else { throw RecordingServiceError.failed("The silent audio buffer could not be initialized.") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var size = 8
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw RecordingServiceError.failed("The silent audio sample could not be created.") }
        return sample
    }
}
