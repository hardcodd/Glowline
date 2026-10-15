import AppKit
import SwiftUI
import Combine
import ServiceManagement
import CoreGraphics
import UniformTypeIdentifiers

func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }
struct EngineStatus: Decodable {
    var pid: Int32; var timestamp: Double; var serialVerified: Int; var fps: Double
    var brightness: Double; var mirrored: Int; var warmth: Double; var mode: Int; var enabled: Int
    var captureReady: Int; var colors: [[Int]]; var framesSent: Int; var writeMs: Double
    var edgeDepth: Double; var releaseSeconds: Double; var captureFps: Int
    var captureReceived: UInt64; var captureAccepted: UInt64; var targetFps: Double
}
struct DisplayChoice: Identifiable { var id: UInt32; var name: String }

@MainActor final class AppModel: ObservableObject {
    @Published var settings = Settings() { didSet { if initialized { scheduleSave() } } }
    @Published var profiles: [Profile] = []
    @Published var status: EngineStatus?
    @Published var message = ""
    @Published var notice = ""
    @Published var permission = false
    @Published var loginStatus = ""
    @Published var displays: [DisplayChoice] = []
    @Published var ports: [String] = []
    @Published var profileName = ""
    @Published var selectedProfile: UUID?
    @Published var page = "overview"
    @Published var confirmReset = false
    let directory: URL
    let stateURL: URL
    let statusURL: URL
    let tuningURL: URL
    let logURL: URL
    private var process: Process?
    private var logHandle: FileHandle?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var initialized = false
    private var quitting = false
    private var lastAttempt = Date.distantPast
    private var launchedAt = Date.distantPast
    private var activePort = ""
    private var activeDisplay: UInt32 = 0
    private var hadPermission = false
    private var lastLoginPreference = true

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Glowline", isDirectory: true)
        stateURL = directory.appendingPathComponent("settings.json")
        statusURL = directory.appendingPathComponent("engine-status.json")
        tuningURL = directory.appendingPathComponent("engine-status.json.tuning.json")
        logURL = directory.appendingPathComponent("engine.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let data = try? Data(contentsOf: stateURL) {
                do {
                    let saved = try JSONDecoder().decode(SavedState.self, from: data)
                    guard saved.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                    var restored = saved.settings; restored.validate(); settings = restored
                    profiles = saved.profiles.map { value in var p = value; p.settings.validate(); return p }
                } catch {
                    let backup = directory.appendingPathComponent("unreadable-settings-\(Int(Date().timeIntervalSince1970)).json")
                    try data.write(to: backup, options: .atomic)
                    notice = tr("settings.recovered")
                }
            }
        } catch { notice = tr("settings.error") + " " + error.localizedDescription }
        lastLoginPreference = settings.launchAtLogin
        permission = CGPreflightScreenCaptureAccess(); hadPermission = permission
        refreshDevices(); initialized = true
    }
    var isConnected: Bool { guard let s = status else { return false }; return s.serialVerified == 1 && Date().timeIntervalSince1970 - s.timestamp < 3 && s.pid == process?.processIdentifier }
    var isStarting: Bool { process?.isRunning == true && !isConnected && Date().timeIntervalSince(launchedAt) < 8 }
    var modeName: String { tr("mode.\(settings.mode)") }
    var connectionTitle: String {
        if isConnected {
            if settings.mode == 0 && status?.captureReady == 0 { return tr("status.captureStarting") }
            return settings.enabled ? tr("status.connected") : tr("status.off")
        }
        if isStarting { return tr("status.connecting") }
        if settings.mode == 0 && !permission { return tr("status.permission") }
        return tr("status.waiting")
    }
    var rateText: String {
        guard isConnected, let s = status else { return "—" }
        if settings.skipUnchanged && s.fps < 13 { return tr("status.static") }
        return String(format: "%.1f FPS", s.fps)
    }
    func begin() {
        configureLogin()
        applySettings()
        startEngine()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    private func scheduleSave() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.applySettings() }; pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }
    func applySettings() {
        do {
            var safe = settings; safe.validate()
            if safe != settings { settings = safe }
            try JSONEncoder().encode(SavedState(settings: safe, profiles: profiles)).write(to: stateURL, options: .atomic)
            try safe.engineData().write(to: tuningURL, options: .atomic)
            if settings.launchAtLogin != lastLoginPreference { configureLogin(); lastLoginPreference = settings.launchAtLogin }
            if process?.isRunning == true && (activePort != settings.port || activeDisplay != settings.displayID) { restartEngine() }
        } catch { notice = tr("settings.error") + " " + error.localizedDescription }
    }
    func configureLogin() {
        do {
            if settings.launchAtLogin && (SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound) { try SMAppService.mainApp.register() }
            if !settings.launchAtLogin && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
        } catch { notice = tr("login.error") + " " + error.localizedDescription }
        updateLoginStatus()
    }
    private func updateLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = tr("login.enabled")
        case .requiresApproval: loginStatus = tr("login.approval")
        case .notRegistered: loginStatus = tr("login.disabled")
        default: loginStatus = tr("login.unavailable")
        }
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
        permission = CGPreflightScreenCaptureAccess()
        if permission { restartEngine() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func refreshDevices() {
        ports = ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []).filter { $0.hasPrefix("cu.usbserial-") }.map { "/dev/" + $0 }.sorted()
        displays = [DisplayChoice(id: 0, name: tr("display.main"))]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displays.append(DisplayChoice(id: number.uint32Value, name: screen.localizedName))
            }
        }
    }
    private func tick() {
        permission = CGPreflightScreenCaptureAccess()
        updateLoginStatus()
        if permission && !hadPermission { hadPermission = true; restartEngine() }
        hadPermission = permission
        if let data = try? Data(contentsOf: statusURL), let next = try? JSONDecoder().decode(EngineStatus.self, from: data), next.pid == process?.processIdentifier { status = next }
        if process?.isRunning == true, let s = status, Date().timeIntervalSince1970 - s.timestamp > 8, Date().timeIntervalSince(launchedAt) > 10 {
            message = tr("device.unresponsive"); return
        }
        if process?.isRunning != true && settings.reconnect && Date().timeIntervalSince(lastAttempt) > 5 { startEngine() }
    }
    func startEngine() {
        guard !quitting, process?.isRunning != true else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased().contains("skydimo") == true }) {
            message = tr("device.skydimo"); lastAttempt = Date(); return
        }
        if settings.mode == 0 && !permission { message = tr("permission.description"); return }
        guard FileManager.default.fileExists(atPath: settings.port) else { message = tr("device.missing"); lastAttempt = Date(); return }
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "GlowlineEngine") else { message = tr("device.engineMissing"); return }
        do {
            try settings.engineData().write(to: tuningURL, options: .atomic)
            let p = Process(); p.executableURL = url; p.arguments = [statusURL.path]
            var env = ProcessInfo.processInfo.environment; env["GLOWLINE_PORT"] = settings.port; env["GLOWLINE_PARENT"] = String(ProcessInfo.processInfo.processIdentifier); env["GLOWLINE_DISPLAY"] = String(settings.displayID)
            p.environment = env
            if (try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 2_000_000 { try? FileManager.default.removeItem(at: logURL) }
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            logHandle = try FileHandle(forWritingTo: logURL); try logHandle?.seekToEnd(); p.standardOutput = logHandle; p.standardError = logHandle
            p.terminationHandler = { [weak self] finished in Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.message = finished.terminationStatus == 3 ? tr("device.busy") : tr("device.stopped")
                self.status = nil
            } }
            lastAttempt = Date(); launchedAt = Date(); activePort = settings.port; activeDisplay = settings.displayID
            process = p; try p.run(); message = ""
        } catch { message = error.localizedDescription; lastAttempt = Date() }
    }
    func restartEngine() {
        guard !quitting else { return }
        if let p = process, p.isRunning {
            p.terminationHandler = nil; p.terminate()
            Task { @MainActor [weak self] in
                for _ in 0..<30 { if !p.isRunning { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
                guard let self else { return }
                if p.isRunning { self.message = tr("device.unresponsive"); return }
                self.process = nil; self.status = nil; self.startEngine()
            }
        } else { process = nil; status = nil; startEngine() }
    }
    func resetDefaults() { let port = settings.port; settings = Settings(); settings.port = port; selectedProfile = nil; notice = tr("settings.resetDone") }
    func saveProfile() {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { profiles[index].settings = settings; selectedProfile = profiles[index].id }
        else { let p = Profile(name: String(name.prefix(60)), settings: settings); profiles.append(p); selectedProfile = p.id }
        profileName = ""; applySettings(); notice = tr("profile.saved")
    }
    func activate(_ profile: Profile) { settings = profile.settings; selectedProfile = profile.id; notice = tr("profile.applied") }
    func deleteProfile(_ id: UUID) { profiles.removeAll { $0.id == id }; if selectedProfile == id { selectedProfile = nil }; applySettings() }
    func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Glowline-settings.json"
        if panel.runModal() == .OK, let url = panel.url { do { try JSONEncoder().encode(SavedState(settings: settings, profiles: profiles)).write(to: url, options: .atomic) } catch { notice = error.localizedDescription } }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                guard data.count < 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let saved = try JSONDecoder().decode(SavedState.self, from: data)
                guard saved.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                var safe = saved.settings; safe.validate(); settings = safe
                profiles = saved.profiles.map { var p = $0; p.settings.validate(); return p }; applySettings(); notice = tr("profile.imported")
            } catch { notice = tr("profile.invalid") + " " + error.localizedDescription }
        }
    }
    func openLogs() { NSWorkspace.shared.open(logURL) }
    func openDataFolder() { NSWorkspace.shared.open(directory) }
    func shutdown() {
        guard !quitting else { return }; quitting = true; timer?.invalidate(); pending?.cancel(); applySettings()
        if let p = process, p.isRunning {
            if settings.offOnQuit {
                var off = settings; off.enabled = false; try? off.engineData().write(to: tuningURL, options: .atomic)
                Thread.sleep(forTimeInterval: 0.25)
            }
            p.terminationHandler = nil; p.terminate()
            for _ in 0..<30 { if !p.isRunning { break }; Thread.sleep(forTimeInterval: 0.1) }
        }
        try? settings.engineData().write(to: tuningURL, options: .atomic)
        try? logHandle?.close()
    }
}

/// The Objective-C engine serializes C flags as JSON integers.
func runStatusTests() throws {
    let payload = """
    {"pid":42,"timestamp":100,"serialVerified":1,"fps":26.7,"brightness":100,"mirrored":1,"warmth":0.5,"mode":0,"enabled":1,"captureReady":1,"colors":[[255,210,128]],"framesSent":10,"writeMs":37,"edgeDepth":0.15,"releaseSeconds":0.18,"captureFps":120,"captureReceived":120,"captureAccepted":120,"targetFps":33.68}
    """
    let status = try JSONDecoder().decode(EngineStatus.self, from: Data(payload.utf8))
    precondition(status.captureReady == 1 && status.mirrored == 1 && status.enabled == 1 && status.serialVerified == 1)
    precondition(status.colors[0] == [255,210,128] && status.fps == 26.7)
}
