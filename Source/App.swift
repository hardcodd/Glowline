import AppKit
import SwiftUI
import Carbon
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var item: NSStatusItem!
    private var window: NSWindow?
    private var observer: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let firstLaunch = !FileManager.default.fileExists(atPath: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Glowline/settings.json").path)
        model = AppModel()
        buildMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Glowline")
        item.button?.toolTip = "Glowline"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.restartEngine() } }
        model.begin()
        let login = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let background = CommandLine.arguments.contains("--background") || login
        if firstLaunch || !background || !model.settings.startHidden { showWindow() }
    }
    private func buildMainMenu() {
        let bar = NSMenu()
        let appEntry = NSMenuItem(); let appMenu = NSMenu(); appEntry.submenu = appMenu; bar.addItem(appEntry)
        add(appMenu, title: tr("menu.open"), action: #selector(openAction), key: ",")
        appMenu.addItem(.separator())
        add(appMenu, title: tr("menu.quit"), action: #selector(quitAction), key: "q")
        let editEntry = NSMenuItem(title: tr("menu.edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: tr("menu.edit")); editEntry.submenu = editMenu; bar.addItem(editEntry)
        for (title, selector, key) in [("menu.undo", "undo:", "z"), ("menu.cut", "cut:", "x"), ("menu.copy", "copy:", "c"), ("menu.paste", "paste:", "v"), ("menu.selectAll", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: tr(title), action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        NSApp.mainMenu = bar
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = NSMenuItem(title: "Glowline · " + model.connectionTitle, action: nil, keyEquivalent: ""); info.isEnabled = false; menu.addItem(info)
        let mode = NSMenuItem(title: model.modeName + " · " + model.rateText, action: nil, keyEquivalent: ""); mode.isEnabled = false; menu.addItem(mode)
        menu.addItem(.separator())
        add(menu, title: tr("menu.open"), action: #selector(openAction), key: ",")
        add(menu, title: tr(model.settings.enabled ? "menu.off" : "menu.on"), action: #selector(toggleAction), key: "")
        let modes = NSMenu(); for i in 0..<6 { let entry = NSMenuItem(title: tr("mode.\(i)"), action: #selector(modeAction(_:)), keyEquivalent: ""); entry.target = self; entry.tag = i; entry.state = model.settings.mode == i ? .on : .off; modes.addItem(entry) }
        let modesEntry = NSMenuItem(title: tr("mode.title"), action: nil, keyEquivalent: ""); modesEntry.submenu = modes; menu.addItem(modesEntry)
        if !model.profiles.isEmpty {
            let profiles = NSMenu()
            for (index, profile) in model.profiles.enumerated() { let entry = NSMenuItem(title: profile.name, action: #selector(profileAction(_:)), keyEquivalent: ""); entry.tag = index; entry.target = self; profiles.addItem(entry) }
            let entry = NSMenuItem(title: tr("page.profiles"), action: nil, keyEquivalent: ""); entry.submenu = profiles; menu.addItem(entry)
        }
        menu.addItem(.separator())
        add(menu, title: tr("menu.quit"), action: #selector(quitAction), key: "q")
    }
    private func add(_ menu: NSMenu, title: String, action: Selector, key: String) { let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry) }
    @objc private func openAction() { showWindow() }
    @objc private func toggleAction() { model.settings.enabled.toggle() }
    @objc private func modeAction(_ sender: NSMenuItem) { model.settings.mode = sender.tag }
    @objc private func profileAction(_ sender: NSMenuItem) { if model.profiles.indices.contains(sender.tag) { model.activate(model.profiles[sender.tag]) } }
    @objc private func quitAction() { NSApp.terminate(nil) }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Glowline"; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false; w.delegate = self; w.minSize = NSSize(width: 1000, height: 725)
            w.contentView = NSHostingView(rootView: RootView(model: model)); w.setFrameAutosaveName("Glowline.main"); w.center(); window = w
        }
        NSApp.setActivationPolicy(.regular); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); NSApp.setActivationPolicy(.accessory); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown(); if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}

@main struct GlowlineMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            do { try runSettingsTests(); try runStatusTests(); runRecoveryTests(); try runModelTests() } catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }; return
        }
        if CommandLine.arguments.contains("--disable-login") {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.alex.Glowline").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            for other in others { _ = other.terminate() }
            for _ in 0..<50 {
                if others.allSatisfy({ $0.isTerminated }) { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            guard others.allSatisfy({ $0.isTerminated }) else { fputs("Close Glowline before rollback.\n", stderr); exit(1) }
            do {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
                let model = AppModel(); model.settings.launchAtLogin = false; model.applySettings()
            } catch { fputs("Cannot disable login item: \(error)\n", stderr); exit(1) }
            return
        }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.alex.Glowline").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let app = existing.first { app.activate(options: [.activateAllWindows]); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
