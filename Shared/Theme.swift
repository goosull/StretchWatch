import SwiftUI

/// Design tokens from DESIGN.md. Warm-tinted dark, one restrained accent.
enum Theme {
    static let ink    = Color(hex: 0x0E0B12)
    static let ink2   = Color(hex: 0x171320)
    static let haze   = Color(hex: 0xA9A2B8)
    static let paper  = Color(hex: 0xF3EEF6)
    static let ember  = Color(hex: 0xF2A65A)
    static let ember2 = Color(hex: 0xE9683E)
    static let calm   = Color(hex: 0x6FB6A6)

    /// Warm amber→coral gradient used for the active arc and the reward bloom.
    static let emberGradient = LinearGradient(
        colors: [ember, ember2],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // SF Rounded is the deliberate face choice: soft, bodily, coach-not-drill.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
