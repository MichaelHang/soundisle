import XCTest
@testable import SoundIsleCore

final class ThemePaletteTests: XCTestCase {
    func testSkinIsNeutralInBothAppearances() {
        // The background skin carries no hue of its own: every channel is
        // neutral grey, so the only colour in the UI is the system accent.
        for isDark in [false, true] {
            for value in [
                ThemeSkin.panelTint(isDark: isDark),
                ThemeSkin.playerTint(isDark: isDark),
                ThemeSkin.backgroundTop(isDark: isDark),
                ThemeSkin.backgroundMiddle(isDark: isDark),
                ThemeSkin.backgroundBottom(isDark: isDark),
            ] {
                let rgb = ThemeRGB(hex: value)!
                XCTAssertLessThanOrEqual(abs(rgb.red - rgb.green), 0.02, value)
                XCTAssertLessThanOrEqual(abs(rgb.green - rgb.blue), 0.02, value)
            }
        }
        XCTAssertTrue(ThemeSkin.panelTint(isDark: true) != ThemeSkin.panelTint(isDark: false))
    }

    func testSystemModeResolution() {
        XCTAssertTrue(ThemeResolver.isDark(mode: .system, systemIsDark: true))
        XCTAssertFalse(ThemeResolver.isDark(mode: .system, systemIsDark: false))
        XCTAssertFalse(ThemeResolver.isDark(mode: .light, systemIsDark: true))
        XCTAssertTrue(ThemeResolver.isDark(mode: .dark, systemIsDark: false))
    }

    func testContrastOnLightAccentIsBlack() {
        XCTAssertEqual(AccentContrast.textColor(on: "#F5B942"), "#000000")
        XCTAssertEqual(AccentContrast.textColor(on: "#7AA2FF"), "#000000")
    }

    func testContrastOnDarkAccentIsWhite() {
        XCTAssertEqual(AccentContrast.textColor(on: "#1B1F27"), "#FFFFFF")
        XCTAssertEqual(AccentContrast.textColor(on: "#3E6FE0"), "#FFFFFF")
    }

    func testInvalidHexFallsBackToWhiteText() {
        XCTAssertEqual(AccentContrast.textColor(on: "not-a-colour"), "#FFFFFF")
    }

    func testSettingsModeResolves() {
        let settings = AppSettings()
        XCTAssertEqual(settings.mode, .system)

        var custom = settings
        custom.themeMode = "dark"
        XCTAssertEqual(custom.mode, .dark)
    }
}

/// Text drawn on a filled accent control — the play button, a notice's action
/// button — takes its colour from `accentTextHex`, which picks black or white
/// by contrast. These pin the property down for the fixed skin in both
/// appearances.
final class AccentContrastTests: XCTestCase {
    /// WCAG relative luminance.
    private func luminance(_ hex: String) -> Double {
        let rgb = ThemeRGB(hex: hex)!
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let one = luminance(a), two = luminance(b)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    func testAccentTextIsReadableForKnownAccents() {
        // The accent is dynamic (the user's control accent), but whatever it
        // resolves to, black-or-white by contrast must stay readable — pin a
        // few plausible accents including the system default blue.
        for hex in ["#3E6FE0", "#7AA2FF", "#C04040", "#40A060", "#808080"] {
            let text = AccentContrast.textColor(on: hex)
            XCTAssertGreaterThanOrEqual(contrast(hex, text), 4.5, "\(text) on \(hex)")
        }
    }
}
