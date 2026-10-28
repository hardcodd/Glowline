import AppKit
import SwiftUI

/// Verify inherited native appearance after repeated overrides without touching macOS settings.
@MainActor func runAppearanceTests() throws {
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
    try runScrollStabilityTests()
}

/// Notices must leave the scroll document and the slider's viewport position unchanged.
@MainActor private func runScrollStabilityTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glowline-scroll-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var settings = Settings(); settings.launchAtLogin = false
    try! JSONEncoder().encode(SavedState(settings: settings, profiles: [])).write(to: directory.appendingPathComponent("settings.json"))
    let model = AppModel(stateDirectory: directory, inspectSystem: false)
    model.page = "effects"; model.settings.mode = 7
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 690), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: RootView(model: model))
    window.contentView = host
    defer { window.close() }
    func settle() throws {
        // SwiftUI layout is asynchronous; wait for stable geometry rather than a machine-specific delay.
        let deadline = Date().addingTimeInterval(2)
        var previous: [CGFloat] = []
        var stable = 0
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            let scroll = scrollView(in: host)
            let geometry: [CGFloat] = [scroll?.documentView?.frame.height ?? 0,
                            scroll?.contentView.bounds.height ?? 0,
                            scroll?.contentView.bounds.origin.y ?? 0]
            stable = geometry == previous ? stable + 1 : 0
            previous = geometry
        } while stable < 4 && Date() < deadline
        guard stable >= 4 else {
            throw NSError(domain: "GlowlineScrollTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "SwiftUI scroll layout did not settle"])
        }
    }
    func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
    try settle()
    let scroll = scrollView(in: host)!
    let height = scroll.documentView!.frame.height
    precondition(height > scroll.contentView.bounds.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: height - scroll.contentView.bounds.height))
    scroll.reflectScrolledClipView(scroll.contentView)
    try settle()
    let position = scroll.contentView.bounds.origin.y
    for index in 0..<6 {
        model.notice = index.isMultiple(of: 2) ? "Connection status changed while editing the effect speed" : ""
        model.connectionHelpDismissed = index.isMultiple(of: 2)
        model.settings.effect.speed = Double(index + 1) * 0.5
        try settle()
        let newHeight = scroll.documentView!.frame.height
        let newPosition = scroll.contentView.bounds.origin.y
        guard abs(newHeight - height) < 0.5, abs(newPosition - position) < 0.5 else {
            throw NSError(domain: "GlowlineScrollTest", code: index, userInfo: [NSLocalizedDescriptionKey:
                "Notice changed scroll geometry: height \(height) -> \(newHeight), position \(position) -> \(newPosition)"])
        }
    }
    print("Notice insertion/removal preserves scroll document height and slider position")
}
