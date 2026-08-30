import SwiftUI
import UIKit

/// Visual tokens for the native studio. Mirrors the web embed `theme` object
/// (`primary`, `background`, `foreground`, `radius`, `fontFamily`, `mode`).
public struct StudioTheme: Hashable, Sendable {
    public var primary: Color
    public var background: Color
    public var foreground: Color
    public var secondary: Color
    public var destructive: Color
    public var live: Color
    public var radius: CGFloat
    public var mode: Mode

    public enum Mode: String, Sendable, Hashable {
        case light
        case dark
        case system
    }

    public init(
        primary: Color = Color(red: 0.15, green: 0.39, blue: 0.92),
        background: Color = Color(uiColor: .systemBackground),
        foreground: Color = Color(uiColor: .label),
        secondary: Color = Color(uiColor: .secondaryLabel),
        destructive: Color = Color(red: 0.86, green: 0.24, blue: 0.24),
        live: Color = Color(red: 0.86, green: 0.24, blue: 0.24),
        radius: CGFloat = 12,
        mode: Mode = .system
    ) {
        self.primary = primary
        self.background = background
        self.foreground = foreground
        self.secondary = secondary
        self.destructive = destructive
        self.live = live
        self.radius = radius
        self.mode = mode
    }

    public static let livo = StudioTheme()
}

public struct StudioThemeKey: EnvironmentKey {
    public static let defaultValue = StudioTheme.livo
}

public extension EnvironmentValues {
    var studioTheme: StudioTheme {
        get { self[StudioThemeKey.self] }
        set { self[StudioThemeKey.self] = newValue }
    }
}

public extension View {
    func studioTheme(_ theme: StudioTheme) -> some View {
        environment(\.studioTheme, theme)
    }
}

struct StudioPreferredColorScheme: ViewModifier {
    var mode: StudioTheme.Mode

    func body(content: Content) -> some View {
        switch mode {
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        case .system:
            content
        }
    }
}
