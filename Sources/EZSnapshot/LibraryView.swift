import SwiftUI
import AppKit
import AVKit

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 18)]
    private var isFavorites: Bool { state.section == .favorites }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                SectionHeading(title: state.text(isFavorites ? .favorites : .library),
                               subtitle: "\(state.filteredRecords.count) \(state.text(.captures))")
                Spacer()
                Button { state.capture() } label: {
                    Label(state.text(.newCapture), systemImage: "plus")
                }.buttonStyle(PrimaryButtonStyle(compact: true)).disabled(state.isCapturing || state.recordingPhase.isBusy)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField(state.text(.searchCaptures), text: $state.search).textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !state.search.isEmpty {
                    Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.secondary).help(state.text(.clearSearch))
                }
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
            if state.filteredRecords.isEmpty {
                Spacer()
                EmptyState(symbol: isFavorites ? "star" : "photo.on.rectangle.angled",
                           title: state.text(isFavorites ? .noFavorites : .noCaptures),
                           subtitle: state.text(isFavorites ? .noFavoritesHint : .noCapturesHint))
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(state.filteredRecords) { record in ScreenshotCard(record: record) }
                    }.padding(.bottom, 25)
                }.scrollIndicators(.hidden)
            }
        }.padding(.horizontal, 34).padding(.top, 48).padding(.bottom, 20)
    }
}

struct ScreenshotCard: View {
    @EnvironmentObject private var state: AppState
    let record: ScreenshotRecord
    @State private var hovering = false
    var body: some View {
        Button { state.select(record) } label: {
            VStack(alignment: .leading, spacing: 11) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.accentSoft.opacity(0.6))
                    MediaThumbnail(record: record)
                    if record.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundStyle(Palette.accent).padding(7)
                            .background(Palette.surface, in: Circle()).padding(8)
                    }
                }.frame(height: 143).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(hovering ? Palette.accent.opacity(0.5) : Palette.border))
                    .overlay(alignment: .bottomTrailing) {
                        if record.isVideo {
                            Label(record.formattedDuration, systemImage: "play.fill")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 5)
                                .background(.black.opacity(0.65), in: Capsule()).padding(8)
                        }
                    }
                Text(record.name).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(Palette.ink)
                HStack(spacing: 5) {
                    Text(record.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Spacer(minLength: 0)
                    Text(record.dimensions)
                }.font(.system(size: 9)).foregroundStyle(Palette.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityLabel("\(record.name), \(record.dimensions)")
            .contextMenu {
                Button(state.text(.copy), systemImage: "doc.on.doc") { state.copy(record) }
                Button(state.text(record.isFavorite ? .unfavorite : .favorite), systemImage: record.isFavorite ? "star.slash" : "star") {
                    state.toggleFavorite(record)
                }
                Button(state.text(.rename), systemImage: "pencil") { state.renameRecord = record }
                Button(state.text(.export), systemImage: "square.and.arrow.up") { state.export(record) }
                Button(state.text(.showInFinder), systemImage: "folder") { state.reveal(record) }
                Divider()
                Button(state.text(.delete), systemImage: "trash", role: .destructive) { state.recordToDelete = record }
            }
    }
}

