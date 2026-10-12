import SwiftUI
import AppKit

enum Palette {
    static let accent = adaptive(light: 0x315E51, dark: 0x9ECBB7)
    static let accentSoft = adaptive(light: 0xE7EEE8, dark: 0x253C32)
    static let background = adaptive(light: 0xF7F8F5, dark: 0x181C19)
    static let sidebar = adaptive(light: 0xF0F2ED, dark: 0x202520)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x272D28)
    static let border = adaptive(light: 0xDFE4DB, dark: 0x394239)
    static let ink = adaptive(light: 0x26372E, dark: 0xEDF2EC)
    static let secondary = adaptive(light: 0x788278, dark: 0xA6B1A6)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .semibold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, compact ? 14 : 23)
            .padding(.vertical, compact ? 9 : 13)
            .background(Palette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(configuration.isPressed ? Palette.accentSoft : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
    }
}

struct AppMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.47, blue: 0.38),
                                              Color(red: 0.14, green: 0.31, blue: 0.24)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "viewfinder")
                .font(.system(size: size * 0.53, weight: .medium))
                .foregroundStyle(.white)
            Circle().fill(.white).frame(width: size * 0.13, height: size * 0.13)
        }.frame(width: size, height: size)
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.6)
                .foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.accent).frame(width: 64, height: 64)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 290)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}
