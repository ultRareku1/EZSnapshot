import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedBinding: Binding<ScreenshotRecord?> {
        Binding(get: { state.selectedRecord }, set: { state.selectedID = $0?.id })
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Rectangle().fill(Palette.border).frame(width: 1)
            Group {
                switch state.section {
                case .capture: CaptureView()
                case .record: RecordingView()
                case .library, .favorites: LibraryView()
                case .settings: SettingsView()
                }
            }
            .id(state.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
        }
        .frame(minWidth: 1020, minHeight: 720)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Palette.border))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .padding(.bottom, 22)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: selectedBinding) { record in ScreenshotDetailView(recordID: record.id).environmentObject(state) }
        .sheet(item: $state.renameRecord) { record in RenameView(record: record).environmentObject(state) }
        .alert(item: $state.alert) { alert in
            if alert.title == state.text(.permissionRequired) {
                return Alert(title: Text(alert.title), message: Text(alert.message),
                             primaryButton: .default(Text(state.text(.openSystemSettings))) { CaptureService.openPermissionSettings() },
                             secondaryButton: .cancel(Text(state.text(.cancel))))
            }
            return Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(state.text(.done))))
        }
        .confirmationDialog(state.text(.deleteCapture), isPresented: Binding(
            get: { state.recordToDelete != nil },
            set: { if !$0 { state.recordToDelete = nil } }
        ), titleVisibility: .visible) {
            Button(state.text(.delete), role: .destructive) { if let record = state.recordToDelete { state.delete(record) } }
            Button(state.text(.cancel), role: .cancel) { state.recordToDelete = nil }
        } message: { Text(state.text(.deleteCaptureMessage)) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshPermission() }
        .alert(state.text(.quitWhileRecording), isPresented: $state.showRecordingQuitDialog) {
            Button(state.text(.keepRecording), role: .cancel) {}
            Button(state.text(.stopAndQuit)) { state.stopRecordingAndQuit() }
        } message: { Text(state.text(.recordingQuitMessage)) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark()
                Text("EZSnapshot").font(.system(size: 16, weight: .semibold, design: .rounded)).tracking(-0.5)
            }.padding(.horizontal, 22).padding(.top, 54).padding(.bottom, 38)
            VStack(spacing: 7) {
                ForEach([AppSection.capture, .record, .library, .favorites]) { section in navigationButton(section) }
            }.padding(.horizontal, 13)
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Circle().fill(state.recordingPhase == .recording ? .red : (state.permissionGranted ? Palette.accent : Color.orange)).frame(width: 5, height: 5)
                    Text(state.text(state.recordingPhase == .recording ? .recording : (state.isCapturing ? .capturing : (state.permissionGranted ? .readyToCapture : .permissionRequired))))
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(2)
                }.padding(.horizontal, 12)
                Rectangle().fill(Palette.border).frame(height: 1).padding(.horizontal, 10)
                navigationButton(.settings)
                HStack {
                    Text("EZSnapshot").font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("1.1").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(Palette.secondary.opacity(0.8)).padding(.horizontal, 12)
            }.padding(.horizontal, 13).padding(.bottom, 23)
        }.background(Palette.sidebar)
    }

    private func navigationButton(_ section: AppSection) -> some View {
        let isSelected = state.section == section
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                state.section = section
                state.search = ""
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.symbol).font(.system(size: 14, weight: isSelected ? .semibold : .regular)).frame(width: 20)
                Text(state.text(section.titleKey)).font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 2)
                if section == .library && !state.records.isEmpty {
                    Text("\(state.records.count)").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                }
                if section == .favorites && state.favoriteCount > 0 {
                    Text("\(state.favoriteCount)").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .foregroundStyle(isSelected ? Palette.accent : Palette.secondary)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(isSelected ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Palette.border.opacity(0.7) : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CaptureView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionHeading(title: state.text(.newCapture), subtitle: state.text(.captureSubtitle))
                    Spacer()
                    Text(state.mode.shortcut).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondary).padding(8)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .help(state.text(.keyboardShortcutsHint))
                }
                hero
                HStack(spacing: 12) {
                    ForEach(CaptureMode.allCases) { mode in modeCard(mode) }
                }
                HStack {
                    Label(state.text(.fileFormat), systemImage: "doc")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Picker(state.text(.fileFormat), selection: $state.format) {
                        ForEach(ScreenshotFormat.allCases) { format in Text(format.title).tag(format) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 112)
                    Rectangle().fill(Palette.border).frame(width: 1, height: 18).padding(.horizontal, 10)
                    Image(systemName: "timer").foregroundStyle(Palette.secondary)
                    Picker(state.text(.captureDelay), selection: $state.captureDelay) {
                        Text(state.text(.noDelay)).tag(0)
                        ForEach([3, 5, 10], id: \.self) { delay in Text("\(delay) \(state.text(.seconds))").tag(delay) }
                    }.labelsHidden().frame(width: 135)
                    Spacer()
                    Button { state.capture() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: state.mode.symbol)
                            Text(state.text(state.isCapturing ? .capturing : .captureNow))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(state.isCapturing || state.recordingPhase.isBusy)
                }.padding(.top, 1)
                if !state.permissionGranted { permissionCard }
                recentSection
            }.padding(.horizontal, 34).padding(.top, 48).padding(.bottom, 32)
        }.scrollIndicators(.hidden)
    }

    private var hero: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 15) {
                Text(state.text(.welcomeTitle))
                    .font(.system(size: 35, weight: .medium, design: .rounded))
                    .tracking(-1.2).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Palette.ink)
                Text(state.text(.welcomeSubtitle)).font(.system(size: 12))
                    .foregroundStyle(Palette.secondary).lineSpacing(4).frame(maxWidth: 260, alignment: .leading)
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").font(.system(size: 10))
                    Text(state.text(.privacy)).font(.system(size: 10, weight: .medium))
                }.foregroundStyle(Palette.accent).padding(.top, 9)
            }.frame(maxWidth: .infinity, alignment: .leading)
            CaptureIllustration().frame(width: 300, height: 224).accessibilityHidden(true)
        }
        .padding(.horizontal, 30).padding(.vertical, 22)
        .background(Palette.accentSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.border.opacity(0.75)))
    }

    private func modeCard(_ mode: CaptureMode) -> some View {
        let selected = state.mode == mode
        return Button { state.mode = mode } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: mode.symbol).font(.system(size: 21, weight: .light))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                    } else {
                        Text(mode.shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                }.foregroundStyle(Palette.accent)
                Text(state.text(mode.titleKey)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(state.text(mode.hintKey)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .lineLimit(2).frame(height: 28, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(selected ? Palette.surface : Palette.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Palette.accent.opacity(0.75) : Palette.border, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var permissionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.system(size: 18)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.text(.permissionRequired)).font(.system(size: 12, weight: .semibold))
                Text(state.text(.permissionMessage)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button(state.text(.enableAccess)) { state.requestPermission() }.buttonStyle(QuietButtonStyle())
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(state.text(.recentCaptures)).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { state.section = .library } label: {
                    HStack(spacing: 5) { Text(state.text(.viewAll)); Image(systemName: "arrow.right").font(.system(size: 9)) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if state.records.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.text(.noCaptures)).font(.system(size: 12, weight: .medium))
                        Text(state.text(.noCapturesHint)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }.padding(20).frame(maxWidth: .infinity)
                    .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(state.records.prefix(3))) { record in ScreenshotCard(record: record) }
                    if state.records.count < 3 { Spacer(minLength: 0) }
                }
            }
        }
    }
}

