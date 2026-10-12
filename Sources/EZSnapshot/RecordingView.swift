import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeading(title: state.text(.newRecording), subtitle: state.text(.recordingSubtitle))
                    Spacer()
                    Text("⌃⌥4").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondary).padding(8)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .help(state.text(.recordShortcut))
                }
                if state.recordingPhase == .recording || state.recordingPhase == .finishing {
                    activeRecording
                } else {
                    if !state.permissionGranted { permissionCard }
                    hero
                    HStack(spacing: 12) {
                        ForEach(CaptureMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }.disabled(state.recordingPhase.isBusy)
                    if state.permissionGranted { sourceControls }
                    preferences
                    HStack(spacing: 16) {
                        Label("MP4 · H.264", systemImage: "film")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        Spacer()
                        if state.recordingPhase.isBusy { ProgressView().controlSize(.small) }
                        Button { state.startRecording() } label: {
                            Label(state.text(state.recordingPhase == .preparing ? .preparingRecording : .startRecording),
                                  systemImage: "record.circle")
                        }.buttonStyle(PrimaryButtonStyle()).disabled(!state.canStartRecording)
                    }
                }
            }.padding(.horizontal, 34).padding(.top, 48).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .task { state.refreshRecordingSources() }
        .onChange(of: state.permissionGranted) { _, granted in if granted { state.refreshRecordingSources() } }
    }

    private var permissionCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.text(.permissionRequired)).font(.system(size: 12, weight: .semibold))
                Text(state.text(.permissionRecordingMessage)).font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button(state.text(.enableAccess)) { state.requestPermission() }.buttonStyle(QuietButtonStyle())
        }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private var hero: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "record.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.accent)
                Text(state.text(.recordingFullScreenHint))
                    .font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.text(.nativeEncodingHint)).font(.system(size: 11))
                    .lineSpacing(4).foregroundStyle(Palette.secondary).frame(maxWidth: 300, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            CaptureIllustration(isVideo: true).scaleEffect(0.82).frame(width: 250, height: 154).accessibilityHidden(true)
        }.padding(.horizontal, 30).padding(.vertical, 18)
            .background(Palette.accentSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.border.opacity(0.75)))
    }

    private func modeCard(_ mode: CaptureMode) -> some View {
        let selected = state.recordingMode == mode
        let hint: L10nKey = mode == .region ? .recordingRegionHint : (mode == .window ? .recordingWindowHint : .recordingFullScreenHint)
        return Button { state.recordingMode = mode } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: mode.symbol).font(.system(size: 21, weight: .light))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                }.foregroundStyle(Palette.accent)
                Text(state.text(mode.titleKey)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(state.text(hint)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .lineLimit(2).frame(height: 28, alignment: .topLeading)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Palette.surface : Palette.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Palette.accent.opacity(0.75) : Palette.border, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: state.recordingMode == .window ? "macwindow" : "display")
                    .foregroundStyle(Palette.secondary)
                Text(state.text(.recordingSource)).font(.system(size: 12, weight: .medium))
                Spacer()
                if state.isLoadingRecordingSources {
                    ProgressView().controlSize(.small)
                } else if state.eligibleRecordingTargets.isEmpty {
                    Text(state.text(.noSources)).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Picker(state.text(.chooseSource), selection: $state.recordingTargetID) {
                        ForEach(state.eligibleRecordingTargets) { target in
                            Text(target.title).tag(Optional(target.id))
                        }
                    }.labelsHidden().frame(maxWidth: 340)
                }
                Button { state.refreshRecordingSources() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(QuietButtonStyle()).help(state.text(.refreshSources))
                    .disabled(state.isLoadingRecordingSources || !state.permissionGranted)
            }
            if state.recordingMode == .region {
                Divider().overlay(Palette.border)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.text(state.recordingRegion == nil ? .selectRegion : .regionSelected))
                            .font(.system(size: 12, weight: .medium))
                        if let rect = state.recordingRegion {
                            Text("\(Int(rect.width)) × \(Int(rect.height))")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                        } else {
                            Text(state.text(.regionSelectionHint)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    Button(state.text(state.recordingRegion == nil ? .selectRegion : .changeRegion)) {
                        state.selectRecordingRegion()
                    }.buttonStyle(QuietButtonStyle()).disabled(state.recordingTarget == nil)
                }
            }
        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
            .disabled(state.recordingPhase.isBusy || state.isCapturing)
    }

    private var preferences: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "speaker.wave.2").foregroundStyle(Palette.secondary)
                    Text(state.text(.systemAudio)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle(state.text(.systemAudio), isOn: $state.recordingAudio).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Text(state.text(.systemAudioHint)).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(Palette.border).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 7) {
                Text(state.text(.frameRate)).font(.system(size: 12, weight: .medium))
                Picker(state.text(.frameRate), selection: $state.recordingFPS) {
                    Text("30 \(state.text(.framesPerSecond))").tag(30)
                    Text("60 \(state.text(.framesPerSecond))").tag(60)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
            }
            Rectangle().fill(Palette.border).frame(width: 1, height: 42)
            VStack(alignment: .leading, spacing: 7) {
                Text(state.text(.includeCursor)).font(.system(size: 12, weight: .medium))
                Toggle(state.text(.includeCursor), isOn: $state.recordingCursor).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
            .disabled(state.recordingPhase.isBusy)
    }

    private var activeRecording: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle().fill(Palette.accentSoft).frame(width: 82, height: 82)
                Image(systemName: "record.circle").font(.system(size: 40, weight: .light)).foregroundStyle(.red)
            }
            Text(state.text(state.recordingPhase == .finishing ? .finishingRecording : .recordingInProgress))
                .font(.system(size: 22, weight: .medium, design: .rounded))
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(ScreenshotRecord.timeString(state.recordingElapsed))
                    .font(.system(size: 42, weight: .light, design: .monospaced)).monospacedDigit()
            }
            Text(state.text(.recordingStopHint)).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
            if state.recordingPhase == .finishing {
                ProgressView().controlSize(.small)
            } else {
                Button { state.stopRecording() } label: {
                    Label(state.text(.stopRecording), systemImage: "stop.fill")
                }.buttonStyle(PrimaryButtonStyle())
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 65).padding(.horizontal, 30)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.border))
    }
}
