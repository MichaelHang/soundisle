import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Hashable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return L("跟随系统")
        case .light: return L("浅色")
        case .dark: return L("深色")
        }
    }
}

/// Colours a view needs for one resolved appearance. `accentTextHex` is the
/// readable text colour on top of `accentHex`.
public struct ThemeTokens: Equatable {
    public var accentHex: String
    public var isDark: Bool

    public init(accentHex: String, isDark: Bool) {
        self.accentHex = accentHex
        self.isDark = isDark
    }

    public var accentTextHex: String {
        AccentContrast.textColor(on: accentHex)
    }
}

/// The app's fixed background skin: neutral greys, in light and dark. The
/// accent comes from the user's macOS control accent colour at runtime, so
/// there is no app-owned colour here.
public enum ThemeSkin {
    public static func panelTint(isDark: Bool) -> String { isDark ? "#1C1C1E" : "#FFFFFF" }
    public static func playerTint(isDark: Bool) -> String { isDark ? "#101013" : "#F4F4F5" }
    public static func backgroundTop(isDark: Bool) -> String { isDark ? "#212124" : "#F7F7F8" }
    public static func backgroundMiddle(isDark: Bool) -> String { isDark ? "#1B1B1E" : "#EFEFF0" }
    public static func backgroundBottom(isDark: Bool) -> String { isDark ? "#141416" : "#FAFAFB" }
}

public enum ThemeResolver {
    /// `systemIsDark` is the effective macOS appearance; explicit light/dark
    /// modes win over it.
    public static func isDark(mode: ThemeMode, systemIsDark: Bool) -> Bool {
        switch mode {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }
}

public enum AccentContrast {
    /// Picks black or white by WCAG relative luminance, whichever reads better
    /// on the given accent.
    public static func textColor(on hex: String) -> String {
        guard let color = ThemeRGB(hex: hex) else { return "#FFFFFF" }
        let luminance = 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? "#000000" : "#FFFFFF"
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.03928
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

/// Small sRGB helper shared by the theme catalog and the SwiftUI palette.
public struct ThemeRGB: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Accepts `#RRGGBB` and `RRGGBB` (case-insensitive).
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6,
              let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    public var hexString: String {
        let channels = [red, green, blue].map { channel -> Int in
            Int((min(max(channel, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    public func blended(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        let t = min(max(amount, 0), 1)
        return ThemeRGB(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    public static let white = ThemeRGB(red: 1, green: 1, blue: 1)
    public static let black = ThemeRGB(red: 0, green: 0, blue: 0)
}

public extension AppSettings {
    /// The six-palette catalog and custom accent were removed; only light/dark
    /// remains configurable.
    var mode: ThemeMode { ThemeMode(rawValue: themeMode) ?? .system }
}
