import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecordingTarget: Identifiable {
    case display(SCDisplay)
    case window(SCWindow)

    var id: String {
        switch self {
        case .display(let display): return "display-\(display.displayID)"
        case .window(let window): return "window-\(window.windowID)"
        }
    }

    /// ScreenCaptureKit exposes the source geometry in logical screen points.
    var dimensions: CGSize {
        switch self {
        case .display(let display): return display.frame.size
        case .window(let window): return window.frame.size
        }
    }

    @MainActor var title: String {
        switch self {
        case .display(let display):
            return NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
            }?.localizedName ?? "Display \(display.displayID)"
        case .window(let window):
            let application = window.owningApplication?.applicationName ?? ""
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty { return application.isEmpty ? "Window \(window.windowID)" : application }
            return application.isEmpty || application == title ? title : "\(application) — \(title)"
        }
    }
}

struct RecordingResult {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double
}

enum RecordingServiceError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case invalidTarget
    case invalidRegion
    case noVideo
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return CaptureServiceError.permissionDenied.errorDescription
        case .alreadyRecording: return "A recording is already in progress."
        case .notRecording: return "There is no recording to stop."
        case .invalidTarget: return "The selected screen or window is no longer available."
        case .invalidRegion: return "Select a recording area inside the screen."
        case .noVideo: return "The recording stopped before macOS delivered a video frame."
        case .failed(let detail): return detail.isEmpty ? "The recording could not be saved." : detail
        }
    }
}

/// Captures with macOS frameworks, requiring no bundled executable or codec library.
@MainActor
final class RecordingService: NSObject {
    var onFailure: ((Error) -> Void)?
    var isRecording: Bool { phase == .recording }

    private enum Phase { case idle, starting, recording, stopping }
    private var phase: Phase = .idle
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var destination: URL?
    private var sessionID: UUID?
    private var streamDidStop = false
    private var failureWasReported = false
    private var startupError: Error?
    private var stopTask: Task<RecordingResult, Error>?
    // SCStreamConfiguration.backgroundColor is an assign property; keep its CGColor alive.
    private let captureBackgroundColor = CGColor(gray: 0, alpha: 1)

    func availableTargets() async throws -> [RecordingTarget] {
        guard CaptureService.hasPermission else { throw RecordingServiceError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let processID = ProcessInfo.processInfo.processIdentifier
        let displays = content.displays.sorted {
            let firstIsMain = $0.displayID == CGMainDisplayID()
            let secondIsMain = $1.displayID == CGMainDisplayID()
            return firstIsMain != secondIsMain ? firstIsMain : $0.displayID < $1.displayID
        }.map(RecordingTarget.display)
        let windows = content.windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 2 && $0.frame.height >= 2
                && $0.owningApplication != nil && $0.owningApplication?.processID != processID
        }.map(RecordingTarget.window).sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        return displays + windows
    }

