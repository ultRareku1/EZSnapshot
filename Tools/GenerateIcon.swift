import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 66, y: 66, width: 892, height: 892), xRadius: 204, yRadius: 204)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.17, green: 0.34, blue: 0.27, alpha: 1),
                              ending: NSColor(srgbRed: 0.36, green: 0.56, blue: 0.44, alpha: 1))!
    gradient.draw(in: outer, angle: 60)
    NSColor.white.withAlphaComponent(0.15).setStroke()
    outer.lineWidth = 3
    outer.stroke()
    NSColor.white.withAlphaComponent(0.95).setStroke()
    let frame = NSBezierPath()
    let near: CGFloat = 281
    let far: CGFloat = 743
    let arm: CGFloat = 106
    for (x, y, dx, dy) in [(near, near, arm, arm), (far, near, -arm, arm),
                            (near, far, arm, -arm), (far, far, -arm, -arm)] {
        frame.move(to: NSPoint(x: x + dx, y: y))
        frame.line(to: NSPoint(x: x + 27 * (dx > 0 ? 1 : -1), y: y))
        frame.curve(to: NSPoint(x: x, y: y + 27 * (dy > 0 ? 1 : -1)),
                    controlPoint1: NSPoint(x: x, y: y),
                    controlPoint2: NSPoint(x: x, y: y))
        frame.line(to: NSPoint(x: x, y: y + dy))
    }
    frame.lineWidth = 35
    frame.lineCapStyle = .round
    frame.lineJoinStyle = .round
    frame.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 464, y: 464, width: 96, height: 96)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let names: [Int: [String]] = [
        16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"]
    ]
    for name in names[size]! { try data.write(to: destination.appendingPathComponent(name)) }
}
