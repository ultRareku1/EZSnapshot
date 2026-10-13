import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var format: ScreenshotFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    @Published var includeCursor: Bool { didSet { defaults.set(includeCursor, forKey: "includeCursor") } }
    @Published var captureDelay: Int { didSet { defaults.set(captureDelay, forKey: "captureDelay") } }
    @Published var saveFolder: URL { didSet { defaults.set(saveFolder.path, forKey: "saveFolder") } }
    @Published var mode: CaptureMode = .region
    @Published var section: AppSection = .capture
    @Published var records: [ScreenshotRecord] = []
    @Published var selectedID: UUID?
    @Published var search = ""
    @Published var isCapturing = false
    @Published var permissionGranted = CaptureService.hasPermission
    @Published var toast: String?
    @Published var alert: AppAlert?
    @Published var recordToDelete: ScreenshotRecord?
    @Published var editorRecord: ScreenshotRecord?
    @Published var renameRecord: ScreenshotRecord?
    @Published var recordingPhase: RecordingPhase = .idle
    @Published var recordingMode: CaptureMode = .fullScreen {
        didSet {
            if oldValue != recordingMode {
                recordingRegion = nil
                recordingTargetID = eligibleRecordingTargets.first?.id
            }
        }
    }
    @Published var recordingTargets: [RecordingTarget] = []
    @Published var recordingTargetID: String? {
        didSet { if oldValue != recordingTargetID { recordingRegion = nil } }
    }
    @Published var recordingRegion: CGRect?
    @Published var isLoadingRecordingSources = false
    @Published var recordingStartedAt: Date?
    @Published private(set) var recordingTime = "00:00"
    @Published var recordingAudio: Bool { didSet { defaults.set(recordingAudio, forKey: "recordingAudio") } }
    @Published var recordingCursor: Bool { didSet { defaults.set(recordingCursor, forKey: "recordingCursor") } }
    @Published var recordingFPS: Int { didSet { defaults.set(recordingFPS, forKey: "recordingFPS") } }
    @Published var showRecordingQuitDialog = false
    private let recordingService = RecordingService()
    private let regionSelector = RecordingRegionSelector()
    private var recordingTask: Task<Void, Never>?
    private var recordingClockTask: Task<Void, Never>?
    private var quitAfterRecording = false
    private var pendingRecordingFailure: Error?
    private let defaults: UserDefaults
    private let manifestURL: URL
    private let captureService = CaptureService()
    private var toastTask: Task<Void, Never>?

    init() {
        defaults = .standard
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        format = ScreenshotFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .png
        includeCursor = defaults.bool(forKey: "includeCursor")
        captureDelay = defaults.integer(forKey: "captureDelay")
        recordingAudio = defaults.bool(forKey: "recordingAudio")
        recordingCursor = defaults.object(forKey: "recordingCursor") == nil ? true : defaults.bool(forKey: "recordingCursor")
        recordingFPS = defaults.integer(forKey: "recordingFPS") == 60 ? 60 : 30
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        saveFolder = defaults.string(forKey: "saveFolder").map { URL(fileURLWithPath: $0) }
            ?? pictures.appendingPathComponent("EZSnapshot", isDirectory: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        manifestURL = support.appendingPathComponent("EZSnapshot/library.json")
        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode([ScreenshotRecord].self, from: data) {
            records = saved.sorted { $0.createdAt > $1.createdAt }
        }
        recordingService.onFailure = { [weak self] error in
            guard let self else { return }
            if self.recordingPhase == .preparing { self.pendingRecordingFailure = error }
            else if self.recordingPhase == .recording { self.stopRecording(interruption: error) }
        }
    }

    func text(_ key: L10nKey) -> String { language.string(key) }
    var selectedRecord: ScreenshotRecord? { records.first { $0.id == selectedID } }
    var filteredRecords: [ScreenshotRecord] {
        records.filter { record in
            (section != .favorites || record.isFavorite) &&
            (search.isEmpty || record.name.localizedCaseInsensitiveContains(search))
        }
    }
    var favoriteCount: Int { records.filter(\.isFavorite).count }

    func capture(_ captureMode: CaptureMode? = nil) {
        guard !isCapturing, !recordingPhase.isBusy else { return }
        if let captureMode { mode = captureMode }
        permissionGranted = CaptureService.hasPermission
        guard permissionGranted else {
            _ = CaptureService.requestPermission()
            permissionGranted = CaptureService.hasPermission
            if !permissionGranted {
                alert = AppAlert(title: text(.permissionRequired), message: text(.permissionMessage))
                return
            }
            return capture(captureMode)
        }
        let requestedMode = mode
        let requestedFormat = format
        let requestedFolder = saveFolder
        let requestedDelay = captureDelay
        let requestedCursor = includeCursor
        isCapturing = true
        NSApp.hide(nil)
        Task {
            // Allow the window to leave the compositor before starting the system capture.
            try? await Task.sleep(for: .milliseconds(300))
            do {
                let url = try await captureService.capture(
                    mode: requestedMode, includeCursor: requestedCursor,
                    delay: requestedDelay, destination: requestedFolder, format: requestedFormat
                )
                restoreWindow()
                isCapturing = false
                if let url {
                    try addRecord(at: url)
                    showToast(text(.savedToLibrary))
                } else {
                    showToast(text(.captureCancelled))
                }
            } catch {
                restoreWindow()
                isCapturing = false
                alert = AppAlert(title: text(.captureError), message: error.localizedDescription)
            }
        }
    }

    func restoreWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" || $0.title == "EZSnapshot" }?.makeKeyAndOrderFront(nil)
    }

    func addRecord(at url: URL) throws {
        guard let image = NSImage(contentsOf: url) else { throw CaptureServiceError.missingOutput }
        let (width, height) = image.pixelDimensions
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let record = ScreenshotRecord(
            name: url.deletingPathExtension().lastPathComponent,
            filePath: url.path, createdAt: Date(), pixelWidth: width, pixelHeight: height,
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0
        )
        records.insert(record, at: 0)
        selectedID = record.id
        persistLibrary()
    }

    func select(_ record: ScreenshotRecord) {
        selectedID = record.id
        section = .library
    }

    func toggleFavorite(_ record: ScreenshotRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        persistLibrary()
    }

    func copy(_ record: ScreenshotRecord) {
        if record.isVideo {
            guard FileManager.default.fileExists(atPath: record.filePath) else { missingFile(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([record.url as NSURL])
            showToast(text(.copiedToClipboard))
            return
        }
        guard let image = NSImage(contentsOf: record.url) else { missingFile(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        showToast(text(.copiedToClipboard))
    }

    func export(_ record: ScreenshotRecord) {
        guard FileManager.default.fileExists(atPath: record.filePath) else { missingFile(); return }
        let panel = NSSavePanel()
        panel.title = text(.export)
        panel.nameFieldStringValue = record.url.lastPathComponent
        panel.allowedContentTypes = [record.isVideo ? .mpeg4Movie : (record.url.pathExtension.lowercased() == "png" ? .png : .jpeg)]
        panel.allowsOtherFileTypes = false
        panel.prompt = text(.save)
        panel.nameFieldLabel = text(.name)
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try FileExport.copy(record.url, to: destination)
                    }.value
                    self.showToast(self.text(.savedToLibrary))
                } catch {
                    self.alert = AppAlert(title: self.text(.exportError), message: error.localizedDescription)
                }
            }
        }
    }

    func reveal(_ record: ScreenshotRecord) {
        guard FileManager.default.fileExists(atPath: record.filePath) else { missingFile(); return }
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }

    func delete(_ record: ScreenshotRecord) {
        do {
            if FileManager.default.fileExists(atPath: record.filePath) {
                try FileManager.default.trashItem(at: record.url, resultingItemURL: nil)
            }
            records.removeAll { $0.id == record.id }
            if selectedID == record.id { selectedID = nil }
            ThumbnailCache.shared.remove(record.url)
            persistLibrary()
        } catch { alert = AppAlert(title: text(.deleteCapture), message: error.localizedDescription) }
        recordToDelete = nil
    }

    func rename(_ record: ScreenshotRecord, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"),
              let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let destination = record.url.deletingLastPathComponent()
            .appendingPathComponent(name).appendingPathExtension(record.url.pathExtension)
        do {
            if destination != record.url { try FileManager.default.moveItem(at: record.url, to: destination) }
            records[index].name = name
            records[index].filePath = destination.path
            ThumbnailCache.shared.remove(record.url)
            persistLibrary()
            renameRecord = nil
        } catch { alert = AppAlert(title: text(.rename), message: error.localizedDescription) }
    }

    func saveEdited(_ image: NSImage, original: ScreenshotRecord) {
        do {
            let editedFormat: ScreenshotFormat = original.url.pathExtension.lowercased() == "png" ? .png : .jpeg
            guard let data = image.encoded(as: editedFormat) else { throw CaptureServiceError.missingOutput }
            let destination = original.url.deletingLastPathComponent()
                .appendingPathComponent("\(original.name)-edited-\(UUID().uuidString)")
                .appendingPathExtension(editedFormat.fileExtension)
            try data.write(to: destination, options: .withoutOverwriting)
            try addRecord(at: destination)
            showToast(text(.savedToLibrary))
        } catch { alert = AppAlert(title: text(.exportError), message: error.localizedDescription) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = text(.saveLocation)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url { self?.saveFolder = url }
        }
    }

    func refreshPermission() { permissionGranted = CaptureService.hasPermission }
    func requestPermission() {
        _ = CaptureService.requestPermission()
        refreshPermission()
        if !permissionGranted { CaptureService.openPermissionSettings() }
    }

    var eligibleRecordingTargets: [RecordingTarget] {
        recordingTargets.filter {
            if recordingMode == .window { if case .window = $0 { return true }; return false }
            if case .display = $0 { return true }; return false
        }
    }
    var recordingTarget: RecordingTarget? { eligibleRecordingTargets.first { $0.id == recordingTargetID } }
    var canStartRecording: Bool {
        permissionGranted && !isCapturing && recordingPhase == .idle && recordingTarget != nil &&
        (recordingMode != .region || recordingRegion != nil)
    }
    var recordingElapsed: Double { recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func refreshRecordingSources() {
        refreshPermission()
        guard permissionGranted, !isLoadingRecordingSources, !recordingPhase.isBusy else { return }
        isLoadingRecordingSources = true
        Task {
            defer { isLoadingRecordingSources = false }
            do {
                let targets = try await recordingService.availableTargets()
                recordingTargets = targets
                if !eligibleRecordingTargets.contains(where: { $0.id == recordingTargetID }) {
                    recordingTargetID = eligibleRecordingTargets.first?.id
                }
            } catch { alert = AppAlert(title: text(.recordingError), message: error.localizedDescription) }
        }
    }

    func selectRecordingRegion() {
        guard let target = recordingTarget, case .display(let display) = target,
              !recordingPhase.isBusy, !isCapturing else { return }
        recordingPhase = .selecting
        selectedID = nil
        hideMainWindow()
        recordingTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { finishRecordingPreparation(); return }
            let region = await regionSelector.select(on: display, language: language)
            if let region { recordingRegion = region }
            finishRecordingPreparation()
        }
    }

    func startRecording() {
        refreshPermission()
        if !permissionGranted {
            _ = CaptureService.requestPermission()
            refreshPermission()
        }
        guard permissionGranted else {
            alert = AppAlert(title: text(.permissionRequired), message: text(.permissionRecordingMessage))
            return
        }
        guard canStartRecording, let requestedTarget = recordingTarget else {
            section = .record
            restoreWindow()
            if recordingTarget == nil { refreshRecordingSources() }
            return
        }
        let targetID = requestedTarget.id
        let region = recordingMode == .region ? recordingRegion : nil
        let audio = recordingAudio
        let cursor = recordingCursor
        let fps = recordingFPS
        let folder = saveFolder
        recordingPhase = .preparing
        pendingRecordingFailure = nil
        selectedID = nil
        hideMainWindow()
        recordingTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let freshTargets = try await recordingService.availableTargets()
                guard let target = freshTargets.first(where: { $0.id == targetID }) else {
                    throw NSError(domain: "EZSnapshot", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: text(.sourceUnavailable)])
                }
                try await recordingService.start(target: target, region: region, includeCursor: cursor,
                                                 captureAudio: audio, fps: fps, destination: folder)
                recordingStartedAt = Date()
                recordingPhase = .recording
                startRecordingClock()
                if let error = pendingRecordingFailure {
                    pendingRecordingFailure = nil
                    stopRecording(interruption: error)
                } else if quitAfterRecording { stopRecording() }
            } catch {
                stopRecordingClock()
                recordingPhase = .idle
                recordingStartedAt = nil
                pendingRecordingFailure = nil
                restoreWindow()
                if quitAfterRecording {
                    quitAfterRecording = false
                    NSApp.terminate(nil)
                } else if !(error is CancellationError) {
                    alert = AppAlert(title: text(.recordingError), message: error.localizedDescription)
                }
            }
        }
    }

    func stopRecording(interruption: Error? = nil) {
        guard recordingPhase == .recording else { return }
        recordingPhase = .finishing
        stopRecordingClock()
        recordingTask = Task {
            do {
                let result = try await recordingService.stop()
                let attributes = try FileManager.default.attributesOfItem(atPath: result.url.path)
                let record = ScreenshotRecord(
                    name: result.url.deletingPathExtension().lastPathComponent, filePath: result.url.path,
                    createdAt: Date(), pixelWidth: result.pixelWidth, pixelHeight: result.pixelHeight,
                    byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                    duration: result.duration
                )
                records.insert(record, at: 0)
                persistLibrary()
                recordingPhase = .idle
                recordingStartedAt = nil
                if quitAfterRecording {
                    quitAfterRecording = false
                    NSApp.terminate(nil)
                    return
                }
                selectedID = record.id
                restoreWindow()
                showToast(text(.recordingSaved))
                if let interruption {
                    alert = AppAlert(title: text(.recordingInterrupted), message: interruption.localizedDescription)
                }
            } catch {
                recordingPhase = .idle
                recordingStartedAt = nil
                quitAfterRecording = false
                restoreWindow()
                alert = AppAlert(title: text(.recordingError), message: error.localizedDescription)
            }
        }
    }

    func toggleRecording() {
        if recordingPhase == .recording { stopRecording() }
        else if recordingPhase == .idle { startRecording() }
    }
    // A TimelineView inside MenuBarExtra's label can recursively invalidate
    // the status button image on macOS. Drive its plain Text from one task.
    private func startRecordingClock() {
        recordingClockTask?.cancel()
        recordingTime = ScreenshotRecord.timeString(recordingElapsed)
        recordingClockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, self.recordingPhase == .recording else { return }
                let updated = ScreenshotRecord.timeString(self.recordingElapsed)
                if self.recordingTime != updated { self.recordingTime = updated }
            }
        }
    }
    private func stopRecordingClock() {
        recordingClockTask?.cancel()
        recordingClockTask = nil
    }
    func stopRecordingAndQuit() {
        showRecordingQuitDialog = false
        quitAfterRecording = true
        switch recordingPhase {
        case .recording: stopRecording()
        case .selecting: recordingTask?.cancel()
        case .preparing, .finishing: break // Wait for the operation, then finalize before quitting.
        case .idle: quitAfterRecording = false; NSApp.terminate(nil)
        }
    }
    private func finishRecordingPreparation() {
        recordingPhase = .idle
        if quitAfterRecording {
            quitAfterRecording = false
            NSApp.terminate(nil)
        } else { restoreWindow() }
    }
    private func hideMainWindow() {
        NSApp.windows.filter { $0.identifier?.rawValue == "main" || $0.title == "EZSnapshot" }
            .forEach { $0.orderOut(nil) }
    }
    func missingFile() {
        alert = AppAlert(title: text(.fileMissing), message: text(.fileMissingMessage))
    }
    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
    private func persistLibrary() {
        do {
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: manifestURL, options: .atomic)
        } catch { alert = AppAlert(title: text(.captureError), message: error.localizedDescription) }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 48 }
    func image(_ url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url.path as NSString) { return cached }
        guard url.pathExtension.lowercased() != "mp4" else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 720,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: url.path as NSString)
        return image
    }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url.path as NSString) }
    func remove(_ url: URL) { cache.removeObject(forKey: url.path as NSString) }
}
