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
    static var accent: Color {
        let value = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.accent ?? "indigo"
        switch value {
        case "blue": return Color(red: 0.12, green: 0.56, blue: 0.98)
        case "cyan": return Color(red: 0.08, green: 0.76, blue: 0.84)
        case "orange": return Color(red: 1, green: 0.59, blue: 0.24)
        case "green": return Color(red: 0.20, green: 0.77, blue: 0.40)
        case "pink": return Color(red: 0.82, green: 0.26, blue: 0.94)
        default: return Color(red: 0.42, green: 0.48, blue: 0.98)
        }
    }
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
