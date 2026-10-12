import Foundation

@main
struct MediaModelChecks {
    static func main() throws {
        let oldLibrary = """
        [{"id":"6A4BDD3F-4380-4878-8D7A-65DD7440E324","name":"Original","filePath":"/tmp/Original.png","createdAt":0,"pixelWidth":600,"pixelHeight":400,"byteCount":1200,"isFavorite":true}]
        """
        let legacy = try JSONDecoder().decode([ScreenshotRecord].self, from: Data(oldLibrary.utf8))
        precondition(legacy.count == 1 && legacy[0].duration == nil && !legacy[0].isVideo && legacy[0].isFavorite)
        var video = legacy[0]
        video.filePath = "/tmp/Recording.mp4"
        video.duration = 65.8
        let roundTrip = try JSONDecoder().decode(ScreenshotRecord.self, from: JSONEncoder().encode(video))
        precondition(roundTrip == video && roundTrip.isVideo && roundTrip.formattedDuration == "01:05")
        precondition(ScreenshotRecord.timeString(3661) == "1:01:01")
        precondition(ScreenshotRecord.timeString(.nan) == "00:00")
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/checks/exports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        let destination = folder.appendingPathComponent("destination.mp4")
        let data = Data(repeating: 0xA5, count: 1_048_576)
        try data.write(to: source)
        try FileExport.copy(source, to: destination)
        let copied = try Data(contentsOf: destination)
        precondition(copied == data)
        try Data("old".utf8).write(to: destination)
        try FileExport.copy(source, to: destination)
        let replaced = try Data(contentsOf: destination)
        precondition(replaced == data)
        try FileExport.copy(source, to: source)
        let retained = try Data(contentsOf: source)
        precondition(retained == data)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(files.count == 2)
        print("PASS: legacy library migration, video metadata, safe media export, overwrite, and same-file handling.")
    }
}
