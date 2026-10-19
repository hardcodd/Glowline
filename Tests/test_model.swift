import Foundation
import AppKit

/// Exercise startup recovery and persistence only in a disposable data directory.
@MainActor func runModelTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glowline-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fresh = AppModel(stateDirectory: directory.appendingPathComponent("fresh"), inspectSystem: false)
    precondition(fresh.settings.port.isEmpty && fresh.profiles.isEmpty && fresh.notice.isEmpty)
    var trackingTicks = 0
    _ = NSApplication.shared
    let trackingTimer = statusPollingTimer { trackingTicks += 1 }
    defer { trackingTimer.invalidate() }
    let trackingDeadline = Date().addingTimeInterval(1.2)
    while trackingTicks == 0 && Date() < trackingDeadline {
        RunLoop.main.run(mode: .eventTracking, before: trackingDeadline)
    }
    precondition(trackingTicks > 0, "Status polling stopped during slider event tracking")
    let state = directory.appendingPathComponent("settings.json")
    let legacy = Data("{\"schemaVersion\":1,\"settings\":{\"brightness\":0.37,\"launchAtLogin\":false,\"port\":\"/dev/cu.usbserial-example\"},\"profiles\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"settings\":{\"warmth\":0.8}}]}".utf8)
    try legacy.write(to: state)
    let model = AppModel(stateDirectory: directory, inspectSystem: false)
    precondition(model.settings.brightness == 0.37 && model.settings.warmth == 0.5)
    precondition(model.profiles.count == 1 && model.profiles[0].settings.warmth == 0.8)
    model.resetDefaults()
    precondition(model.settings.port == "/dev/cu.usbserial-example" && model.profiles.count == 1)
    // Keep the test's login preference unchanged; never register a login item.
    model.settings.launchAtLogin = false
    model.applySettings()
    let reloaded = try SavedState.decode(Data(contentsOf: state))
    precondition(reloaded.settings == model.settings && reloaded.profiles.count == 1)
    for mode in 0...8 {
        model.settings.mode = mode
        model.settings.effect.speed = Double(mode + 1) * 0.4
        model.settings.effect.cometTail = 1.6
        model.profileName = "Mode \(mode)"; model.saveProfile()
        let savedMode = try SavedState.decode(Data(contentsOf: state))
        precondition(savedMode.settings.mode == mode && savedMode.profiles.last?.settings.mode == mode)
        let tuning = try JSONSerialization.jsonObject(with: Data(contentsOf: model.tuningURL)) as! [String: Any]
        precondition(tuning["mode"] as? Int == mode)
        precondition(tuning["speed"] as? Double == model.settings.effect.speed)
        precondition(tuning["cometTail"] as? Double == 1.6)
        model.settings.effect.speed = 4.9
        model.settings.mode = 0
        model.activate(savedMode.profiles.last!)
        precondition(model.settings.mode == mode)
        precondition(model.settings.effect == savedMode.settings.effect)
    }
    let independentStartup = AppModel(stateDirectory: directory, inspectSystem: false)
    for mode in Settings.supportedModes {
        independentStartup.settings.mode = mode
        precondition(abs(independentStartup.settings.effect.speed - Double(mode + 1) * 0.4) < 0.00001)
    }
    let invalid = Data("{invalid-json".utf8)
    try invalid.write(to: state)
    let recovered = AppModel(stateDirectory: directory, inspectSystem: false)
    precondition(!recovered.notice.isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("unreadable-settings-") }
    precondition(backups.count == 1)
    let backup = try Data(contentsOf: backups[0])
    precondition(backup == invalid)
    let parser = ISO8601DateFormatter()
    var instant = parser.date(from: "2026-10-16T21:59:59Z")!
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let scheduled = AppModel(stateDirectory: directory.appendingPathComponent("scheduled"), inspectSystem: false, clock: { instant }, calendar: { calendar })
    scheduled.settings.launchAtLogin = false
    scheduled.settings.brightness = 0.73
    scheduled.settings.brightnessSchedule.enabled = true
    scheduled.profileName = "Scheduled"; scheduled.saveProfile()
    let persisted = try Data(contentsOf: scheduled.stateURL)
    func tuningBrightness() throws -> Double {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: scheduled.tuningURL)) as! [String: Any]
        return value["brightness"] as! Double
    }
    precondition(scheduled.effectiveBrightness == 1 && scheduled.scheduledPeriod == .day)
    let dayTuning = try tuningBrightness(); precondition(dayTuning == 1)
    instant = parser.date(from: "2026-10-16T22:00:00Z")!
    try scheduled.updateScheduledBrightness()
    precondition(scheduled.effectiveBrightness == 0.5 && scheduled.scheduledPeriod == .night)
    let nightTuning = try tuningBrightness(); precondition(nightTuning == 0.5)
    let unchanged = try FileManager.default.attributesOfItem(atPath: scheduled.tuningURL.path)[.systemFileNumber] as! NSNumber
    try scheduled.updateScheduledBrightness()
    let unchangedAgain = try FileManager.default.attributesOfItem(atPath: scheduled.tuningURL.path)[.systemFileNumber] as! NSNumber
    precondition(unchanged == unchangedAgain)
    let afterClock = try Data(contentsOf: scheduled.stateURL); precondition(afterClock == persisted)
    // Jump over hours as on wake, and backwards as after a manual clock correction.
    instant = parser.date(from: "2026-10-17T12:00:00Z")!
    try scheduled.updateScheduledBrightness(); precondition(scheduled.effectiveBrightness == 1)
    instant = parser.date(from: "2026-10-17T07:00:00Z")!
    try scheduled.updateScheduledBrightness(); precondition(scheduled.effectiveBrightness == 0.5)
    instant = parser.date(from: "2026-10-17T15:00:00Z")!
    calendar.timeZone = TimeZone(identifier: "Asia/Novosibirsk")!
    try scheduled.updateScheduledBrightness(); precondition(scheduled.effectiveBrightness == 0.5)
    scheduled.settings.brightnessSchedule.enabled = false
    scheduled.applySettings(); precondition(scheduled.effectiveBrightness == 0.73)
    let manualTuning = try tuningBrightness(); precondition(manualTuning == 0.73)
    precondition(scheduled.profiles[0].settings.brightnessSchedule.enabled)
    scheduled.activate(scheduled.profiles[0]); scheduled.applySettings()
    precondition(scheduled.effectiveBrightness == 0.5 && scheduled.settings.brightness == 0.73)
    let startup = AppModel(stateDirectory: scheduled.directory, inspectSystem: false, clock: { instant }, calendar: { calendar })
    precondition(startup.effectiveBrightness == 0.5 && startup.settings.brightness == 0.73)
    print("Model schedule clock/wake, tuning deduplication, profile restore and startup contracts passed")
    print("Startup migration, profile preservation and corruption backup contracts passed")
}
