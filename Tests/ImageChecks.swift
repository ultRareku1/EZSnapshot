import AppKit
import Foundation

/// Standalone encoding smoke checks. Compile with Models.swift and Localization.swift.
@main
struct ImageChecks {
    static func main() {
        do {
            try checkEncoding()
            let scale = NSScreen.main?.backingScaleFactor
            let display = scale.map { "\($0)×" } ?? "headless"
            print("PASS: PNG and JPEG preserve 600×400 source pixels (300×200 points; display \(display)).")
            print("PASS: PNG preserves transparency; JPEG composites transparent pixels onto white.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func checkEncoding() throws {
        let width = 600
        let height = 400
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ImageCheckError("Could not create the transparent source image.") }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let source = context.makeImage() else {
            throw ImageCheckError("Could not create the source CGImage.")
        }
        let image = NSImage(cgImage: source, size: CGSize(width: 300, height: 200))
        try require(image.size == CGSize(width: 300, height: 200),
                    "Source NSImage does not use the expected 300×200 point size.")

        let png = try encodedBitmap(image, format: .png)
        let jpeg = try encodedBitmap(image, format: .jpeg)
        for (name, bitmap) in [("PNG", png), ("JPEG", jpeg)] {
            try require(bitmap.pixelsWide == width && bitmap.pixelsHigh == height,
                        "\(name) changed source dimensions to \(bitmap.pixelsWide)×\(bitmap.pixelsHigh).")
        }

        guard let pngCenter = png.colorAt(x: width / 2, y: height / 2)?.usingColorSpace(.sRGB),
              let jpegCenter = jpeg.colorAt(x: width / 2, y: height / 2)?.usingColorSpace(.sRGB) else {
            throw ImageCheckError("Could not sample the decoded image pixels.")
        }
        try require(png.hasAlpha && pngCenter.alphaComponent < 0.01,
                    "PNG did not preserve the transparent center pixel.")
        try require(!jpeg.hasAlpha && jpegCenter.alphaComponent > 0.99,
                    "JPEG was not encoded as an opaque image.")
        try require(jpegCenter.redComponent > 0.97 && jpegCenter.greenComponent > 0.97 && jpegCenter.blueComponent > 0.97,
                    "JPEG transparency did not composite onto white.")
    }

    private static func encodedBitmap(_ image: NSImage, format: ScreenshotFormat) throws -> NSBitmapImageRep {
        guard let data = image.encoded(as: format), let bitmap = NSBitmapImageRep(data: data) else {
            throw ImageCheckError("Could not encode and decode \(format.title).")
        }
        return bitmap
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ImageCheckError(message) }
    }
}

private struct ImageCheckError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
