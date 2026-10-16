import AppKit

/// Verify inherited native appearance after repeated overrides without touching macOS settings.
@MainActor func runAppearanceTests() {
    let app = NSApplication.shared
    let original = app.appearance
    defer { app.appearance = original }
    app.appearance = nil
    let system = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = NSView(frame: window.contentLayoutRect)
    window.contentView = view
    defer { window.close() }
    for theme in ["dark", "system", "light", "system", "dark", "light", "dark", "system"] {
        AppAppearance.apply(theme)
        let expected: NSAppearance.Name? = theme == "system" ? system : theme == "dark" ? .darkAqua : .aqua
        precondition(window.appearance == nil && view.appearance == nil)
        precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        precondition(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        if theme == "system" { precondition(app.appearance == nil) }
    }
    func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    func resolvedAccent(_ name: NSAppearance.Name) -> NSColor {
        var result = NSColor.clear
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = AppPalette.amber.usingColorSpace(.sRGB)!
        }
        return result
    }
    var light = NSColor.clear
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        light = NSColor.labelColor.usingColorSpace(.sRGB)!
    }
    let dark = resolvedAccent(.darkAqua)
    precondition(abs(dark.redComponent - 1) < 0.001 && abs(dark.greenComponent - 0.69) < 0.001 && abs(dark.blueComponent - 0.34) < 0.001)
    // Include a conservative gray backdrop for the translucent sidebar and cards.
    for level in [1.0, 0.96, 0.90, 0.86] {
        let background = NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
        let ratio = (luminance(background) + 0.05) / (luminance(light) + 0.05)
        precondition(ratio >= 4.5, "Light label contrast: \(ratio)")
    }
    print("Native appearance transitions and light label contrast contracts passed")
}
