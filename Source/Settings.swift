import Foundation

struct RGB: Codable, Equatable {
    var red: Double; var green: Double; var blue: Double
    static let amber = RGB(red: 1, green: 160.0/255, blue: 64.0/255)
    static let blue = RGB(red: 72.0/255, green: 96.0/255, blue: 1)
    var bytes: [Int] { [red, green, blue].map { Int(($0.clamped(0...1) * 255).rounded()) } }
}
extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double { isFinite ? min(range.upperBound, max(range.lowerBound, self)) : range.lowerBound }
}

/// Daily local wall-clock periods; start is inclusive and the next start exclusive.
/// Missing legacy schedules are disabled. Equal starts deliberately use manual brightness.
struct BrightnessSchedule: Codable, Equatable {
    enum Period { case day, night }
    var enabled = false
    var dayStart = 8 * 60
    var nightStart = 22 * 60
    var dayBrightness = 1.0
    var nightBrightness = 0.5
    var isActive: Bool { enabled && dayStart != nightStart }
    private enum CodingKeys: String, CodingKey { case enabled, dayStart, nightStart, dayBrightness, nightBrightness }
    init() {}
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.enabled) { enabled = try values.decode(Bool.self, forKey: .enabled) }
        if values.contains(.dayStart) { dayStart = try values.decode(Int.self, forKey: .dayStart) }
        if values.contains(.nightStart) { nightStart = try values.decode(Int.self, forKey: .nightStart) }
        if values.contains(.dayBrightness) { dayBrightness = try values.decode(Double.self, forKey: .dayBrightness) }
        if values.contains(.nightBrightness) { nightBrightness = try values.decode(Double.self, forKey: .nightBrightness) }
        validate()
    }
    mutating func validate() {
        dayStart = min(1439, max(0, dayStart)); nightStart = min(1439, max(0, nightStart))
        dayBrightness = dayBrightness.clamped(0...1); nightBrightness = nightBrightness.clamped(0...1)
    }
    func period(at date: Date, calendar: Calendar = .current) -> Period? {
        guard isActive else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let day = dayStart < nightStart ? minute >= dayStart && minute < nightStart : minute >= dayStart || minute < nightStart
        return day ? .day : .night
    }
}

/// Persisted preferences and the accepted hardware-specific defaults.
struct Settings: Codable, Equatable {
    var enabled = true
    var mode = 0
    var brightness = 1.0
    var brightnessSchedule = BrightnessSchedule()
    var warmth = 0.5
    var saturation = 1.0
    var gamma = 1.0
    var redGain = 1.0; var greenGain = 1.0; var blueGain = 1.0
    var blackThreshold = 0.0
    var edgeDepth = 0.15
    var detailMode = false
    var releaseSeconds = 0.18
    var attackSeconds = 0.0
    var mirrored = true
    var offset = 0
    var leftEnabled = true; var topEnabled = true; var rightEnabled = true; var bottomEnabled = true
    var leftGain = 1.0; var topGain = 1.0; var rightGain = 1.0; var bottomGain = 1.0
    var fps = 33.68
    var captureFps = 120
    var keepaliveSeconds = 0.1
    var skipUnchanged = true
    var primary = RGB.amber
    var secondary = RGB.blue
    var speed = 1.0
    var reverse = false
    var port = ""
    var displayID: UInt32 = 0
    var theme = "dark"
    var launchAtLogin = true
    var startHidden = true
    var reconnect = true
    var offOnQuit = true

