import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                SectionHeading(title: state.text(.settings), subtitle: state.text(.madeForMac))
                settingsGroup(.general) {
                    settingsRow(.language, symbol: "globe") {
                        Picker(state.text(.language), selection: $state.language) {
                            Text("🌐 \(state.text(.systemDefault))").tag(AppLanguage.system)
                            Divider()
                            ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                                Text("\(language.flag)  \(language.nativeName)").tag(language)
                            }
                        }.labelsHidden().frame(width: 235)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.appearance, symbol: "circle.lefthalf.filled") {
                        Picker(state.text(.appearance), selection: $state.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in Text(state.text(appearance.titleKey)).tag(appearance) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 235)
                    }
                }
                settingsGroup(.capturePreferences) {
                    settingsRow(.saveLocation, symbol: "folder") {
                        HStack(spacing: 12) {
                            Text(state.saveFolder.lastPathComponent).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                .lineLimit(1).help(state.saveFolder.path)
                            Button(state.text(.chooseFolder)) { state.chooseFolder() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.fileFormat, symbol: "doc") {
                        Picker(state.text(.fileFormat), selection: $state.format) {
                            ForEach(ScreenshotFormat.allCases) { format in Text(format.title).tag(format) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.captureDelay, symbol: "timer") {
                        Picker(state.text(.captureDelay), selection: $state.captureDelay) {
                            Text(state.text(.noDelay)).tag(0)
                            ForEach([3, 5, 10], id: \.self) { delay in Text("\(delay) \(state.text(.seconds))").tag(delay) }
                        }.labelsHidden().frame(width: 140)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.includeCursor, symbol: "cursorarrow", detail: state.text(.fullScreen)) {
                        Toggle(state.text(.includeCursor), isOn: $state.includeCursor).labelsHidden().toggleStyle(.switch)
                    }
                }
                settingsGroup(.keyboardShortcuts) {
                    ForEach(CaptureMode.allCases) { mode in
                        settingsRow(mode.titleKey, symbol: mode.symbol) {
                            Text(mode.shortcut).font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Palette.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 6))
                        }
                        if mode != .fullScreen { Divider().overlay(Palette.border) }
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.recordShortcut, symbol: "record.circle") {
                        Text("⌃⌥4").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                settingsGroup(.recordingPreferences) {
                    settingsRow(.recordingFormat, symbol: "film") {
                        Text("MP4 · H.264 / AAC").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.frameRate, symbol: "speedometer") {
                        Picker(state.text(.frameRate), selection: $state.recordingFPS) {
                            Text("30 \(state.text(.framesPerSecond))").tag(30)
                            Text("60 \(state.text(.framesPerSecond))").tag(60)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.systemAudio, symbol: "speaker.wave.2", detail: state.text(.systemAudioHint)) {
                        Toggle(state.text(.systemAudio), isOn: $state.recordingAudio).labelsHidden().toggleStyle(.switch)
                    }
                    Divider().overlay(Palette.border)
                    settingsRow(.includeCursor, symbol: "cursorarrow", detail: state.text(.recordingCursorHint)) {
                        Toggle(state.text(.includeCursor), isOn: $state.recordingCursor).labelsHidden().toggleStyle(.switch)
                    }
                }
                settingsGroup(.privacy) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "lock.shield").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(state.text(.privacyHint)).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                            HStack {
                                Label(state.text(state.permissionGranted ? .accessGranted : .permissionRequired),
                                      systemImage: state.permissionGranted ? "checkmark.circle" : "exclamationmark.circle")
                                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
                                Spacer()
                                Button(state.text(state.permissionGranted ? .refreshAccess : .enableAccess)) {
                                    if state.permissionGranted { state.refreshPermission() } else { state.requestPermission() }
                                }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }.padding(.vertical, 3)
                }
                HStack(spacing: 11) {
                    AppMark(size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EZSnapshot").font(.system(size: 12, weight: .semibold))
                        Text("\(state.text(.version)) \(AppMetadata.version) · Apple Silicon").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button(state.text(.about)) { openWindow(id: "about") }.buttonStyle(QuietButtonStyle())
                }.padding(.horizontal, 4).padding(.bottom, 10)
            }.padding(.horizontal, 34).padding(.top, 48).padding(.bottom, 24)
        }.scrollIndicators(.hidden)
    }
    private func settingsGroup<Content: View>(_ key: L10nKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(state.text(key)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                .padding(.leading, 3)
            VStack(spacing: 0, content: content).padding(.horizontal, 18).padding(.vertical, 6)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
        }
    }
    private func settingsRow<Control: View>(_ key: L10nKey, symbol: String, detail: String? = nil,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.text(key)).font(.system(size: 12, weight: .medium))
                if let detail { Text(detail).font(.system(size: 9)).foregroundStyle(Palette.secondary) }
            }
            Spacer()
            control()
        }.padding(.vertical, 12)
    }
}