struct CaptureIllustration: View {
    var isVideo = false
    var body: some View {
        ZStack {
            Circle().fill(Palette.surface.opacity(0.5)).frame(width: 215, height: 215).offset(x: 25, y: 0)
            RoundedRectangle(cornerRadius: 14).fill(Palette.surface.opacity(0.8))
                .frame(width: 218, height: 144).rotationEffect(.degrees(-8)).offset(x: -17, y: -4)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border).frame(width: 218, height: 144)
                    .rotationEffect(.degrees(-8)).offset(x: -17, y: -4))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.64, green: 0.76, blue: 0.67),
                                                  Color(red: 0.28, green: 0.47, blue: 0.38)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse().fill(Color(red: 0.80, green: 0.87, blue: 0.71)).frame(width: 280, height: 150)
                    .rotationEffect(.degrees(-22)).offset(x: -102, y: 80)
                Ellipse().fill(Color(red: 0.39, green: 0.57, blue: 0.45)).frame(width: 245, height: 130)
                    .rotationEffect(.degrees(-25)).offset(x: 44, y: 100)
                Circle().fill(Color(red: 0.92, green: 0.93, blue: 0.79)).frame(width: 40, height: 40).offset(x: 149, y: 31)
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5) }
                }.padding(12)
                RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 140, height: 91).offset(x: 39, y: 34)
                Image(systemName: "plus").font(.system(size: 13, weight: .ultraLight)).foregroundStyle(.white)
                    .offset(x: 104, y: 73)
            }.frame(width: 218, height: 144).clipShape(RoundedRectangle(cornerRadius: 14))
                .rotationEffect(.degrees(5)).offset(x: 20, y: -6)
                .shadow(color: Palette.accent.opacity(0.18), radius: 17, y: 12)
            HStack(spacing: 7) {
                Image(systemName: isVideo ? "record.circle" : "checkmark").font(.system(size: 10, weight: .semibold))
                Text(isVideo ? "MP4" : "PNG").font(.system(size: 10, weight: .semibold, design: .monospaced))
            }.foregroundStyle(Palette.accent).padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.surface, in: Capsule()).shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                .offset(x: 76, y: 77)
            Image(systemName: "cursorarrow").font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.ink).shadow(color: .white.opacity(0.5), radius: 0, x: 1, y: 1)
                .offset(x: 101, y: 52)
        }
    }
}