    private enum CodingKeys: String, CodingKey {
        case enabled, mode, brightness, brightnessSchedule, warmth, saturation, gamma, redGain, greenGain, blueGain, blackThreshold, edgeDepth, detailMode, releaseSeconds, attackSeconds, mirrored, offset, leftEnabled, topEnabled, rightEnabled, bottomEnabled, leftGain, topGain, rightGain, bottomGain, fps, captureFps, keepaliveSeconds, skipUnchanged, primary, secondary, speed, reverse, port, displayID, theme, launchAtLogin, startHidden, reconnect, offOnQuit
    }
    init() {}
    /// Missing fields inherit current defaults; present invalid values still fail.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.enabled) { enabled = try values.decode(Bool.self, forKey: .enabled) }
        if values.contains(.mode) { mode = try values.decode(Int.self, forKey: .mode) }
        if values.contains(.brightness) { brightness = try values.decode(Double.self, forKey: .brightness) }
        if values.contains(.brightnessSchedule) { brightnessSchedule = try values.decode(BrightnessSchedule.self, forKey: .brightnessSchedule) }
        if values.contains(.warmth) { warmth = try values.decode(Double.self, forKey: .warmth) }
        if values.contains(.saturation) { saturation = try values.decode(Double.self, forKey: .saturation) }
        if values.contains(.gamma) { gamma = try values.decode(Double.self, forKey: .gamma) }
        if values.contains(.redGain) { redGain = try values.decode(Double.self, forKey: .redGain) }
        if values.contains(.greenGain) { greenGain = try values.decode(Double.self, forKey: .greenGain) }
        if values.contains(.blueGain) { blueGain = try values.decode(Double.self, forKey: .blueGain) }
        if values.contains(.blackThreshold) { blackThreshold = try values.decode(Double.self, forKey: .blackThreshold) }
        if values.contains(.edgeDepth) { edgeDepth = try values.decode(Double.self, forKey: .edgeDepth) }
        if values.contains(.detailMode) { detailMode = try values.decode(Bool.self, forKey: .detailMode) }
        if values.contains(.releaseSeconds) { releaseSeconds = try values.decode(Double.self, forKey: .releaseSeconds) }
        if values.contains(.attackSeconds) { attackSeconds = try values.decode(Double.self, forKey: .attackSeconds) }
        if values.contains(.mirrored) { mirrored = try values.decode(Bool.self, forKey: .mirrored) }
        if values.contains(.offset) { offset = try values.decode(Int.self, forKey: .offset) }
        if values.contains(.leftEnabled) { leftEnabled = try values.decode(Bool.self, forKey: .leftEnabled) }
        if values.contains(.topEnabled) { topEnabled = try values.decode(Bool.self, forKey: .topEnabled) }
        if values.contains(.rightEnabled) { rightEnabled = try values.decode(Bool.self, forKey: .rightEnabled) }
        if values.contains(.bottomEnabled) { bottomEnabled = try values.decode(Bool.self, forKey: .bottomEnabled) }
        if values.contains(.leftGain) { leftGain = try values.decode(Double.self, forKey: .leftGain) }
        if values.contains(.topGain) { topGain = try values.decode(Double.self, forKey: .topGain) }
        if values.contains(.rightGain) { rightGain = try values.decode(Double.self, forKey: .rightGain) }
        if values.contains(.bottomGain) { bottomGain = try values.decode(Double.self, forKey: .bottomGain) }
        if values.contains(.fps) { fps = try values.decode(Double.self, forKey: .fps) }
        if values.contains(.captureFps) { captureFps = try values.decode(Int.self, forKey: .captureFps) }
        if values.contains(.keepaliveSeconds) { keepaliveSeconds = try values.decode(Double.self, forKey: .keepaliveSeconds) }
        if values.contains(.skipUnchanged) { skipUnchanged = try values.decode(Bool.self, forKey: .skipUnchanged) }
        if values.contains(.primary) { primary = try values.decode(RGB.self, forKey: .primary) }
        if values.contains(.secondary) { secondary = try values.decode(RGB.self, forKey: .secondary) }
        if values.contains(.speed) { speed = try values.decode(Double.self, forKey: .speed) }
        if values.contains(.reverse) { reverse = try values.decode(Bool.self, forKey: .reverse) }
        if values.contains(.port) { port = try values.decode(String.self, forKey: .port) }
        if values.contains(.displayID) { displayID = try values.decode(UInt32.self, forKey: .displayID) }
        if values.contains(.theme) { theme = try values.decode(String.self, forKey: .theme) }
        if values.contains(.launchAtLogin) { launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin) }
        if values.contains(.startHidden) { startHidden = try values.decode(Bool.self, forKey: .startHidden) }
        if values.contains(.reconnect) { reconnect = try values.decode(Bool.self, forKey: .reconnect) }
        if values.contains(.offOnQuit) { offOnQuit = try values.decode(Bool.self, forKey: .offOnQuit) }
        validate()
    }

    mutating func validate() {
        mode = min(5, max(0, mode)); brightness = brightness.clamped(0...1)
        brightnessSchedule.validate()
        warmth = warmth.clamped(0...0.9); saturation = saturation.clamped(0...2)
        gamma = gamma.clamped(0.5...2.5); blackThreshold = blackThreshold.clamped(0...0.2)
        redGain = redGain.clamped(0...2); greenGain = greenGain.clamped(0...2); blueGain = blueGain.clamped(0...2)
        leftGain = leftGain.clamped(0...2); topGain = topGain.clamped(0...2)
        rightGain = rightGain.clamped(0...2); bottomGain = bottomGain.clamped(0...2)
        edgeDepth = edgeDepth.clamped(0...0.35); releaseSeconds = releaseSeconds.clamped(0...1)
        attackSeconds = attackSeconds.clamped(0...1); fps = fps.clamped(5...33.68)
        captureFps = min(240, max(30, captureFps)); keepaliveSeconds = keepaliveSeconds.clamped(0.05...1)
        offset = min(111, max(-111, offset)); speed = speed.clamped(0.1...5)
        if !["system", "dark", "light"].contains(theme) { theme = "dark" }
        if !port.isEmpty && (!port.hasPrefix("/dev/cu.usbserial-") || port.count <= "/dev/cu.usbserial-".count || port.split(separator: "/").count != 2) { port = "" }
        primary = RGB(red: primary.red.clamped(0...1), green: primary.green.clamped(0...1), blue: primary.blue.clamped(0...1))
        secondary = RGB(red: secondary.red.clamped(0...1), green: secondary.green.clamped(0...1), blue: secondary.blue.clamped(0...1))
    }
    func effectiveBrightness(at date: Date, calendar: Calendar = .current) -> Double {
        switch brightnessSchedule.period(at: date, calendar: calendar) {
        case .day: return brightnessSchedule.dayBrightness
        case .night: return brightnessSchedule.nightBrightness
        case nil: return brightness
        }
    }
    func engineData(at date: Date = Date(), calendar: Calendar = .current) throws -> Data {
        var safe = self; safe.validate()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(safe)) as! [String: Any]
        object["brightness"] = safe.effectiveBrightness(at: date, calendar: calendar)
        object["primary"] = safe.primary.bytes; object["secondary"] = safe.secondary.bytes
        object["drainEvery"] = 1; object["drainEach"] = false; object["queueLimit"] = 64; object["trace"] = false
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    /// Merge additive future settings with defaults while rejecting invalid value types.
    static func decodeMerged(_ data: Data) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: data)
    }
}
struct Profile: Codable, Identifiable { var id = UUID(); var name: String; var settings: Settings }
struct SavedState: Codable {
    var schemaVersion = 1
    var settings: Settings
    var profiles: [Profile]

