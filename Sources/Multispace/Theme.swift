import SwiftUI
import AppKit

@MainActor
enum Palette {
    static var light: Bool {
        let setting = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.appearance ?? "Follow System"
        return setting == "Light" || (setting == "Follow System" && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }
    // Quiet, low-chroma surfaces keep dense communication UI readable without
    // turning every nested panel into a separate visual layer.
    static var background: Color { light ? Color(red: 0.965, green: 0.970, blue: 0.978) : Color(red: 0.047, green: 0.052, blue: 0.063) }
    static var sidebar: Color { light ? Color(red: 0.945, green: 0.951, blue: 0.961) : Color(red: 0.059, green: 0.065, blue: 0.078) }
    static var panel: Color { light ? Color(red: 0.992, green: 0.994, blue: 0.997) : Color(red: 0.071, green: 0.078, blue: 0.092) }
    static var card: Color { light ? Color(red: 0.972, green: 0.976, blue: 0.983) : Color(red: 0.091, green: 0.099, blue: 0.116) }
    static var muted: Color { light ? Color(red: 0.39, green: 0.42, blue: 0.47) : Color(red: 0.58, green: 0.61, blue: 0.67) }
    static var border: Color { light ? Color(white: 0, opacity: 0.075) : Color(white: 1, opacity: 0.075) }
    static var hover: Color { light ? Color(white: 0, opacity: 0.045) : Color(white: 1, opacity: 0.055) }
    static var text: Color { light ? Color(red: 0.10, green: 0.11, blue: 0.13) : Color(red: 0.93, green: 0.94, blue: 0.96) }
    static var accent: Color {
        let value = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.accent ?? "indigo"
        switch value {
        case "blue": return Color(red: 0.12, green: 0.56, blue: 0.98)
        case "cyan": return Color(red: 0.08, green: 0.76, blue: 0.84)
        case "orange": return Color(red: 1, green: 0.59, blue: 0.24)
        case "green": return Color(red: 0.20, green: 0.77, blue: 0.40)
        case "pink": return Color(red: 0.82, green: 0.26, blue: 0.94)
        default: return Color(red: 0.49, green: 0.36, blue: 0.96) // restrained Pinggo violet
        }
    }
    // Global Header Navigation Tokens
    static var navActiveBg: Color { accent.opacity(light ? 0.12 : 0.18) }
    static var navActiveText: Color { accent }
    static var navInactiveText: Color { muted }
}

@MainActor
func spaceColor(_ name: String) -> Color {
    switch name {
    case "green": return Color(red: 0.25, green: 0.80, blue: 0.48)
    case "pink": return Color(red: 1, green: 0.55, blue: 0.72)
    case "blue": return Color(red: 0.43, green: 0.70, blue: 1)
    case "orange": return Color(red: 1, green: 0.67, blue: 0.37)
    default: return Palette.accent
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
