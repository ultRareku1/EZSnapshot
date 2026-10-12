import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            AppMark(size: 84).padding(.top, 28)
                .shadow(color: Palette.accent.opacity(0.12), radius: 14, y: 8)
            Text("EZSnapshot").font(.system(size: 29, weight: .semibold, design: .rounded))
                .tracking(-0.8).padding(.top, 21)
            HStack(spacing: 8) {
                Text("v\(AppMetadata.version)").font(.system(size: 11, weight: .medium, design: .monospaced))
                Circle().fill(Palette.secondary.opacity(0.5)).frame(width: 3, height: 3)
                Text(state.text(.initialRelease)).font(.system(size: 11, weight: .medium))
            }.foregroundStyle(Palette.accent).padding(.horizontal, 13).padding(.vertical, 7)
                .background(Palette.accentSoft, in: Capsule()).padding(.top, 11)
            Text(state.text(.aboutDescription)).font(.system(size: 12))
                .foregroundStyle(Palette.secondary).lineSpacing(4).multilineTextAlignment(.center)
                .frame(maxWidth: 345).padding(.top, 23)
            HStack(spacing: 8) {
                Text(state.text(.author)).foregroundStyle(Palette.secondary)
                Text(AppMetadata.author).fontWeight(.medium)
            }.font(.system(size: 12)).padding(.top, 24)
            Text(AppMetadata.copyright).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .padding(.top, 10)
            Spacer(minLength: 20)
            Button(state.text(.done)) { dismiss() }
                .buttonStyle(QuietButtonStyle()).keyboardShortcut(.escape, modifiers: [])
                .padding(.bottom, 28)
        }
        .frame(width: 500, height: 455)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}
