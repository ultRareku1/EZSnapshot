import AppKit
import SwiftUI

/// An image-sized drawing surface: marks remain aligned when the sheet is resized,
/// and are exported at the screenshot's original pixel resolution.
struct AnnotationEditor: View {
    let image: NSImage
    let language: AppLanguage
    let onSave: (NSImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTool: AnnotationTool = .pen
    @State private var selectedInk: AnnotationInk = .blue
    @State private var lineWidth: Double = 6
    @State private var marks: [AnnotationMark] = []
    @State private var undoHistory: [[AnnotationMark]] = []
    @State private var activeMark: AnnotationMark?
    @State private var exportFailed = false

    init(image: NSImage, language: AppLanguage, onSave: @escaping (NSImage) -> Void) {
        self.image = image
        self.language = language
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            drawingControls
            Divider()
            canvas
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 860, idealWidth: 960, minHeight: 600, idealHeight: 680)
        .onDisappear { NSCursor.arrow.set() }
        .alert(language.string(.exportError), isPresented: $exportFailed) {
            Button(language.string(.done), role: .cancel) { }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.string(.editor))
                    .font(.system(size: 17, weight: .semibold))
                Text(language.string(.editingHint))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 16)
            Button(language.string(.cancel)) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(language.string(.saveChanges), action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var drawingControls: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        activeMark = nil
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedTool == tool ? Color.accentColor : Color.primary.opacity(0.75))
                            .frame(width: 36, height: 34)
                            .background {
                                if selectedTool == tool {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(language.string(tool.label))
                    .accessibilityLabel(language.string(tool.label))
                    .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
                }
            }

            Divider().frame(height: 24)