    /// Shared startup/import boundary; reject future schemas without replacing data.
    static func decode(_ data: Data) throws -> SavedState {
        guard data.count < 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let saved = try JSONDecoder().decode(SavedState.self, from: data)
        guard saved.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        return saved
    }
}

/// Behavior tests run without touching USB, permissions, login items, or preferences.
func runSettingsTests() throws {
    let defaults = Settings()
    precondition(defaults.port.isEmpty)
    let selectedPort = "/dev/cu.usbserial-example"
    let selected = try Settings.decodeMerged(Data("{\"port\":\"\(selectedPort)\"}".utf8))
    precondition(selected.port == selectedPort)
    for invalidPort in ["/tmp/device", "/dev/cu.usbserial-../other", "/dev/cu.usbserial-"] {
        let decoded = try Settings.decodeMerged(Data("{\"port\":\"\(invalidPort)\"}".utf8))
        precondition(decoded.port.isEmpty)
    }
    precondition(defaults.warmth == 0.5 && defaults.mirrored && defaults.brightness == 1)
    precondition(!defaults.detailMode)
    var detailed = defaults; detailed.detailMode = true; detailed.saturation = 0.396591796875
    let detailRoundtrip = try Settings.decodeMerged(JSONEncoder().encode(detailed))
    precondition(detailRoundtrip == detailed)
    let detailPayload = try JSONSerialization.jsonObject(with: detailed.engineData()) as! [String: Any]
    precondition((detailPayload["detailMode"] as? Bool) == true)
    precondition(defaults.edgeDepth == 0.15 && defaults.releaseSeconds == 0.18 && defaults.launchAtLogin && defaults.startHidden)
    let roundtrip = try Settings.decodeMerged(JSONEncoder().encode(defaults)); precondition(roundtrip == defaults)
    let migrated = try Settings.decodeMerged(Data("{\"warmth\":0.8,\"brightness\":2,\"mode\":99}".utf8))
    precondition(migrated.warmth == 0.8 && migrated.brightness == 1 && migrated.mode == 5 && migrated.mirrored)
    let engine = try JSONSerialization.jsonObject(with: defaults.engineData()) as! [String: Any]
    precondition((engine["primary"] as? [Int]) == [255,160,64]); precondition((engine["drainEvery"] as? Int) == 1)
    precondition((engine["skipUnchanged"] as? Bool) == true)
    let profile = Profile(name: "Test", settings: defaults)
    let saved = SavedState(settings: defaults, profiles: [profile])
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(saved))
    precondition(restored.profiles.first?.settings == defaults)
    do { _ = try Settings.decodeMerged(Data("{\"warmth\":\"bad\"}".utf8)); preconditionFailure("Invalid type accepted") } catch {}
    // Exercise the exact persisted-state decoder used at startup and import.
    let legacy = Data("{\"schemaVersion\":1,\"settings\":{\"brightness\":0.37},\"profiles\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"settings\":{\"warmth\":0.8}}]}".utf8)
    let legacyState = try SavedState.decode(legacy)
    precondition(legacyState.settings.brightness == 0.37 && legacyState.settings.warmth == 0.5)
    precondition(legacyState.profiles[0].settings.warmth == 0.8 && legacyState.profiles[0].settings.port.isEmpty)
    precondition(!legacyState.settings.detailMode && !legacyState.profiles[0].settings.detailMode)
    let detailSaved = SavedState(settings: detailed, profiles: [Profile(name: "Detail", settings: detailed)])
    let detailRestored = try SavedState.decode(JSONEncoder().encode(detailSaved))
    precondition(detailRestored.settings == detailed && detailRestored.profiles[0].settings == detailed)
    for invalid in ["{\"schemaVersion\":2,\"settings\":{},\"profiles\":[]}", "{\"schemaVersion\":1,\"settings\":{\"warmth\":null},\"profiles\":[]}"] {
        do { _ = try SavedState.decode(Data(invalid.utf8)); preconditionFailure("Invalid saved state accepted") } catch {}
    }
    print("Settings, migration, profile and engine contracts passed")
}
