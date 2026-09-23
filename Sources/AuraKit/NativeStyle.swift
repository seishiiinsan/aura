import SwiftUI

// Native macOS look shared by Aura and Aura Insights.
//
// Liquid Glass (macOS 26+) is used for the navigation / control layer only — toolbars,
// buttons, floating panels — as Apple's guidelines recommend; content sits on standard
// system surfaces. Every helper falls back gracefully on macOS 15.

/// A System Settings–style icon: white SF Symbol on a colored rounded square.
public struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat

    public init(_ symbol: String, color: Color, size: CGFloat = 20) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// Small colored dot used for connection / live states.
public struct StatusDot: View {
    let color: Color
    public init(_ color: Color) { self.color = color }
    public var body: some View {
        Circle().fill(color.gradient).frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
}

public extension View {
    /// Liquid Glass surface on macOS 26+, regular material before.
    @ViewBuilder
    func nativeGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Glass buttons on macOS 26+, bordered buttons before.
    @ViewBuilder
    func nativeButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// Soft scroll-edge fading under toolbars (macOS 26+).
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }

    /// Content card matching grouped-form sections (not glass: content stays on system surfaces).
    func contentSurface(cornerRadius: CGFloat = 12, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.separator.opacity(0.35), lineWidth: 0.5))
    }

    /// Tab-style segmented picker on macOS 27, segmented before.
    @ViewBuilder
    func nativeTabsPickerStyle() -> some View {
        #if compiler(>=6.3)
        if #available(macOS 27, *) {
            self.pickerStyle(.tabs)
        } else {
            self.pickerStyle(.segmented)
        }
        #else
        self.pickerStyle(.segmented)
        #endif
    }
}

/// Groups glass shapes so they blend and morph together (macOS 26+).
public struct NativeGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Control Center–style round toggle button.
public struct RoundToggleButton: View {
    let symbol: String
    let isOn: Bool
    var tint: Color
    let action: () -> Void

    public init(symbol: String, isOn: Bool, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.symbol = symbol
        self.isOn = isOn
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 38, height: 38)
                .background {
                    if isOn { Circle().fill(tint.gradient) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nativeGlass(in: Circle(), interactive: true)
    }
}
