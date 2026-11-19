import AppKit
import SoundIsleCore
import SwiftUI

// MARK: - Palette

/// UI-side colours for one resolved theme. Core owns the accent contract;
/// this type adds the background skin, glass tints and control fills.
struct ThemePalette {
    let tokens: ThemeTokens

    let accent: Color
    let accentSecondary: Color
    let accentLight: Color
    let accentGradient: LinearGradient
    let onAccent: Color
    let text: Color
    let warning: Color
    let panelTint: Color
    let playerTint: Color
    let backgroundTop: Color
    let backgroundMiddle: Color
    let backgroundBottom: Color
    let coverGradient: LinearGradient
    let hairline: Color
    let raisedFill: Color
    let sliderTrack: Color

    var isDark: Bool { tokens.isDark }

    /// Secondary text/icons stay subtle but readable: both modes carry a
    /// contrast floor. Light already clamped at 0.62 (0.4–0.55 opacity read
    /// at only 2.6–3.3:1); dark now clamps at 0.5, which the near-white text
    /// turns into roughly 4.9:1 on the darkest skin — WCAG AA for the small
    /// sizes these labels use.
    func mutedText(_ base: Double) -> Color {
        text.opacity(isDark ? max(base, 0.5) : max(base, 0.62))
    }

    /// The accent is the user's macOS control accent colour; backgrounds are
    /// neutral greys. There is no app-owned theme colour any more — only
    /// light/dark remains configurable.
    init(tokens: ThemeTokens) {
        self.tokens = tokens

        let accentRGB = ThemeRGB(hex: tokens.accentHex) ?? ThemeRGB(red: 0.40, green: 0.56, blue: 1)
        let secondaryRGB = accentRGB.blended(
            with: tokens.isDark ? .white : .black,
            amount: 0.30
        )

        let accent = Color(rgb: accentRGB)
        let secondary = Color(rgb: secondaryRGB)
        self.accent = accent
        self.accentSecondary = secondary
        self.accentGradient = LinearGradient(
            colors: [accent, secondary],
            startPoint: .leading,
            endPoint: .trailing
        )
        self.accentLight = Color(rgb: accentRGB.blended(
            with: tokens.isDark ? .white : .black,
            amount: tokens.isDark ? 0.55 : 0.28
        ))
        self.onAccent = Color(hex: tokens.accentTextHex)
        self.text = Color(hex: tokens.isDark ? "#F0F0F2" : "#1D1D1F")
        self.warning = Color(hex: tokens.isDark ? "#FFB766" : "#A65F00")
        self.panelTint = Color(hex: ThemeSkin.panelTint(isDark: tokens.isDark))
        self.playerTint = Color(hex: ThemeSkin.playerTint(isDark: tokens.isDark))
        self.backgroundTop = Color(hex: ThemeSkin.backgroundTop(isDark: tokens.isDark))
        self.backgroundMiddle = Color(hex: ThemeSkin.backgroundMiddle(isDark: tokens.isDark))
        self.backgroundBottom = Color(hex: ThemeSkin.backgroundBottom(isDark: tokens.isDark))
        self.coverGradient = LinearGradient(
            colors: [accent, accentLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        self.hairline = tokens.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.09)
        self.raisedFill = tokens.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.055)
        self.sliderTrack = tokens.isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.13)
    }

    /// Resolves the persisted light/dark setting plus the effective system
    /// appearance into the neutral skin, tinted by the user's macOS control
    /// accent colour.
    static func resolve(mode: ThemeMode, systemIsDark: Bool) -> ThemePalette {
        let isDark = ThemeResolver.isDark(mode: mode, systemIsDark: systemIsDark)
        return ThemePalette(tokens: ThemeTokens(
            accentHex: systemAccentHex(isDark: isDark),
            isDark: isDark
        ))
    }

    /// The user's system accent (系统设置 → 外观 → 强调色), resolved under the
    /// given appearance so a fixed-light or fixed-dark theme still gets the
    /// right shade.
    private static func systemAccentHex(isDark: Bool) -> String {
        var rgb: ThemeRGB?
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            if let nsColor = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                rgb = ThemeRGB(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent)
                )
            }
        }
        // The system default accent, as a fallback if extraction fails.
        return rgb?.hexString ?? (isDark ? "#7AA2FF" : "#3E6FE0")
    }
}

// MARK: - Environment

extension NSWorkspace {
    /// The system 减弱动态效果 switch. The SwiftUI environment value only
    /// reaches views; model code and view helpers read this instead, so one
    /// switch gates every animation in the app.
    static var appReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.resolve(mode: .system, systemIsDark: true)
}

extension EnvironmentValues {
    var theme: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension View {
    /// Applies a resolved palette to this subtree. Root windows call it once;
    /// every descendant reads `@Environment(\.theme)`.
    func soundIsleTheme(_ palette: ThemePalette) -> some View {
        environment(\.theme, palette)
    }
}

// MARK: - Shared drawing

/// Blurred desktop/window behind a clear window. Shared by the main window,
/// the settings sheet, the mini player and the lyrics overlay.
struct MaterialBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct AppBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            // One opaque theme gradient for the whole window. The sidebar and
            // player bar draw only tonal scrims over this, never their own
            // material, so active/inactive state cannot change the colours.
            LinearGradient(
                colors: [
                    theme.backgroundTop,
                    theme.backgroundMiddle,
                    theme.backgroundBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ambient colour blobs, drawn once and never animated.
            Circle()
                .fill(theme.accent.opacity(theme.isDark ? 0.22 : 0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -250, y: -210)
            Circle()
                .fill(theme.accentSecondary.opacity(theme.isDark ? 0.18 : 0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 280, y: 170)

            RadialGradient(
                colors: [theme.accent.opacity(theme.isDark ? 0.26 : 0.16), .clear],
                center: UnitPoint(x: 0.12, y: 0.05),
                startRadius: 0,
                endRadius: 480
            )
            RadialGradient(
                colors: [theme.accentSecondary.opacity(theme.isDark ? 0.18 : 0.12), .clear],
                center: UnitPoint(x: 0.88, y: 0.22),
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

private struct GlassPanelModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(theme.panelTint.opacity(theme.isDark ? 0.55 : 0.78), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(theme.hairline, lineWidth: 0.5))
    }
}

extension View {
    /// Frosted panel: material blurs what is behind, a translucent tint gives
    /// the theme cast, and a hairline border catches the light.
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Color bridges

extension Color {
    init(hex: String) {
        self.init(rgb: ThemeRGB(hex: hex) ?? ThemeRGB(red: 0.5, green: 0.5, blue: 0.5))
    }

    init(rgb: ThemeRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// `ColorPicker` hands back an opaque `Color`; persist it as `#RRGGBB`.
    var hexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return ThemeRGB(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        ).hexString
    }
}
