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

/// Persisted preferences and the accepted hardware-specific defaults.
struct Settings: Codable, Equatable {
    var enabled = true
    var mode = 0
    var brightness = 1.0
    var warmth = 0.5
    var saturation = 1.0
    var gamma = 1.0
    var redGain = 1.0; var greenGain = 1.0; var blueGain = 1.0
    var blackThreshold = 0.0
    var edgeDepth = 0.15
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

    mutating func validate() {
        mode = min(5, max(0, mode)); brightness = brightness.clamped(0...1)
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
    func engineData() throws -> Data {
        var safe = self; safe.validate()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(safe)) as! [String: Any]
        object["primary"] = safe.primary.bytes; object["secondary"] = safe.secondary.bytes
        object["drainEvery"] = 1; object["drainEach"] = false; object["queueLimit"] = 64; object["trace"] = false
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    /// Merge additive future settings with defaults while rejecting invalid value types.
    static func decodeMerged(_ data: Data) throws -> Settings {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
        merged.merge(object) { _, new in new }
        var result = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: merged))
        result.validate(); return result
    }
}
struct Profile: Codable, Identifiable { var id = UUID(); var name: String; var settings: Settings }
struct SavedState: Codable { var schemaVersion = 1; var settings: Settings; var profiles: [Profile] }

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
    print("Settings, migration, profile and engine contracts passed")
}
