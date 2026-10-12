import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Native encoding checks with generated media; no screen access or audio device is needed.
@main
struct RecordingChecks {
    private static let width = 640
    private static let height = 360
    private static let sourceStart = CMTime(value: 100, timescale: 1)

    static func main() async {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/checks/fixtures", isDirectory: true)
            .appendingPathComponent("RecordingChecks-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try await checkStaticVideo(in: directory, audio: false)
            print("PASS: A static first frame is held through stop; 640×360 H.264 MP4 plays and decodes.")
            try await checkStaticVideo(in: directory, audio: true)
            print("PASS: A silent source with system audio enabled produces a valid AAC track.")
            try await checkAudioEncoding(in: directory)
            print("PASS: Native stereo PCM encodes to AAC and decodes with the original audible signal.")
            try await checkImmediateStop(in: directory)
            print("PASS: An immediate stop at 60 fps still produces playable video with configured AAC audio.")
            try await checkNoFrames(in: directory)
            print("PASS: Finishing without a video frame fails and leaves no unusable output.")
            try await checkCancellation(in: directory)
            print("PASS: Canceling an unfinished recording removes its partial output.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func checkStaticVideo(in directory: URL, audio: Bool) async throws {
        let url = directory.appendingPathComponent(audio ? "static-silent.mp4" : "static-video.mp4")
        let writer = try RecordingWriter(url: url, width: width, height: height, fps: 30, captureAudio: audio)
        let frame = try makeVideo(at: sourceStart)
        await submit(to: writer) { writer.appendVideo(frame.buffer) }
        // ScreenCaptureKit may deliver just one complete frame when the screen
        // is unchanged. The encoder must preserve the time spent recording it.
        try await Task.sleep(for: .milliseconds(350))
        let result = try await writer.finish(stopHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
        try require(result.pixelWidth == width && result.pixelHeight == height, "The result changed capture dimensions.")
        try require(result.duration >= 0.15, "The static recording lost its elapsed duration (\(result.duration) s).")
        let asset = try await validateVideo(at: result.url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if audio {
            try require(audioTracks.count == 1, "The silent configured source did not create an audio track.")
            try await validateAAC(audioTracks[0])
            let peak = try decodedAudioPeak(asset: asset, track: audioTracks[0])
            try require(peak < 0.005, "The generated silent audio seed contains an audible signal.")
        } else {
            try require(audioTracks.isEmpty, "Audio appeared in a video-only recording.")
        }
    }

    private static func checkAudioEncoding(in directory: URL) async throws {
        let url = directory.appendingPathComponent("native-audio.mp4")
        let writer = try RecordingWriter(url: url, width: width, height: height, fps: 30, captureAudio: true)
        let video = try makeVideo(at: sourceStart)
        let precedingAudio = try makeAudio(at: CMTimeSubtract(sourceStart, CMTime(value: 1, timescale: 10)))
        let firstAudio = try makeAudio(at: sourceStart)
        let secondAudio = try makeAudio(at: CMTimeAdd(sourceStart, CMTime(value: 1_024, timescale: 48_000)))
        await submit(to: writer) {
            // Verify the startup queue tolerates audio arriving before video.
            writer.appendAudio(precedingAudio.buffer)
            writer.appendVideo(video.buffer)
            writer.appendAudio(firstAudio.buffer)
            writer.appendAudio(secondAudio.buffer)
        }
        try await Task.sleep(for: .milliseconds(350))
        let result = try await writer.finish(stopHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
        let asset = try await validateVideo(at: result.url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try require(tracks.count == 1, "The PCM recording did not create one audio track.")
        try await validateAAC(tracks[0])
        let peak = try decodedAudioPeak(asset: asset, track: tracks[0])
        try require(peak > 0.05, "The AAC output lost the PCM signal (decoded peak \(peak)).")
        let timeRange = try await tracks[0].load(.timeRange)
        try require(timeRange.start >= .zero, "Pre-video audio introduced a negative start timestamp.")
    }

    private static func checkNoFrames(in directory: URL) async throws {
        let url = directory.appendingPathComponent("no-frames.mp4")
        let writer = try RecordingWriter(url: url, width: width, height: height, fps: 30, captureAudio: true)
        let audio = try makeAudio(at: sourceStart)
        await submit(to: writer) { writer.appendAudio(audio.buffer) }
        do {
            _ = try await writer.finish(stopHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
            throw RecordingCheckError("An empty recording was reported as successful.")
        } catch RecordingServiceError.noVideo {
            try require(!FileManager.default.fileExists(atPath: url.path), "An empty recording left an unusable MP4 file.")
        }
    }

    private static func checkImmediateStop(in directory: URL) async throws {
        let url = directory.appendingPathComponent("immediate-stop.mp4")
        let writer = try RecordingWriter(url: url, width: width, height: height, fps: 60, captureAudio: true)
        let frame = try makeVideo(at: sourceStart)
        await submit(to: writer) { writer.appendVideo(frame.buffer) }
        let result = try await writer.finish(stopHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
        try require(result.duration >= 1.0 / 60, "An immediate stop lost the minimum video frame duration.")
        let asset = AVURLAsset(url: result.url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        try require(playable && duration.isNumeric && duration.seconds >= 1.0 / 60,
                    "An immediate stop did not create a playable clip lasting at least one frame.")
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        try require(videos.count == 1 && audios.count == 1, "An immediate stop lost a configured media track.")
        try await validateAAC(audios[0])
    }

    private static func checkCancellation(in directory: URL) async throws {
        let url = directory.appendingPathComponent("canceled.mp4")
        let writer = try RecordingWriter(url: url, width: width, height: height, fps: 30, captureAudio: false)
        let frame = try makeVideo(at: sourceStart)
        await submit(to: writer) { writer.appendVideo(frame.buffer) }
        await writer.cancel()
        try require(!FileManager.default.fileExists(atPath: url.path), "Canceling a recording left its partial MP4 file.")
    }

    private static func validateVideo(at url: URL) async throws -> AVURLAsset {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        try require((attributes[.size] as? NSNumber)?.intValue ?? 0 > 1_024, "The MP4 output is missing or empty.")
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        try require(playable, "AVFoundation cannot play the encoded MP4.")
        let duration = try await asset.load(.duration)
        try require(duration.isNumeric && duration.seconds >= 0.15, "The encoded clip duration is too short (\(duration.seconds) s).")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        try require(tracks.count == 1, "The MP4 output does not contain one video track.")
        let track = tracks[0]
        let size = try await track.load(.naturalSize)
        try require(size == CGSize(width: width, height: height), "Video dimensions changed to \(size).")
        let formats = try await track.load(.formatDescriptions)
        try require(!formats.isEmpty && formats.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 },
                    "The video track was not encoded as H.264.")
        let videoRange = try await track.load(.timeRange)
        try require(videoRange.duration.seconds >= 0.15, "Only the first static frame was saved.")

        // Decode real samples rather than relying on the container metadata.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        try require(reader.canAdd(output), "The H.264 decoder could not be configured.")
        reader.add(output)
        try require(reader.startReading(), "The H.264 decoder could not start: \(reader.error?.localizedDescription ?? "unknown error").")
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                throw RecordingCheckError("A decoded H.264 frame has no pixel buffer.")
            }
            try require(CVPixelBufferGetWidth(pixelBuffer) == width && CVPixelBufferGetHeight(pixelBuffer) == height,
                        "A decoded frame changed source dimensions.")
            frames += 1
        }
        try require(reader.status == .completed, "Video decoding failed: \(reader.error?.localizedDescription ?? "unknown error").")
        try require(frames >= 2, "The static clip did not include a held final frame.")
        return asset
    }

    private static func validateAAC(_ track: AVAssetTrack) async throws {
        let descriptions = try await track.load(.formatDescriptions)
        try require(!descriptions.isEmpty && descriptions.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC },
                    "The audio track was not encoded as AAC.")
        let range = try await track.load(.timeRange)
        try require(range.duration.seconds > 0, "The AAC track contains no samples.")
    }

    private static func decodedAudioPeak(asset: AVURLAsset, track: AVAssetTrack) throws -> Float {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ])
        try require(reader.canAdd(output), "The AAC decoder could not be configured.")
        reader.add(output)
        try require(reader.startReading(), "The AAC decoder could not start.")
        var peak: Float = 0
        var decodedSamples = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                throw RecordingCheckError("A decoded AAC sample has no data buffer.")
            }
            let bytes = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
            let status = floats.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!)
            }
            try require(status == noErr, "The decoded audio buffer could not be read (\(status)).")
            for value in floats { peak = max(peak, abs(value)) }
            decodedSamples += floats.count
        }
        try require(reader.status == .completed, "Audio decoding failed: \(reader.error?.localizedDescription ?? "unknown error").")
        try require(decodedSamples > 0, "The AAC track did not decode to any PCM samples.")
        return peak
    }

    private static func makeVideo(at time: CMTime) throws -> RecordingCheckSample {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        var status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
        try require(status == kCVReturnSuccess, "The synthetic video buffer could not be created (\(status)).")
        guard let pixelBuffer else { throw RecordingCheckError("The synthetic video buffer is missing.") }
        status = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        try require(status == kCVReturnSuccess, "The synthetic video buffer could not be locked.")
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw RecordingCheckError("The synthetic video buffer has no writable storage.")
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = address.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = 38
                row[x * 4 + 1] = x < width / 2 ? 156 : 90
                row[x * 4 + 2] = 68
                row[x * 4 + 3] = 255
            }
        }
        var format: CMVideoFormatDescription?
        status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        try require(status == noErr, "The synthetic video format could not be created (\(status)).")
        guard let format else { throw RecordingCheckError("The synthetic video format is missing.") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                         formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        try require(status == noErr, "The synthetic video sample could not be created (\(status)).")
        guard let sample else { throw RecordingCheckError("The synthetic video sample is missing.") }
        return RecordingCheckSample(buffer: sample)
    }

    private static func makeAudio(at time: CMTime) throws -> RecordingCheckSample {
        let frames = 1_024
        let channels = 2
        let bytesPerFrame = channels * MemoryLayout<Float>.size
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1, mBytesPerFrame: UInt32(bytesPerFrame), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        try require(status == noErr, "The synthetic audio format could not be created (\(status)).")
        guard let format else { throw RecordingCheckError("The synthetic audio format is missing.") }
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let value = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000)) * 0.2
            samples[frame * channels] = value
            samples[frame * channels + 1] = value
        }
        let byteCount = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block)
        try require(status == noErr, "The synthetic audio buffer could not be created (\(status)).")
        guard let block else { throw RecordingCheckError("The synthetic audio buffer is missing.") }
        status = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        try require(status == noErr, "The synthetic audio buffer could not be initialized (\(status)).")
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleSize = bytesPerFrame
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
        try require(status == noErr, "The synthetic audio sample could not be created (\(status)).")
        guard let sample else { throw RecordingCheckError("The synthetic audio sample is missing.") }
        return RecordingCheckSample(buffer: sample)
    }

    private static func submit(to writer: RecordingWriter, _ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.queue.async {
                operation()
                continuation.resume()
            }
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw RecordingCheckError(message) }
    }
}

/// Buffers are fully initialized before handoff and then read only on the writer queue.
private struct RecordingCheckSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

private struct RecordingCheckError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