struct ScreenshotDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    @State private var scale: CGFloat = 1
    @State private var player: AVPlayer?
    private var record: ScreenshotRecord? { state.records.first { $0.id == recordID } }
    var body: some View {
        Group {
            if let record {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text("\(record.dimensions) · \(record.formattedSize)\(record.isVideo ? " · \(record.formattedDuration)" : "")").font(.system(size: 10))
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button { state.toggleFavorite(record) } label: {
                            Image(systemName: record.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(record.isFavorite ? Palette.accent : Palette.secondary)
                        }.buttonStyle(QuietButtonStyle())
                            .help(state.text(record.isFavorite ? .unfavorite : .favorite))
                        Button(state.text(.done)) { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.escape, modifiers: [])
                    }.padding(22)
                    Rectangle().fill(Palette.border).frame(height: 1)
                    GeometryReader { geometry in
                        ZStack {
                            Checkerboard().opacity(0.3)
                            if record.isVideo {
                                if FileManager.default.fileExists(atPath: record.filePath) {
                                    VideoPlayer(player: player).padding(20)
                                } else {
                                    EmptyState(symbol: "film", title: state.text(.videoMissing),
                                               subtitle: state.text(.videoMissingMessage))
                                }
                            } else if let image = NSImage(contentsOf: record.url) {
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: image).resizable().scaledToFit()
                                        .frame(width: max(geometry.size.width - 64, 1) * scale,
                                               height: max(geometry.size.height - 64, 1) * scale)
                                        .padding(32)
                                }
                            } else {
                                EmptyState(symbol: "photo.badge.exclamationmark", title: state.text(.fileMissing),
                                           subtitle: state.text(.fileMissingMessage))
                            }
                        }
                    }.background(Palette.sidebar)
                    Rectangle().fill(Palette.border).frame(height: 1)
                    HStack(spacing: 9) {
                        if !record.isVideo {
                            Button { scale = max(0.5, scale - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                                .help(state.text(.zoomOut))
                            Button { scale = 1 } label: { Text("\(Int(scale * 100))%").monospacedDigit().frame(width: 36) }
                                .help(state.text(.fitToWindow))
                            Button { scale = min(3, scale + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                                .help(state.text(.zoomIn))
                        } else {
                            Label("MP4", systemImage: "film").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button { state.reveal(record) } label: { Image(systemName: "folder") }
                            .help(state.text(.showInFinder))
                        ShareLink(item: record.url) { Image(systemName: "square.and.arrow.up") }.help(state.text(.share))
                        if !record.isVideo {
                            Button {
                                if NSImage(contentsOf: record.url) != nil { state.editorRecord = record }
                                else { state.missingFile() }
                            } label: {
                                Label(state.text(.openEditor), systemImage: "pencil.tip.crop.circle")
                            }.disabled(!FileManager.default.fileExists(atPath: record.filePath))
                        }
                        Button { state.copy(record) } label: { Label(state.text(.copy), systemImage: "doc.on.doc") }
                            .keyboardShortcut("c", modifiers: .command)
                        Button { state.export(record) } label: { Label(state.text(.export), systemImage: "arrow.down.to.line") }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    }.buttonStyle(QuietButtonStyle()).padding(18)
                }
            } else {
                EmptyState(symbol: "photo", title: state.text(.fileMissing), subtitle: state.text(.fileMissingMessage))
            }
        }.frame(width: 940, height: 670).background(Palette.background)
            .foregroundStyle(Palette.ink).tint(Palette.accent)
            .task(id: recordID) {
                player?.pause()
                if let record, record.isVideo {
                    player = AVPlayer(url: record.url)
                    player?.play()
                } else { player = nil }
            }
            .onDisappear { player?.pause(); player = nil }
            .sheet(item: $state.editorRecord) { editedRecord in
                if let image = NSImage(contentsOf: editedRecord.url) {
                    AnnotationEditor(image: image, language: state.language) { editedImage in
                        state.saveEdited(editedImage, original: editedRecord)
                    }
                } else {
                    VStack(spacing: 18) {
                        EmptyState(symbol: "photo.badge.exclamationmark", title: state.text(.fileMissing),
                                   subtitle: state.text(.fileMissingMessage))
                        Button(state.text(.done)) { state.editorRecord = nil }
                    }.padding(25).frame(width: 450)
                }
            }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Palette.border))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct RenameView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let record: ScreenshotRecord
    @State private var name: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(state.text(.rename)).font(.system(size: 19, weight: .semibold))
            TextField(state.text(.name), text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(state.text(.cancel)) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button(state.text(.save)) { state.rename(record, to: name) }
                    .keyboardShortcut(.return, modifiers: []).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(26).frame(width: 420).onAppear { name = record.name }
    }
}
