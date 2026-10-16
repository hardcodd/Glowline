import Foundation

@main struct ScheduleTests {
    static func main() throws {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = parts.hour! * 60 + parts.minute!
        let object: [String: Any] = ["brightness": 0.73, "brightnessSchedule": ["enabled": true, "dayStart": (minute+1)%1440, "nightStart": (minute+1439)%1440, "dayBrightness": 1.0, "nightBrightness": 0.5]]
        let settings = try Settings.decodeMerged(JSONSerialization.data(withJSONObject: object))
        let engine = try JSONSerialization.jsonObject(with: settings.engineData()) as! [String: Any]
        guard engine["brightness"] as? Double == 0.5 else {
            print("FAIL: active nightly schedule must reach engine without replacing saved manual brightness")
            exit(1)
        }
        precondition(settings.brightness == 0.73)
        let parser = ISO8601DateFormatter()
        func date(_ text: String) -> Date { parser.date(from: text)! }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var schedule = BrightnessSchedule(); schedule.enabled = true
        for (stamp, expected) in [("2026-10-16T07:59:59Z", BrightnessSchedule.Period.night), ("2026-10-16T08:00:00Z", .day), ("2026-10-16T21:59:59Z", .day), ("2026-10-16T22:00:00Z", .night), ("2026-10-17T00:00:00Z", .night)] {
            precondition(schedule.period(at: date(stamp), calendar: utc) == expected)
        }
        var active = Settings(); active.brightness = 0.73; active.brightnessSchedule = schedule
        for (stamp, expected) in [("2026-10-16T08:00:00Z",1.0), ("2026-10-16T22:00:00Z",0.5)] {
            for mode in 0...5 {
                active.mode = mode
                let value = try JSONSerialization.jsonObject(with: active.engineData(at: date(stamp), calendar: utc)) as! [String: Any]
                precondition(value["brightness"] as? Double == expected)
                precondition(active.brightness == 0.73)
            }
        }
        active.enabled = false
        let off = try JSONSerialization.jsonObject(with: active.engineData(at: date("2026-10-16T22:00:00Z"), calendar: utc)) as! [String: Any]
        precondition(off["enabled"] as? Bool == false)
        active.brightnessSchedule.enabled = false
        precondition(active.effectiveBrightness(at: date("2026-10-16T22:00:00Z"), calendar: utc) == 0.73)
        schedule.dayStart = 22*60; schedule.nightStart = 8*60
        for (hour, expected) in [(0,BrightnessSchedule.Period.day),(7,.day),(8,.night),(21,.night),(22,.day),(23,.day)] {
            precondition(schedule.period(at: date(String(format: "2026-10-16T%02d:00:00Z",hour)), calendar: utc) == expected)
        }
        schedule.dayStart = schedule.nightStart
        precondition(schedule.period(at: Date(), calendar: utc) == nil)
        active.brightnessSchedule = schedule
        precondition(active.effectiveBrightness(at: Date(), calendar: utc) == 0.73)
        schedule.dayStart = 8*60; schedule.nightStart = 22*60
        var local = utc; local.timeZone = TimeZone(identifier: "Asia/Novosibirsk")!
        let instant = date("2026-10-16T15:00:00Z")
        precondition(schedule.period(at: instant, calendar: utc) == .day && schedule.period(at: instant, calendar: local) == .night)
        var dst = utc; dst.timeZone = TimeZone(identifier: "America/New_York")!
        schedule.dayStart = 150
        precondition(schedule.period(at: date("2026-03-08T06:59:59Z"), calendar: dst) == .night)
        precondition(schedule.period(at: date("2026-03-08T07:00:00Z"), calendar: dst) == .day)
        precondition(schedule.period(at: date("2026-11-01T05:30:00Z"), calendar: dst) == .night)
        precondition(schedule.period(at: date("2026-11-01T06:30:00Z"), calendar: dst) == .night)
        schedule.dayStart = -3; schedule.nightStart = 99999; schedule.dayBrightness = .infinity; schedule.nightBrightness = 2
        schedule.validate()
        precondition(schedule.dayStart == 0 && schedule.nightStart == 1439 && schedule.dayBrightness == 0 && schedule.nightBrightness == 1)
        let legacy = try SavedState.decode(Data("{\"schemaVersion\":1,\"settings\":{\"brightness\":0.73},\"profiles\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"settings\":{}}]}".utf8))
        precondition(!legacy.settings.brightnessSchedule.enabled && !legacy.profiles[0].settings.brightnessSchedule.enabled)
        let partial = try Settings.decodeMerged(Data("{\"brightnessSchedule\":{\"enabled\":true}}".utf8))
        precondition(partial.brightnessSchedule.enabled && partial.brightnessSchedule.nightBrightness == 0.5)
        for invalid in ["{\"brightnessSchedule\":null}", "{\"brightnessSchedule\":{\"dayStart\":\"8\"}}"] {
            do { _ = try Settings.decodeMerged(Data(invalid.utf8)); preconditionFailure("Invalid schedule accepted") } catch {}
        }
        let saved = SavedState(settings: settings, profiles: [Profile(name: "Scheduled", settings: settings)])
        let restored = try SavedState.decode(JSONEncoder().encode(saved))
        precondition(restored.settings == settings && restored.profiles[0].settings == settings)
        print("Schedule boundaries, midnight, timezone, DST, master-off, migration and persistence contracts passed")
    }
}