            HStack(spacing: 7) {
                ForEach(Array(AnnotationInk.allCases.enumerated()), id: \.element.id) { index, ink in
                    Button { selectedInk = ink } label: {
                        Circle()
                            .fill(Color(nsColor: ink.color))
                            .frame(width: 19, height: 19)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
                            .padding(3)
                            .overlay {
                                if selectedInk == ink {
                                    Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(language.string(.color)) \(index + 1)")
                    .accessibilityAddTraits(selectedInk == ink ? .isSelected : [])
                }
            }
            .help(language.string(.color))

            Divider().frame(height: 24)

            HStack(spacing: 8) {
                Image(systemName: "lineweight")
                    .foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 2...16, step: 1)
                    .frame(width: 105)
                    .accessibilityLabel(language.string(.lineWidth))
                Text("\(Int(lineWidth))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            .help(language.string(.lineWidth))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .help(language.string(.undo))
                .accessibilityLabel(language.string(.undo))
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoHistory.isEmpty)

                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .help(language.string(.reset))
                .accessibilityLabel(language.string(.reset))
                .disabled(marks.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let fittedSize = imageSizeFitted(in: geometry.size)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                ZStack(alignment: .topLeading) {
                    Color.white
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                    Canvas { context, size in
                        for mark in marks {
                            draw(mark, in: &context, size: size)
                        }
                        if let activeMark {
                            draw(activeMark, in: &context, size: size)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .clipped()
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
                .contentShape(Rectangle())
                .gesture(drawingGesture(in: fittedSize))
                .onHover { hovering in
                    if hovering { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(language.string(.editor))
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(language.string(selectedTool.label), systemImage: selectedTool.symbol)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(pixelSize.width) × \(pixelSize.height)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var pixelSize: (width: Int, height: Int) {
        if let bitmap = sourceCGImage {
            return (bitmap.width, bitmap.height)
        }
        return (max(1, Int(image.size.width)), max(1, Int(image.size.height)))
    }

    private var sourceCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private func imageSizeFitted(in available: CGSize) -> CGSize {
        let width = max(1, image.size.width)
        let height = max(1, image.size.height)
        let scale = min(max(1, available.width - 56) / width, max(1, available.height - 48) / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = normalized(value.location, in: size)
                if activeMark == nil {
                    activeMark = AnnotationMark(
                        tool: selectedTool,
                        ink: selectedInk,
                        width: CGFloat(lineWidth) / 1_000,
                        points: [normalized(value.startLocation, in: size)]
                    )
                }
                guard var mark = activeMark else { return }
                if mark.tool == .pen {
                    if let previous = mark.points.last,
                       hypot(point.x - previous.x, point.y - previous.y) > 0.0003 {
                        mark.points.append(point)
                    }
                } else {
                    mark.points = [mark.points[0], point]
                }
                activeMark = mark
            }
            .onEnded { value in
                guard var mark = activeMark else { return }
                let point = normalized(value.location, in: size)
                if mark.tool == .pen {
                    if let previous = mark.points.last,
                       hypot(point.x - previous.x, point.y - previous.y) > 0.0003 {
                        mark.points.append(point)
                    }
                } else {
                    mark.points = [mark.points[0], point]
                }
                activeMark = nil
                if mark.isVisible {
                    rememberUndo()
                    marks.append(mark)
                }
            }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x / max(1, size.width))),
            y: min(1, max(0, point.y / max(1, size.height)))
        )
    }

    private func draw(_ mark: AnnotationMark, in context: inout GraphicsContext, size: CGSize) {
        let path = Path(mark.path(in: size))
        let color = GraphicsContext.Shading.color(Color(nsColor: mark.ink.color))
        if mark.isDot {
            context.fill(path, with: color)
        } else {
            context.stroke(path, with: color, style: StrokeStyle(
                lineWidth: mark.pixelWidth(in: size), lineCap: .round, lineJoin: .round
            ))
        }
    }

    private func rememberUndo() {
        undoHistory.append(marks)
        if undoHistory.count > 100 { undoHistory.removeFirst() }
    }

    private func undo() {
        activeMark = nil
        guard let previous = undoHistory.popLast() else { return }
        marks = previous
    }

    private func reset() {
        activeMark = nil
        guard !marks.isEmpty else { return }
        rememberUndo()
        marks.removeAll()
    }

    private func save() {
        activeMark = nil
        guard let result = flattenedImage() else {
            exportFailed = true
            return
        }
        onSave(result)
        NSCursor.arrow.set()
        dismiss()
    }

    private func flattenedImage() -> NSImage? {
        guard !marks.isEmpty else { return image }
        guard let original = sourceCGImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                data: nil, width: original.width, height: original.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let size = CGSize(width: original.width, height: original.height)
        bitmap.draw(original, in: CGRect(origin: .zero, size: size))

        // UI coordinates start at the top left. Export uses source pixels, never
        // the window's backing scale, so Retina screenshots keep all their detail.
        bitmap.translateBy(x: 0, y: size.height)
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.setShouldAntialias(true)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        if let context = NSGraphicsContext.current?.cgContext {
            for mark in marks {
                context.setStrokeColor(mark.ink.color.cgColor)
                context.setFillColor(mark.ink.color.cgColor)
                context.setLineWidth(mark.pixelWidth(in: size))
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(mark.path(in: size))
                if mark.isDot { context.fillPath() } else { context.strokePath() }
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let output = bitmap.makeImage() else { return nil }
        return NSImage(cgImage: output, size: image.size)
    }
}

private enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen, rectangle, ellipse, arrow

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        }
    }

    var label: L10nKey {
        switch self {
        case .pen: .pen
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .arrow: .arrow
        }
    }
}

private enum AnnotationInk: String, CaseIterable, Identifiable {
    case blue, red, orange, green, purple, white, black

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .blue: NSColor(srgbRed: 0.12, green: 0.48, blue: 1, alpha: 1)
        case .red: NSColor(srgbRed: 0.97, green: 0.22, blue: 0.29, alpha: 1)
        case .orange: NSColor(srgbRed: 1, green: 0.57, blue: 0.12, alpha: 1)
        case .green: NSColor(srgbRed: 0.12, green: 0.74, blue: 0.45, alpha: 1)
        case .purple: NSColor(srgbRed: 0.65, green: 0.35, blue: 1, alpha: 1)
        case .white: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        }
    }
}

private struct AnnotationMark {
    let tool: AnnotationTool
    let ink: AnnotationInk
    /// Width relative to the shorter side of the screenshot.
    let width: CGFloat
    var points: [CGPoint]

    var isDot: Bool { tool == .pen && points.count == 1 }

    var isVisible: Bool {
        guard let first = points.first else { return false }
        if tool == .pen { return true }
        guard let last = points.last, points.count > 1 else { return false }
        if tool == .arrow { return hypot(last.x - first.x, last.y - first.y) > 0.002 }
        return abs(last.x - first.x) > 0.002 && abs(last.y - first.y) > 0.002
    }

    func pixelWidth(in size: CGSize) -> CGFloat {
        max(0.5, min(size.width, size.height) * width)
    }

    func path(in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let firstPoint = points.first else { return path }
        let start = CGPoint(x: firstPoint.x * size.width, y: firstPoint.y * size.height)

        if isDot {
            let diameter = pixelWidth(in: size)
            path.addEllipse(in: CGRect(x: start.x - diameter / 2, y: start.y - diameter / 2,
                                      width: diameter, height: diameter))
            return path
        }

        let lastPoint = points.last ?? firstPoint
        let end = CGPoint(x: lastPoint.x * size.width, y: lastPoint.y * size.height)
        switch tool {
        case .pen:
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
        case .rectangle:
            path.addRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .ellipse:
            path.addEllipse(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .arrow:
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = hypot(end.x - start.x, end.y - start.y)
            let head = min(length * 0.45, max(pixelWidth(in: size) * 4, min(size.width, size.height) * 0.024))
            for direction in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x - head * cos(angle + direction),
                                        y: end.y - head * sin(angle + direction)))
            }
        }
        return path
    }
}
