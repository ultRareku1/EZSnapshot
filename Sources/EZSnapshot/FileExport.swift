import Foundation

enum FileExport {
    /// Copy media without loading the file into RAM. Publish only after copying finishes.
    static func copy(_ source: URL, to destination: URL) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let manager = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".EZSnapshot-export-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }
}
