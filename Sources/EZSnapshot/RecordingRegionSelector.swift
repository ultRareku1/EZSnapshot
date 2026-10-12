import AppKit
import ScreenCaptureKit

/// Selects a recording crop in the chosen display's logical coordinate space.
/// The result is measured in points from that display's top-left corner, which
/// is also the coordinate system used by SCStreamConfiguration.sourceRect.
@MainActor
final class RecordingRegionSelector: NSObject, NSWindowDelegate {
    private var selectionID: UUID?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var panel: RecordingSelectionPanel?
    private var observers: [NSObjectProtocol] = []

    func select(on display: SCDisplay, language: AppLanguage) async -> CGRect? {
        guard selectionID == nil, !Task.isCancelled,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
              }), screen.frame.width >= 32, screen.frame.height >= 32 else { return nil }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGRect?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                selectionID = id
                self.continuation = continuation
                showOverlay(on: screen, language: language, id: id)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(nil, id: id)
            }
        }
    }

    private func showOverlay(on screen: NSScreen, language: AppLanguage, id: UUID) {
        // AppKit frames use global bottom-left coordinates. Giving the panel
        // the exact NSScreen frame supports displays above/left of the primary
        // screen; its flipped content view supplies local top-left coordinates.
        let panel = RecordingSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self
        panel.setAccessibilityLabel(language.string(.selectRegion))

        let view = RecordingSelectionView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            language: language
        ) { [weak self] rect in
            self?.finish(rect, id: id)
        }
        panel.contentView = view
        self.panel = panel

        // A switch to another application, a disconnected display, or a Space
        // change must not leave an invisible pending picker or floating panel.
        for name in [NSApplication.didResignActiveNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish(nil, id: id) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish(nil, id: id) }
        })

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        panel.invalidateCursorRects(for: view)
    }

    private func finish(_ rect: CGRect?, id: UUID) {
        guard selectionID == id, let continuation else { return }
        // Clear the session before closing: windowWillClose and cancellation
        // notifications may re-enter this method, but can never resume twice.
        selectionID = nil
        self.continuation = nil
        let panel = self.panel
        self.panel = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close()
        continuation.resume(returning: rect)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === panel, let id = selectionID else { return }
        finish(nil, id: id)
    }
}

@MainActor
private final class RecordingSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class RecordingSelectionView: NSView {
    private let language: AppLanguage
    private let completion: (CGRect?) -> Void
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private let instructionCard = NSVisualEffectView()

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, language: AppLanguage, completion: @escaping (CGRect?) -> Void) {
        self.language = language
        self.completion = completion
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(language.string(.selectRegion))
        setAccessibilityHelp(language.string(.regionSelectionHint))
        configureInstructions()
    }

    required init?(coder: NSCoder) { nil }

    private func configureInstructions() {
        instructionCard.material = .hudWindow
        instructionCard.blendingMode = .withinWindow
        instructionCard.state = .active
        instructionCard.appearance = NSAppearance(named: .darkAqua)
        instructionCard.wantsLayer = true
        instructionCard.layer?.cornerRadius = 16
        instructionCard.layer?.masksToBounds = true
        instructionCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(instructionCard)

        let title = NSTextField(labelWithString: language.string(.selectRegion))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .white
        let hint = NSTextField(wrappingLabelWithString: language.string(.regionSelectionHint))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor.white.withAlphaComponent(0.78)
        hint.maximumNumberOfLines = 3
        let labels = NSStackView(views: [title, hint])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5

        let cancel = NSButton(title: "\(language.string(.cancel))  ⎋", target: self, action: #selector(cancelSelection(_:)))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .regular
        cancel.font = .systemFont(ofSize: 12, weight: .medium)
        cancel.setAccessibilityLabel(language.string(.cancelRecording))
        cancel.setContentHuggingPriority(.required, for: .horizontal)
        let content = NSStackView(views: [labels, cancel])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false
        instructionCard.addSubview(content)
        NSLayoutConstraint.activate([
            instructionCard.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            instructionCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            instructionCard.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            content.leadingAnchor.constraint(equalTo: instructionCard.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: instructionCard.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: instructionCard.topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: instructionCard.bottomAnchor, constant: -15),
            labels.widthAnchor.constraint(lessThanOrEqualToConstant: 460)
        ])
    }

    override func resetCursorRects() {
        // AppKit owns cursor restoration when this view/window disappears.
        // There is no process-wide cursor push to leak on a cancellation path.
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = clampedPoint(for: event)
        selection = nil
        instructionCard.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = clampedPoint(for: event)
        selection = CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(start.x - current.x), height: abs(start.y - current.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        dragStart = nil
        guard let selection, selection.width >= 32, selection.height >= 32 else {
            completion(nil)
            return
        }
        completion(selection.integral.intersection(bounds))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion(nil) }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { completion(nil) }

    @objc private func cancelSelection(_ sender: Any?) { completion(nil) }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        let shade = NSBezierPath(rect: bounds)
        if let selection, selection.width > 0, selection.height > 0 {
            shade.append(NSBezierPath(rect: selection))
            shade.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.36).setFill()
        shade.fill()

        guard let selection, selection.width > 0, selection.height > 0 else { return }
        let outline = NSBezierPath(rect: selection.insetBy(dx: 0.75, dy: 0.75))
        outline.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.95).setStroke()
        outline.stroke()
        drawCorners(of: selection)
        drawSizeBadge(for: selection)
    }

    private func drawCorners(of rect: CGRect) {
        let length = min(14, min(rect.width, rect.height) / 3)
        let corners = [(rect.minX, rect.minY, 1.0, 1.0),
                       (rect.maxX, rect.minY, -1.0, 1.0),
                       (rect.minX, rect.maxY, 1.0, -1.0),
                       (rect.maxX, rect.maxY, -1.0, -1.0)]
        let brackets = NSBezierPath()
        for (x, y, dx, dy) in corners {
            brackets.move(to: NSPoint(x: x + dx * length, y: y))
            brackets.line(to: NSPoint(x: x, y: y))
            brackets.line(to: NSPoint(x: x, y: y + dy * length))
        }
        brackets.lineWidth = 3
        brackets.lineCapStyle = .round
        NSColor(srgbRed: 0.68, green: 0.89, blue: 0.77, alpha: 1).setStroke()
        brackets.stroke()
    }

    private func drawSizeBadge(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let badgeSize = NSSize(width: size.width + 24, height: 28)
        let x = min(max(rect.midX - badgeSize.width / 2, 8), max(8, bounds.width - badgeSize.width - 8))
        let preferredY = rect.maxY + 12
        let y = preferredY + badgeSize.height <= bounds.maxY - 8
            ? preferredY : max(8, rect.minY - badgeSize.height - 12)
        let badge = NSRect(origin: NSPoint(x: x, y: y), size: badgeSize)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 9, yRadius: 9).fill()
        text.draw(at: NSPoint(x: badge.minX + 12, y: badge.minY + (badge.height - size.height) / 2), withAttributes: attributes)
    }
}
