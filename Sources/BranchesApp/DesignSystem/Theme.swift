import AppKit
import BranchesKit
import SwiftUI

/// Forest-inspired tokens (docs/04-design.md §9). Dark is primary; light is supported.
enum Palette {
    static let window = dynamic(dark: 0x141613, light: 0xF4F1EA)
    static let textPrimary = dynamic(dark: 0xECE6D8, light: 0x1E211C)
    static let textSecondary = dynamic(dark: 0xA9A391, light: 0x5C5A50)
    static let textTertiary = dynamic(dark: 0x6E6A5E, light: 0x8E8A7E)
    static let bark = dynamic(dark: 0x5A4E42, light: 0xA89684)
    static let moss = dynamic(dark: 0x3F5A43, light: 0x6F8F6F)
    static let leaf = dynamic(dark: 0x7FCF7A, light: 0x2F8F3A)
    static let amber = dynamic(dark: 0xE0A94A, light: 0xB7791F)
    static let rust = dynamic(dark: 0xC8664A, light: 0xA4472E)
    static let cream = dynamic(dark: 0xECE6D8, light: 0x3C3A33)
    static let selection = dynamic(dark: 0x2F4A34, light: 0x3D6B45, darkAlpha: 0.45, lightAlpha: 0.16)
    static let hover = dynamic(dark: 0xECE6D8, light: 0x5A4E42, darkAlpha: 0.05, lightAlpha: 0.06)

    private static func dynamic(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func color(for status: StatusResult) -> Color {
        switch status.display {
        case .needsYou: status.attention == .error ? rust : amber
        case .working: leaf
        case .done: cream
        case .idle: textSecondary
        case .ended: textTertiary
        }
    }
}

enum Typo {
    static let wordmark = Font.system(size: 11, weight: .semibold)
    static let project = Font.system(size: 13, weight: .semibold)
    static let title = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static let captionEmphasized = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 11, design: .monospaced)
}

enum Metrics {
    static let connectorWidth: CGFloat = 22
    static let nodeColumn: CGFloat = 16
    static let rowCorner: CGFloat = 6
    static let groupSpacing: CGFloat = 14
    static let providerColumn: CGFloat = 50
    /// Vertical center of a row's first text line; where the elbow meets the node.
    static let elbowY: CGFloat = 15
}
