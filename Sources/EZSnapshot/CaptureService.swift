import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureServiceError: LocalizedError, Sendable {
    case permissionDenied
    case failed(String)
    case missingOutput
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow EZSnapshot to record your screen in System Settings → Privacy & Security → Screen Recording, then reopen the app."
        case .failed(let detail):
            return detail.isEmpty ? "The screenshot could not be captured." : "The screenshot could not be captured. \(detail)"
        case .missingOutput:
            return "The screenshot finished without creating an image."
        case .saveFailed(let detail):
            return "The screenshot was captured, but could not be saved. \(detail)"
        }
    }
}

/// Uses macOS's own selection overlay, keeping screenshot interaction familiar.
@MainActor
final class CaptureService {
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Returns nil when the native interactive picker is dismissed with Escape.
    /// Cursor inclusion is supported by macOS for full-screen captures only.
    func capture(
        mode: CaptureMode,
        includeCursor: Bool,
        delay: Int,
        destination: URL,
        format: ScreenshotFormat
    ) async throws -> URL? {
        try Task.checkCancellation()
        guard Self.hasPermission else { throw CaptureServiceError.permissionDenied }

        let accessingDestination = destination.startAccessingSecurityScopedResource()
        defer {
            if accessingDestination { destination.stopAccessingSecurityScopedResource() }
        }
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        try Task.checkCancellation()

        // The system utility writes only into an app-owned temporary workspace.
        // EZSnapshot exports the finished image itself, so child-process access
        // to the user's selected folder cannot prevent native capture.
        let workspace = try Self.makeCaptureWorkspace()
        let temporaryURL = workspace.appendingPathComponent("Capture").appendingPathExtension(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: workspace) }

        var arguments = ["-x", "-T", "0", "-t", format == .jpeg ? "jpg" : "png"]
        switch mode {
        case .region:
            arguments += ["-i", "-s"]
        case .window:
            arguments += ["-i", "-w"]
        case .fullScreen:
            arguments += ["-m"]
            if includeCursor { arguments += ["-C"] }
        }
        arguments.append(temporaryURL.path)

        let result = try await Self.runScreencapture(arguments: arguments)
        try Task.checkCancellation()

        let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let outputSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let isInteractive = mode != .fullScreen

        // macOS returns either 0 or 1 for a dismissed interactive picker.
        // A reported error, a signal, or another exit code remains an error.
        if isInteractive, outputSize == 0, result.stderr.isEmpty,
           result.reason == .exit, result.status == 0 || result.status == 1 {
            return nil
        }
        guard result.reason == .exit, result.status == 0 else {
            let detail = result.stderr.isEmpty ? "macOS screenshot capture exited with code \(result.status)." : result.stderr
            throw CaptureServiceError.failed(detail)
        }
        guard outputSize > 0 else {
            if !result.stderr.isEmpty { throw CaptureServiceError.failed(result.stderr) }
            throw CaptureServiceError.missingOutput
        }

        do {
            // Validation and file export can involve large images or a slow
            // external drive; keep that work away from the main actor.
            return try await Task.detached(priority: .userInitiated) {
                try Self.publishImage(at: temporaryURL, in: destination, format: format)
            }.value
        } catch let error as CaptureServiceError {
            throw error
        } catch {
            throw CaptureServiceError.saveFailed("\(destination.path): \(error.localizedDescription)")
        }
    }

    nonisolated static func makeCaptureWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EZSnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    nonisolated static func publishImage(
        at temporaryURL: URL,
        in directory: URL,
        format: ScreenshotFormat,
        capturedAt: Date = Date()
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(temporaryURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else {
            throw CaptureServiceError.failed("macOS did not produce a valid screenshot image.")
        }
        let expectedType = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard (CGImageSourceGetType(source) as String?) == expectedType else {
            throw CaptureServiceError.failed("macOS produced an image in an unexpected format.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let baseName = "EZSnapshot \(formatter.string(from: capturedAt))"

        // copyItem handles different volumes and refuses to overwrite an image
        // created by another app between the existence check and the copy.
        // The validated source remains intact until the caller cleans up.
        for suffix in 0..<10_000 {
            let name = suffix == 0 ? baseName : "\(baseName) (\(suffix + 1))"
            let resultURL = directory.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
            if FileManager.default.fileExists(atPath: resultURL.path) { continue }
            do {
                try FileManager.default.copyItem(at: temporaryURL, to: resultURL)
                return resultURL
            } catch {
                let fileError = error as NSError
                if fileError.domain == NSCocoaErrorDomain,
                   fileError.code == CocoaError.fileWriteFileExists.rawValue { continue }
                throw error
            }
        }
        throw CaptureServiceError.failed("A unique screenshot filename could not be created.")
    }

    private static func runScreencapture(arguments: [String]) async throws -> CaptureProcessResult {
        let cancellation = CaptureProcessCancellation()
        return try await withTaskCancellationHandler {
            let task = Task.detached(priority: .userInitiated) {
                let process = Process()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errorPipe

                try cancellation.launch(process)
                // Drain while the child runs so a full error pipe cannot deadlock it.
                let errorReader = Task.detached(priority: .utility) {
                    errorPipe.fileHandleForReading.readDataToEndOfFile()
                }
                process.waitUntilExit()
                let errorData = await errorReader.value
                try cancellation.checkCancellation()

                let stderr = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return CaptureProcessResult(status: process.terminationStatus, reason: process.terminationReason, stderr: stderr)
            }
            return try await task.value
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private struct CaptureProcessResult: Sendable {
    let status: Int32
    let reason: Process.TerminationReason
    let stderr: String
}

/// Synchronizes cancellation with child launch, including cancellation before run().
private final class CaptureProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        self.process = process
        try process.run()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled { throw CancellationError() }
    }
}
