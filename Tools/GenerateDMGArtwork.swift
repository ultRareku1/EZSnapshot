import AppKit

// Finder uses point coordinates; both representations retain a 760 × 500 point size.
let canvas = NSSize(width: 760, height: 500)
let scale: CGFloat = 2
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/dmg-artwork", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

let paper = color(0xF7F8F5)
let forest = color(0x315E51)
let ink = color(0x26372E)
let secondary = color(0x788278)
let border = color(0xDFE4DB)

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height - y - height, width: width, height: height)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height), xRadius: radius, yRadius: radius)
}

func text(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat,
          size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink,
          alignment: NSTextAlignment = .left, tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
        .kern: tracking
    ]
    (string as NSString).draw(in: rect(x, y, width, size * 1.55), withAttributes: attributes)
}

func line(from: NSPoint, to: NSPoint, color: NSColor, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: from.x, y: canvas.height - from.y))
    path.line(to: NSPoint(x: to.x, y: canvas.height - to.y))
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func mark(x: CGFloat, y: CGFloat, size: CGFloat) {
    let outer = roundedRect(x, y, size, size, radius: size * 0.27)
    NSGradient(starting: color(0x548773), ending: color(0x294F3E))!.draw(in: outer, angle: 60)
    color(0xFFFFFF, alpha: 0.18).setStroke()
    outer.lineWidth = 0.7
    outer.stroke()

    let frame = NSBezierPath()
    let min: CGFloat = size * 0.26
    let max: CGFloat = size * 0.74
    let arm: CGFloat = size * 0.13
    for (px, py, dx, dy) in [(min, min, arm, arm), (max, min, -arm, arm),
                              (min, max, arm, -arm), (max, max, -arm, -arm)] {
        frame.move(to: NSPoint(x: x + px + dx, y: canvas.height - y - py))
        frame.line(to: NSPoint(x: x + px, y: canvas.height - y - py))
        frame.line(to: NSPoint(x: x + px, y: canvas.height - y - py - dy))
    }
    frame.lineWidth = size * 0.036
    frame.lineCapStyle = .round
    frame.lineJoinStyle = .round
    NSColor.white.setStroke()
    frame.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: rect(x + size * 0.456, y + size * 0.456, size * 0.088, size * 0.088)).fill()
}

func well(centerX: CGFloat) {
    let panel = roundedRect(centerX - 108, 171, 216, 205, radius: 30)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = forest.withAlphaComponent(0.035)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    color(0xFFFFFF, alpha: 0.65).setFill()
    panel.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0xDCE5DD, alpha: 0.65).setStroke()
    panel.lineWidth = 0.7
    panel.stroke()
}

func render(preview: Bool) -> NSBitmapImageRep {
    let representation = NSBitmapImageRep(bitmapDataPlanes: nil,
                                          pixelsWide: Int(canvas.width * scale),
                                          pixelsHigh: Int(canvas.height * scale),
                                          bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)!
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: scale, y: scale)

    paper.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()

    // Broad, quiet pools of green provide depth without competing with Finder icons.
    cg.saveGState()
    let haloColors = [color(0xC8DBC9, alpha: 0.32).cgColor, color(0xC8DBC9, alpha: 0).cgColor]
    let halo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: haloColors as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(halo, startCenter: CGPoint(x: 757, y: 506), startRadius: 0,
                          endCenter: CGPoint(x: 757, y: 506), endRadius: 330, options: .drawsBeforeStartLocation)
    let lowColors = [color(0xDDE7D6, alpha: 0.32).cgColor, color(0xDDE7D6, alpha: 0).cgColor]
    let lowHalo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: lowColors as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(lowHalo, startCenter: CGPoint(x: 0, y: -18), startRadius: 0,
                          endCenter: CGPoint(x: 0, y: -18), endRadius: 300, options: .drawsBeforeStartLocation)
    cg.restoreGState()

    mark(x: 50, y: 43, size: 43)
    text("EZSnapshot", x: 108, y: 41, width: 224, size: 32, weight: .semibold, tracking: -0.9)
    forest.withAlphaComponent(0.075).setFill()
    roundedRect(303, 48, 49, 24, radius: 12).fill()
    text("v1.0", x: 303, y: 52.2, width: 49, size: 11, weight: .semibold, color: forest, alignment: .center)
    text("INITIAL RELEASE", x: 538, y: 56, width: 172, size: 9.4, weight: .medium,
         color: secondary, alignment: .right, tracking: 1.5)
    text("Your screen. Beautifully captured.", x: 108, y: 86, width: 450, size: 14,
         color: secondary, tracking: 0.05)
    line(from: NSPoint(x: 50, y: 131), to: NSPoint(x: 710, y: 131), color: border.withAlphaComponent(0.72), width: 0.7)

    well(centerX: 205)
    well(centerX: 555)

    // These slots deliberately remain empty: Finder draws the actual app and alias icons.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 351, y: canvas.height - 265))
    arrow.line(to: NSPoint(x: 409, y: canvas.height - 265))
    arrow.move(to: NSPoint(x: 401, y: canvas.height - 257))
    arrow.line(to: NSPoint(x: 409, y: canvas.height - 265))
    arrow.line(to: NSPoint(x: 401, y: canvas.height - 273))
    arrow.lineWidth = 1.8
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    forest.withAlphaComponent(0.66).setStroke()
    arrow.stroke()

    text("Drag EZSnapshot to Applications", x: 100, y: 413, width: 560, size: 15,
         weight: .medium, color: forest, alignment: .center, tracking: -0.1)
    text("拖入 Applications 文件夹即可安装", x: 100, y: 438, width: 560, size: 11,
         color: secondary, alignment: .center, tracking: 0.15)
    text("Apple Silicon  ·  macOS 14+", x: 50, y: 475, width: 325, size: 10,
         color: secondary.withAlphaComponent(0.85))
    text("© 2026 ultRareku", x: 455, y: 475, width: 255, size: 10,
         color: secondary.withAlphaComponent(0.85), alignment: .right)

    if preview {
        let iconURL = URL(fileURLWithPath: "build/AppIcon.iconset/icon_128x128@2x.png")
        if let appIcon = NSImage(contentsOf: iconURL) {
            appIcon.draw(in: rect(141, 201, 128, 128))
        }
        let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
        folderIcon.draw(in: rect(491, 201, 128, 128))
        text("EZSnapshot", x: 97, y: 342, width: 216, size: 13, alignment: .center)
        text("Applications", x: 447, y: 342, width: 216, size: 13, alignment: .center)
    }
    NSGraphicsContext.restoreGraphicsState()
    representation.size = canvas
    return representation
}

let artwork = render(preview: false)
try artwork.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("background.png"))
try artwork.representation(using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])!
    .write(to: output.appendingPathComponent("background.tiff"))
let preview = render(preview: true)
try preview.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("preview.png"))
print("Created 760 × 500 point Retina DMG artwork at \(output.path)")
