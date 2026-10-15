import Foundation

/// Exercise startup recovery and persistence only in a disposable data directory.
@MainActor func runModelTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Glowline-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fresh = AppModel(stateDirectory: directory.appendingPathComponent("fresh"), inspectSystem: false)
    precondition(fresh.settings.port.isEmpty && fresh.profiles.isEmpty && fresh.notice.isEmpty)
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
    let invalid = Data("{invalid-json".utf8)
    try invalid.write(to: state)
    let recovered = AppModel(stateDirectory: directory, inspectSystem: false)
    precondition(!recovered.notice.isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("unreadable-settings-") }
    precondition(backups.count == 1)
    let backup = try Data(contentsOf: backups[0])
    precondition(backup == invalid)
    print("Startup migration, profile preservation and corruption backup contracts passed")
}
