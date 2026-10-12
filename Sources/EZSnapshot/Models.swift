import AppKit
import SwiftUI

enum AppMetadata {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static let author = "ultRareku"
    static let copyright = "© 2026 ultRareku"
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case region, window, fullScreen
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        }
    }
    var titleKey: L10nKey {
        switch self {
        case .region: return .region
        case .window: return .window
        case .fullScreen: return .fullScreen
        }
    }
    var hintKey: L10nKey {
        switch self {
        case .region: return .regionHint
        case .window: return .windowHint
        case .fullScreen: return .fullScreenHint
        }
    }
    var shortcut: String {
        switch self {
        case .region: return "⌃⌥1"
        case .window: return "⌃⌥2"
        case .fullScreen: return "⌃⌥3"
        }
    }
}

enum ScreenshotFormat: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var title: String { self == .png ? "PNG" : "JPEG" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var titleKey: L10nKey {
        switch self { case .system: return .automatic; case .light: return .light; case .dark: return .dark }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case capture, record, library, favorites, settings
    var id: String { rawValue }
    var titleKey: L10nKey {
        switch self { case .capture: return .capture; case .record: return .record; case .library: return .library; case .favorites: return .favorites; case .settings: return .settings }
    }
    var symbol: String {
        switch self { case .capture: return "viewfinder"; case .record: return "record.circle"; case .library: return "square.grid.2x2"; case .favorites: return "star"; case .settings: return "slider.horizontal.3" }
    }
}

enum RecordingPhase: Equatable {
    case idle, selecting, preparing, recording, finishing
    var isBusy: Bool { self != .idle }
}

struct ScreenshotRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var filePath: String
    var createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int64
    var isFavorite: Bool = false
    // Optional so screenshot libraries from version 1.0 decode without migration.
    var duration: Double?
    var url: URL { URL(fileURLWithPath: filePath) }
    var dimensions: String { "\(pixelWidth) × \(pixelHeight)" }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    var isVideo: Bool { url.pathExtension.lowercased() == "mp4" }
    var formattedDuration: String { Self.timeString(duration ?? 0) }
    static func timeString(_ interval: Double) -> String {
        let seconds = max(0, Int(interval.isFinite ? interval : 0))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension NSImage {
    var pixelDimensions: (Int, Int) {
        guard let rep = representations.compactMap({ $0 as? NSBitmapImageRep }).first else {
            if let image = cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return (image.width, image.height)
            }
            return (Int(size.width), Int(size.height))
        }
        return (rep.pixelsWide, rep.pixelsHigh)
    }
    func encoded(as format: ScreenshotFormat) -> Data? {
        guard let cgImage = representations.compactMap({ ($0 as? NSBitmapImageRep)?.cgImage }).first
                ?? cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if format == .jpeg {
            // JPEG has no alpha. Composite onto white instead of producing black transparent pixels.
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
            context.draw(cgImage, in: rect)
            guard let opaque = context.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: opaque).representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
        return rep.representation(using: .png, properties: [:])
    }
}