    func start(target: RecordingTarget, region: CGRect?, includeCursor: Bool,
               captureAudio: Bool, fps: Int, destination: URL) async throws {
        guard phase == .idle, stopTask == nil else { throw RecordingServiceError.alreadyRecording }
        guard CaptureService.hasPermission else { throw RecordingServiceError.permissionDenied }
        try Task.checkCancellation()
        let identifier = UUID()
        phase = .starting
        sessionID = identifier
        streamDidStop = false
        failureWasReported = false
        startupError = nil
        self.destination = destination
        var captureStarted = false

        do {
            // Refresh the target: a window may have closed since the picker opened.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            let filter: SCContentFilter
            let sourceSize: CGSize
            switch target {
            case .display(let selectedDisplay):
                guard let display = content.displays.first(where: { $0.displayID == selectedDisplay.displayID }) else {
                    throw RecordingServiceError.invalidTarget
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                sourceSize = display.frame.size
            case .window(let selectedWindow):
                guard region == nil,
                      let window = content.windows.first(where: { $0.windowID == selectedWindow.windowID }),
                      window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier else {
                    throw RecordingServiceError.invalidTarget
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                sourceSize = filter.contentRect.size
            }

            let configuration = SCStreamConfiguration()
            var recordingSize = sourceSize
            if let region {
                let values = [region.origin.x, region.origin.y, region.width, region.height]
                guard values.allSatisfy({ $0.isFinite }), region.width >= 2, region.height >= 2 else {
                    throw RecordingServiceError.invalidRegion
                }
                let clipped = region.intersection(CGRect(origin: .zero, size: sourceSize))
                guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else {
                    throw RecordingServiceError.invalidRegion
                }
                configuration.sourceRect = clipped
                recordingSize = clipped.size
            }
            guard recordingSize.width > 0, recordingSize.height > 0 else { throw RecordingServiceError.invalidTarget }
            // Keep Retina detail, with a portable H.264 limit of 4096 pixels on the long edge.
            let scale = max(1, CGFloat(filter.pointPixelScale))
            let nativeWidth = recordingSize.width * scale
            let nativeHeight = recordingSize.height * scale
            let reduction = min(1, 4096 / max(nativeWidth, nativeHeight))
            let width = max(2, Int((nativeWidth * reduction).rounded(.down)) / 2 * 2)
            let height = max(2, Int((nativeHeight * reduction).rounded(.down)) / 2 * 2)
            let frameRate = min(60, max(1, fps))
            configuration.width = width
            configuration.height = height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate))
            configuration.queueDepth = 5
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.showsCursor = includeCursor
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = true
            configuration.backgroundColor = captureBackgroundColor
            configuration.captureResolution = .best
            configuration.capturesAudio = captureAudio
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true

            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let temporaryURL = destination.appendingPathComponent(".EZRecording-\(identifier.uuidString).mp4")
            let writer = try RecordingWriter(url: temporaryURL, width: width, height: height,
                                             fps: frameRate, captureAudio: captureAudio)
            writer.onStreamFailure = { [weak self] error in
                Task { @MainActor in self?.receivedFailure(error, session: identifier, streamStopped: true) }
            }
            writer.onWriterFailure = { [weak self] error in
                Task { @MainActor in self?.receivedFailure(error, session: identifier, streamStopped: false) }
            }
            self.writer = writer
            let stream = SCStream(filter: filter, configuration: configuration, delegate: writer)
            self.stream = stream
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            if captureAudio { try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue) }
            captureStarted = true
            try await stream.startCapture()
            try Task.checkCancellation()
            if let startupError { throw startupError }
            phase = .recording
        } catch {
            if let stream {
                if captureStarted, !streamDidStop { try? await stream.stopCapture() }
                if let writer {
                    try? stream.removeStreamOutput(writer, type: .screen)
                    try? stream.removeStreamOutput(writer, type: .audio)
                }
            }
            if let writer { await writer.cancel() }
            reset(session: identifier)
            throw error
        }
    }

    /// Repeated calls while saving share one finalization. An interrupted stream can still be saved.
    func stop() async throws -> RecordingResult {
        if let stopTask { return try await stopTask.value }
        guard phase == .recording, let identifier = sessionID,
              let stream, let writer, let destination else { throw RecordingServiceError.notRecording }
        phase = .stopping
        let stopHostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let alreadyStopped = streamDidStop
        let task = Task { @MainActor [self] in
            defer { reset(session: identifier) }
            if !alreadyStopped {
                // Even when the stream is interrupted during stop, finish any good frames.
                try? await stream.stopCapture()
            }
            try? stream.removeStreamOutput(writer, type: .screen)
            try? stream.removeStreamOutput(writer, type: .audio)
            do {
                let written = try await writer.finish(stopHostTime: stopHostTime)
                let url = try Self.publishVideo(at: written.url, in: destination)
                return RecordingResult(url: url, pixelWidth: written.pixelWidth,
                                       pixelHeight: written.pixelHeight, duration: written.duration)
            } catch {
                await writer.cancel()
                throw error
            }
        }
        stopTask = task
        return try await task.value
    }

    private func receivedFailure(_ error: Error, session: UUID, streamStopped: Bool) {
        guard sessionID == session else { return }
        if streamStopped { streamDidStop = true }
        if phase == .starting {
            if startupError == nil { startupError = error }
            return
        }
        guard phase == .recording, !failureWasReported else { return }
        failureWasReported = true
        onFailure?(error)
    }

    private func reset(session: UUID) {
        guard sessionID == session else { return }
        stream = nil
        writer = nil
        destination = nil
        sessionID = nil
        startupError = nil
        stopTask = nil
        phase = .idle
    }

    private static func publishVideo(at temporaryURL: URL, in directory: URL) throws -> URL {
        let size = (try FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw RecordingServiceError.noVideo }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "EZRecording \(formatter.string(from: Date()))"
        for suffix in 0..<10_000 {
            let base = suffix == 0 ? name : "\(name) (\(suffix + 1))"
            let output = directory.appendingPathComponent(base).appendingPathExtension("mp4")
            if FileManager.default.fileExists(atPath: output.path) { continue }
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: output)
                return output
            } catch {
                if FileManager.default.fileExists(atPath: output.path) { continue }
                throw error
            }
        }
        throw RecordingServiceError.failed("A unique recording filename could not be created.")
    }
}
