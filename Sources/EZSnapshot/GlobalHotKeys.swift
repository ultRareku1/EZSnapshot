import Carbon
import Foundation

/// Carbon hot keys work while other apps are active without Accessibility access.
@MainActor
final class GlobalHotKeys {
    private let onCapture: (CaptureMode) -> Void
    private let onToggleRecording: () -> Void
    private let resources = HotKeyResources()
    private(set) var registrationFailures: [CaptureMode] = []
    private(set) var recordingShortcutUnavailable = false

    init(onCapture: @escaping (CaptureMode) -> Void, onToggleRecording: @escaping () -> Void = {}) {
        self.onCapture = onCapture
        self.onToggleRecording = onToggleRecording
    }

    func register() {
        resources.clear()
        registrationFailures.removeAll()
        recordingShortcutUnavailable = false

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            ezSnapshotHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &resources.handler
        )
        guard handlerStatus == noErr else {
            registrationFailures = CaptureMode.allCases
            recordingShortcutUnavailable = true
            return
        }

        let bindings: [(CaptureMode, UInt32, UInt32)] = [
            (.region, UInt32(kVK_ANSI_1), 1),
            (.window, UInt32(kVK_ANSI_2), 2),
            (.fullScreen, UInt32(kVK_ANSI_3), 3)
        ]
        for (mode, keyCode, id) in bindings {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                UInt32(controlKey | optionKey),
                EventHotKeyID(signature: ezSnapshotHotKeySignature, id: id),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                resources.keys.append(reference)
            } else {
                registrationFailures.append(mode)
            }
        }
        var recordingReference: EventHotKeyRef?
        let recordingStatus = RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(controlKey | optionKey),
                                                 EventHotKeyID(signature: ezSnapshotHotKeySignature, id: 4),
                                                 GetApplicationEventTarget(), 0, &recordingReference)
        if recordingStatus == noErr, let recordingReference { resources.keys.append(recordingReference) }
        else { recordingShortcutUnavailable = true }
    }

    fileprivate func handleHotKey(id: UInt32) {
        switch id {
        case 1: onCapture(.region)
        case 2: onCapture(.window)
        case 3: onCapture(.fullScreen)
        case 4: onToggleRecording()
        default: break
        }
    }

    deinit {
        resources.clear()
    }
}

private let ezSnapshotHotKeySignature: OSType = 0x455A534E // "EZSN"

private func ezSnapshotHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == ezSnapshotHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    let controller = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor [weak controller] in
        controller?.handleHotKey(id: id)
    }
    return noErr
}

/// References are owned by the main-actor controller. This box also permits
/// synchronous teardown from deinit without transferring raw Carbon pointers.
private final class HotKeyResources: @unchecked Sendable {
    var handler: EventHandlerRef?
    var keys: [EventHotKeyRef] = []

    func clear() {
        for key in keys { UnregisterEventHotKey(key) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
