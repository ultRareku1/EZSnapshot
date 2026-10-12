import SwiftUI
import AVFoundation

struct MediaThumbnail: View {
    let record: ScreenshotRecord
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(10)
            } else {
                Image(systemName: record.isVideo ? "play.rectangle" : "photo.badge.exclamationmark")
                    .font(.system(size: 25)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.task(id: record.filePath) {
            image = ThumbnailCache.shared.image(record.url)
            guard image == nil, record.isVideo else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: record.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            do {
                let frame = try await generator.image(at: .zero).image
                guard !Task.isCancelled else { return }
                let thumbnail = NSImage(cgImage: frame, size: .zero)
                ThumbnailCache.shared.store(thumbnail, for: record.url)
                image = thumbnail
            } catch { image = nil }
        }
    }
}
