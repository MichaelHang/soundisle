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

    /// checkin-swift-style theming: the accent is SwiftUI's `Color.accentColor`
    /// — the user's macOS control accent, a dynamic colour that follows system
    /// changes (accent or appearance) on its own. Surfaces are neutral greys.
    /// `tokens.accentHex` carries the same accent resolved to RGB once, only
    /// for the on-accent text contrast computation.
    init(tokens: ThemeTokens) {
        self.tokens = tokens

        let accent = Color.accentColor
        self.accent = accent
        self.accentSecondary = accent.opacity(0.65)
        self.accentLight = accent
        self.accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
        self.onAccent = Color(hex: tokens.accentTextHex)
        self.text = Color(hex: tokens.isDark ? "#F0F0F2" : "#1D1D1F")
        self.warning = Color(hex: tokens.isDark ? "#FFB766" : "#A65F00")
        self.panelTint = Color(hex: ThemeSkin.panelTint(isDark: tokens.isDark))
        self.playerTint = Color(hex: ThemeSkin.playerTint(isDark: tokens.isDark))
        self.backgroundTop = Color(hex: ThemeSkin.backgroundTop(isDark: tokens.isDark))
        self.backgroundMiddle = Color(hex: ThemeSkin.backgroundMiddle(isDark: tokens.isDark))
        self.backgroundBottom = Color(hex: ThemeSkin.backgroundBottom(isDark: tokens.isDark))
        self.coverGradient = LinearGradient(
            colors: [accent.opacity(0.85), accent.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        self.hairline = tokens.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.09)
        self.raisedFill = tokens.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.055)
        self.sliderTrack = tokens.isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.13)
    }

    /// Resolves the persisted light/dark setting. The accent colour itself is
    /// the dynamic `Color.accentColor`; it is only resolved to RGB here so
    /// the on-accent text (black or white) can be picked by contrast.
    static func resolve(mode: ThemeMode, systemIsDark: Bool) -> ThemePalette {
        let isDark = ThemeResolver.isDark(mode: mode, systemIsDark: systemIsDark)
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
        return ThemePalette(tokens: ThemeTokens(
            accentHex: rgb?.hexString ?? (isDark ? "#7AA2FF" : "#3E6FE0"),
            isDark: isDark
        ))
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
        // One quiet three-stop gradient, no ambient accent blobs. The old
        // blurred accent circles washed the whole window in the accent hue —
        // with the system-blue accent everything looked flooded with blue.
        // The accent now lives only in controls, the way small apps do it.
        LinearGradient(
            colors: [
                theme.backgroundTop,
                theme.backgroundMiddle,
                theme.backgroundBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
