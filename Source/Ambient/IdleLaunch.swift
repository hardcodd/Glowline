import AppKit
import Combine
import CoreGraphics

/// App-wide idle preferences, isolated from strip profiles and the scene's sleep timer.
@MainActor final class AmbientIdleSettings: ObservableObject {
    static let minuteChoices = [1, 3, 5, 10, 15, 30, 60]
    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "idleEnabled") } }
    @Published var minutes: Int {
        didSet {
            if !Self.minuteChoices.contains(minutes) { minutes = 5 }
            defaults.set(minutes, forKey: "idleMinutes")
        }
    }

    init(
        defaults: UserDefaults = UserDefaults(
            suiteName: (Bundle.main.bundleIdentifier ?? "Glowline") + ".ambient")!
    ) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "idleEnabled")
        let saved = defaults.integer(forKey: "idleMinutes")
        minutes = Self.minuteChoices.contains(saved) ? saved : 5
    }
}

/// Allows one launch attempt per idle period, including renderer failures or timed closure.
struct AmbientIdlePolicy {
    enum Action { case none, launch, dismiss }
    private var attempted = false

    mutating func update(
        idleSeconds: Double, delay: Double, enabled: Bool,
        available: Bool, blocked: Bool, open: Bool, automatic: Bool
    ) -> Action {
        guard idleSeconds.isFinite, idleSeconds >= 0 else { return automatic ? .dismiss : .none }
        if idleSeconds < delay { attempted = false }
        if automatic {
            return !enabled || !available || blocked || idleSeconds < delay ? .dismiss : .none
        }
        if open {
            if idleSeconds >= delay { attempted = true }
            return .none
        }
        guard enabled, available, !blocked, !attempted, idleSeconds >= delay else { return .none }
        attempted = true
        return .launch
    }
}

/// Uses window geometry only: no window titles, screenshots, event taps or accessibility access.
@MainActor enum AmbientIdleEnvironment {
    static var idleSeconds: Double {
        // .null is a single event type, not "any input".
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }

    static var displays: [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
    }

    /// Near-full-display windows also block, including video/game windows without native fullscreen.
    static func coversDisplay(_ window: CGRect, displays: [CGRect]) -> Bool {
        displays.contains { display in
            let overlap = display.intersection(window)
            return display.width > 0 && display.height > 0
                && overlap.width >= display.width * 0.98 && overlap.height >= display.height * 0.95
        }
    }

    static var blocked: Bool {
        let screens = displays
        guard !screens.isEmpty,
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return true }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { windowBlocksLaunch($0, ownPID: ownPID, displays: screens) }
    }

    /// Ignore the host and system menu overlays while retaining ordinary, floating and shield windows.
    static func windowBlocksLaunch(_ window: [String: Any], ownPID: Int32, displays: [CGRect]) -> Bool {
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
            let layer = window[kCGWindowLayer as String] as? Int,
            // System menu/recording overlays can have transparent full-display bounds.
            (layer >= 0 && layer < Int(CGWindowLevelForKey(.mainMenuWindow)))
                || layer == Int(CGShieldingWindowLevel()),
            let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
            let dictionary = window[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        else { return false }
        return coversDisplay(bounds, displays: displays)
    }

    static var available: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            session[kCGSessionOnConsoleKey] as? Bool == true,
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow"
        else { return false }
        return NSScreen.screens.contains { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsAsleep(number.uint32Value) == 0
        }
    }
}

/// Main-run-loop polling owns its observers/timer and never samples windows before the idle deadline.
@MainActor final class AmbientIdleMonitor {
    private let settings: AmbientIdleSettings
    private let isOpen: () -> Bool
    private let isAutomatic: () -> Bool
    private let launch: () -> Void
    private let dismiss: () -> Void
    private var policy = AmbientIdlePolicy()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sessionActive = true
    private var screensAwake = true
    private var resumedAt = ProcessInfo.processInfo.systemUptime

    init(
        settings: AmbientIdleSettings, isOpen: @escaping () -> Bool,
        isAutomatic: @escaping () -> Bool, launch: @escaping () -> Void, dismiss: @escaping () -> Void
    ) {
        self.settings = settings
        self.isOpen = isOpen
        self.isAutomatic = isAutomatic
        self.launch = launch
        self.dismiss = dismiss
    }

    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    Task { @MainActor in self?.environmentChanged(notification.name) }
                })
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func environmentChanged(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification: screensAwake = false
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification: screensAwake = true
        case NSWorkspace.sessionDidResignActiveNotification: sessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionActive = true
        default: return
        }
        resumedAt = ProcessInfo.processInfo.systemUptime
        if isAutomatic() { dismiss() }
    }

    private func poll() {
        guard settings.enabled || isAutomatic() else { return }
        // A wake or session switch starts a fresh wait even if Quartz retained old idle time.
        let idle = min(AmbientIdleEnvironment.idleSeconds, ProcessInfo.processInfo.systemUptime - resumedAt)
        let delay = Double(settings.minutes * 60)
        let available = sessionActive && screensAwake && AmbientIdleEnvironment.available
        let blocked =
            available && idle >= delay && (!isOpen() || isAutomatic())
            ? AmbientIdleEnvironment.blocked : false
        switch policy.update(
            idleSeconds: idle, delay: delay, enabled: settings.enabled,
            available: available, blocked: blocked, open: isOpen(), automatic: isAutomatic())
        {
        case .launch: launch()
        case .dismiss: dismiss()
        case .none: break
        }
    }
}
