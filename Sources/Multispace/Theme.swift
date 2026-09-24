import SwiftUI
import AppKit

@MainActor
enum Palette {
    static var light: Bool {
        let setting = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.appearance ?? "Follow System"
        return setting == "Light" || (setting == "Follow System" && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }
    static var background: Color { light ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.055, green: 0.060, blue: 0.085) }
    static var sidebar: Color { light ? Color(red: 0.91, green: 0.92, blue: 0.94) : Color(red: 0.080, green: 0.084, blue: 0.115) }
    static var panel: Color { light ? .white : Color(red: 0.105, green: 0.110, blue: 0.145) }
    static var card: Color { light ? Color(red: 0.88, green: 0.89, blue: 0.92) : Color(red: 0.135, green: 0.140, blue: 0.180) }
    static var muted: Color { light ? Color(red: 0.42, green: 0.44, blue: 0.49) : Color(red: 0.60, green: 0.62, blue: 0.69) }
    static var border: Color { light ? Color(white: 0, opacity: 0.08) : Color(white: 1, opacity: 0.08) }
    static var hover: Color { light ? Color(white: 0, opacity: 0.05) : Color(white: 1, opacity: 0.07) }
    static var text: Color { light ? Color(red: 0.11, green: 0.12, blue: 0.14) : Color(red: 0.94, green: 0.95, blue: 0.97) }
    static var accent: Color {
        let value = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.accent ?? "indigo"
        switch value {
        case "blue": return Color(red: 0.12, green: 0.56, blue: 0.98)
        case "cyan": return Color(red: 0.08, green: 0.76, blue: 0.84)
        case "orange": return Color(red: 1, green: 0.59, blue: 0.24)
        case "green": return Color(red: 0.20, green: 0.77, blue: 0.40)
        case "pink": return Color(red: 0.82, green: 0.26, blue: 0.94)
        default: return Color(red: 0.66, green: 0.33, blue: 0.97) // #A855F7 — Pinggo violet
        }
    }
    // Global Header Navigation Tokens
    static var navActiveBg: Color { Color(red: 184/255.0, green: 121/255.0, blue: 1.0) } // #B879FF
    static var navActiveText: Color { Color(red: 0.07, green: 0.07, blue: 0.07) } // #111111
    static var navInactiveText: Color { Color(red: 0.53, green: 0.53, blue: 0.53) } // #888888
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
