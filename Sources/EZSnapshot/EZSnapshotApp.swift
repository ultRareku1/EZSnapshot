import SwiftUI
import AppKit

@main
struct EZSnapshotApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(EZSnapshotDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("EZSnapshot", id: "main") {
            MainView()
                .environmentObject(state)
                .environment(\.locale, Locale(identifier: state.language.localeIdentifier))
                .preferredColorScheme(state.appearance.colorScheme)
                .onAppear { delegate.configure(state: state) }
        }
        .defaultSize(width: 1160, height: 810)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(state.text(.menuAbout)) { showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button(state.text(.menuOpenMainWindow)) { showMain() }.keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button(state.text(.menuOpenSettings)) { state.section = .settings; showMain() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu(state.text(.capture)) {
                Button(state.text(.menuCaptureRegion)) { state.capture(.region) }.keyboardShortcut("1", modifiers: [.control, .option])
                Button(state.text(.menuCaptureWindow)) { state.capture(.window) }.keyboardShortcut("2", modifiers: [.control, .option])
                Button(state.text(.menuCaptureFullScreen)) { state.capture(.fullScreen) }.keyboardShortcut("3", modifiers: [.control, .option])
                Divider()
                Button(state.text(state.recordingPhase == .recording ? .stopRecording : .startRecording)) {
                    state.toggleRecording()
                }.keyboardShortcut("4", modifiers: [.control, .option])
                    .disabled(state.recordingPhase == .preparing || state.recordingPhase == .selecting || state.recordingPhase == .finishing)
            }
        }
        Window(state.text(.menuAbout), id: "about") {
            AboutView()
                .environmentObject(state)
                .environment(\.locale, Locale(identifier: state.language.localeIdentifier))
                .preferredColorScheme(state.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        MenuBarExtra {
            Text("EZSnapshot").font(.headline)
            if state.recordingPhase == .recording {
                Text("\(state.text(.recording)) · \(state.recordingTime)")
                Button(state.text(.stopRecording)) { state.stopRecording() }
                    .keyboardShortcut("4", modifiers: [.control, .option])
            } else if state.recordingPhase.isBusy {
                Text(state.text(state.recordingPhase == .finishing ? .finishingRecording : .preparingRecording))
            } else {
                Button(state.text(.startRecording)) { state.section = .record; showMain(); state.refreshRecordingSources() }
            }
            Divider()
            ForEach(CaptureMode.allCases) { mode in
                Button { state.capture(mode) } label: { Label(state.text(mode.titleKey), systemImage: mode.symbol) }
                    .disabled(state.isCapturing || state.recordingPhase.isBusy)
            }
            Divider()
            Button(state.text(.menuOpenMainWindow)) { showMain() }
            Button(state.text(.menuOpenSettings)) { state.section = .settings; showMain() }
            Button(state.text(.menuAbout)) { showAbout() }
            Divider()
            Button(state.text(.menuQuit)) { NSApp.terminate(nil) }
        } label: {
            if state.recordingPhase == .recording {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                    Text(state.recordingTime).monospacedDigit()
                }
            } else {
                Image(systemName: state.recordingPhase == .finishing ? "hourglass" : "viewfinder")
            }
        }
    }
    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showAbout() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class EZSnapshotDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: GlobalHotKeys?
    weak var state: AppState?
    func configure(state: AppState) {
        self.state = state
        guard hotKeys == nil else { return }
        let keys = GlobalHotKeys(onCapture: { [weak state] mode in state?.capture(mode) },
                                 onToggleRecording: { [weak state] in state?.toggleRecording() })
        keys.register()
        hotKeys = keys
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.recordingPhase.isBusy else { return .terminateNow }
        state.restoreWindow()
        state.showRecordingQuitDialog = true
        return .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.title == "EZSnapshot" }?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
