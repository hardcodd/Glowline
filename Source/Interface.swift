import SwiftUI
import AppKit

extension RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
    init(color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(c.redComponent); green = Double(c.greenComponent); blue = Double(c.blueComponent)
    }
}
/// AppKit owns appearance so SwiftUI, window materials and native panels agree.
@MainActor enum AppAppearance {
    static func apply(_ theme: String) {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

/// Keep warm decoration separate from text contrast in the light appearance.
enum AppPalette {
    static let amber = NSColor(name: "GlowlineAmber") { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 1, green: 0.69, blue: 0.34, alpha: 1)
        }
        return NSColor(srgbRed: 1, green: 0.60, blue: 0.12, alpha: 1)
    }
}
private let amber = Color(nsColor: AppPalette.amber)
private let pages: [(String, String)] = [("overview", "sparkles"), ("color", "slider.horizontal.3"), ("schedule", "clock"), ("capture", "viewfinder"), ("effects", "circle.lefthalf.filled"), ("profiles", "square.stack.3d.up"), ("app", "gearshape")]
private let modeIcons = ["display", "lightbulb", "rectangle.fill.on.rectangle.fill", "wind", "rainbow", "flame", "flame.fill", "sparkle", "waveform.path"]

struct RootView: View {
    @ObservedObject var model: AppModel
    var openAmbient: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var accentText: Color { scheme == .dark ? amber : .primary }
    private var canvas: Color { scheme == .dark ? Color(red: 0.065, green: 0.071, blue: 0.086) : Color(nsColor: .windowBackgroundColor) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.4)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch model.page {
                        case "color": colorPage
                        case "schedule": schedulePage
                        case "capture": capturePage
                        case "effects": effectsPage
                        case "profiles": profilesPage
                        case "app": appPage
                        default: overview
                        }
                    }.padding(28).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("settings.scroll")
                .overlay(alignment: .top) {
                    // Transient status must not insert rows above a slider being dragged.
                    VStack(spacing: 12) {
                        if !model.notice.isEmpty {
                            notice.background(canvas, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if !model.connectionHelpDismissed && ((!model.isConnected && !model.isStarting) || (model.isConnected && model.settings.mode == 0 && model.status?.captureReady == 0)) {
                            connectionHelp.background(canvas, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 28).padding(.top, 12)
                    .frame(maxWidth: 920)
                }
            }.background(canvas)
        }
        .frame(minWidth: 980, minHeight: 690)
        .tint(amber)
        .modifier(AppearanceButtonLabels())
        .onChange(of: model.connectionTitle) { _, _ in model.connectionHelpDismissed = false }
        .confirmationDialog(tr("reset.confirm"), isPresented: $model.confirmReset, titleVisibility: .visible) {
            Button(tr("settings.reset"), role: .destructive) { model.resetDefaults() }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 29, weight: .medium)).foregroundStyle(amber.gradient)
                VStack(alignment: .leading, spacing: 2) { Text("Glowline").font(.system(size: 23, weight: .semibold, design: .rounded)); Text(tr("brand.subtitle")).font(.caption).foregroundStyle(.secondary) }
            }.padding(.bottom, 30).padding(.top, 14)
            ForEach(pages, id: \.0) { item in
                Button { model.page = item.0 } label: {
                    Label(tr("page." + item.0), systemImage: item.1)
                        .font(.system(size: 13, weight: model.page == item.0 ? .semibold : .medium))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                        .foregroundStyle(model.page == item.0 ? accentText : Color.primary.opacity(0.7))
                        .background(model.page == item.0 ? amber.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityIdentifier("page." + item.0)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(model.isConnected ? Color.green : Color.orange).frame(width: 6, height: 6); Text(model.connectionTitle).font(.caption.weight(.medium)) }
                Text("SK0L34 · 112 LED").font(.caption2).foregroundStyle(.secondary)
                Text(tr("sidebar.power")).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            Button { NSApp.keyWindow?.close() } label: { Label(tr("window.hide"), systemImage: "menubar.rectangle").font(.caption).frame(maxWidth: .infinity) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 14)
        }.padding(20).frame(width: 220).background(.ultraThinMaterial)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("page." + model.page)).font(.system(size: 25, weight: .semibold))
                Text(tr("subtitle." + model.page)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Toggle(tr("light.enabled"), isOn: $model.settings.enabled).toggleStyle(.switch).accessibilityIdentifier("master.enabled")
                Text(model.modeName + " · " + model.rateText).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private var notice: some View {
        HStack { Image(systemName: "info.circle"); Text(model.notice).font(.caption); Spacer(); Button { model.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.foregroundStyle(.secondary).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
    private var connectionHelp: some View {
        HStack(spacing: 12) {
            Image(systemName: model.permission || model.settings.mode != 0 ? "cable.connector" : "display.trianglebadge.exclamationmark").font(.title2).foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 4) { Text(model.connectionTitle).font(.headline); Text(model.message.isEmpty ? tr("device.missing") : model.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer()
            if !model.permission && model.settings.mode == 0 { Button(tr("permission.allow")) { model.requestPermission() }.buttonStyle(.borderedProminent) }
            else { Button(tr("device.retry")) { model.refreshDevices(); model.restartEngine() }.buttonStyle(.bordered) }
            Button { model.connectionHelpDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(tr("notice.dismiss"))
        }.padding(18).background(amber.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
    private var overview: some View {
        VStack(spacing: 20) {
            MonitorPreview(colors: model.isConnected ? model.status?.colors ?? [] : [], enabled: model.settings.enabled)
            HStack(spacing: 12) {
                stat("stat.mode", value: model.modeName, icon: modeIcons[model.settings.mode])
                stat("stat.brightness", value: percent(model.settings.enabled ? model.effectiveBrightness : 0), icon: "sun.max")
                stat("stat.warmth", value: percent(model.settings.warmth), icon: "thermometer.medium")
            }
            card("light.quick", icon: "slider.horizontal.3") {
                settingSlider("control.brightness", value: $model.settings.brightness, range: 0...1, format: percent)
                settingSlider("control.warmth", value: $model.settings.warmth, range: 0...0.9, format: percent, help: "help.warmth")
                HStack { Text(tr("warmth.neutral")).foregroundStyle(.secondary); Spacer(); Text(tr("warmth.accepted")).foregroundStyle(accentText); Spacer(); Text(tr("warmth.amber")).foregroundStyle(.secondary) }.font(.caption2)
            }
            card("mode.title", icon: "square.grid.2x2") { modeGrid }
        }
    }
    private var colorPage: some View {
        VStack(spacing: 20) {
            card("color.balance", icon: "thermometer.medium") {
                settingSlider("control.warmth", value: $model.settings.warmth, range: 0...0.9, format: percent, help: "help.warmth")
                HStack { swatch(r: 255, g: 255 * (1 - model.settings.warmth * 0.35), b: 255 * (1 - model.settings.warmth)); Text(tr("color.whitePreview")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(tr("color.accepted")) { model.settings.warmth = 0.5 } }
                settingSlider("control.brightness", value: $model.settings.brightness, range: 0...1, format: percent)
                settingSlider("control.saturation", value: $model.settings.saturation, range: 0...2, format: percent)
                settingSlider("control.gamma", value: $model.settings.gamma, range: 0.5...2.5, format: { String(format: "%.2f", $0) }, help: "help.gamma")
            }
            card("color.channels", icon: "paintpalette") {
                settingSlider("control.red", value: $model.settings.redGain, range: 0...2, format: percent)
                settingSlider("control.green", value: $model.settings.greenGain, range: 0...2, format: percent)
                settingSlider("control.blue", value: $model.settings.blueGain, range: 0...2, format: percent)
                Text(tr("help.channels")).font(.caption).foregroundStyle(.secondary)
            }
            card("color.dark", icon: "moon") { settingSlider("control.black", value: $model.settings.blackThreshold, range: 0...0.2, format: percent, help: "help.black") }
        }
    }
    private var schedulePage: some View {
        VStack(spacing: 20) {
            card("schedule.title", icon: "clock") {
                Toggle(tr("schedule.enabled"), isOn: $model.settings.brightnessSchedule.enabled).accessibilityIdentifier("schedule.enabled")
                Text(tr("schedule.help")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label(tr("schedule.current"), systemImage: "sun.max")
                    Spacer()
                    Text(tr(!model.settings.enabled ? "schedule.off" : model.scheduledPeriod == .day ? "schedule.day" : model.scheduledPeriod == .night ? "schedule.night" : "schedule.manual"))
                    Text(percent(model.settings.enabled ? model.effectiveBrightness : 0)).monospacedDigit()
                }.font(.callout).accessibilityIdentifier("schedule.current")
                if model.settings.brightnessSchedule.enabled && !model.settings.brightnessSchedule.isActive {
                    Label(tr("schedule.invalid"), systemImage: "exclamationmark.triangle").font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            card("schedule.day", icon: "sun.max") {
                scheduleTime("schedule.dayStart", minutes: $model.settings.brightnessSchedule.dayStart)
                Text(timeLabel(model.settings.brightnessSchedule.dayStart) + " — " + timeLabel(model.settings.brightnessSchedule.nightStart)).font(.caption).foregroundStyle(.secondary)
                settingSlider("schedule.dayBrightness", value: $model.settings.brightnessSchedule.dayBrightness, range: 0...1, format: percent)
            }
            card("schedule.night", icon: "moon") {
                scheduleTime("schedule.nightStart", minutes: $model.settings.brightnessSchedule.nightStart)
                Text(timeLabel(model.settings.brightnessSchedule.nightStart) + " — " + timeLabel(model.settings.brightnessSchedule.dayStart)).font(.caption).foregroundStyle(.secondary)
                settingSlider("schedule.nightBrightness", value: $model.settings.brightnessSchedule.nightBrightness, range: 0...1, format: percent)
            }
            Text(tr("schedule.profiles")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func timeLabel(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func scheduleTime(_ key: String, minutes: Binding<Int>) -> some View {
        // A fixed UTC reference encodes only clock fields, avoiding DST gaps in the picker.
        let zone = TimeZone(secondsFromGMT: 0)!
        let binding = Binding<Date>(get: { Date(timeIntervalSinceReferenceDate: Double(minutes.wrappedValue * 60)) }, set: { date in
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
        return DatePicker(tr(key), selection: binding, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, zone).environment(\.locale, Locale(identifier: "ru_RU"))
            .accessibilityIdentifier(key)
    }
    private var earlyResponseControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(tr("control.earlyResponse"), isOn: $model.settings.earlyResponse)
                .accessibilityIdentifier("control.earlyResponse")
            Text(tr("help.earlyResponse")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capturePage: some View {
        VStack(spacing: 20) {
            card("capture.area", icon: "viewfinder") {
                Picker(tr("capture.display"), selection: $model.settings.displayID) { ForEach(model.displays) { Text($0.name).tag($0.id) } }.pickerStyle(.menu)
                Toggle(tr("control.detailMode"), isOn: $model.settings.detailMode).accessibilityIdentifier("control.detailMode")
                Text(tr("help.detailMode")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                settingSlider("control.depth", value: $model.settings.edgeDepth, range: 0...0.35, format: percent, help: "help.depth")
                DepthPreview(depth: model.settings.edgeDepth)
                earlyResponseControl
                settingSlider("control.release", value: $model.settings.releaseSeconds, range: 0...1, step: 0.001, format: milliseconds, help: "help.release")
                settingSlider("control.attack", value: $model.settings.attackSeconds, range: 0...1, step: 0.001, format: milliseconds, help: "help.attack")
            }
            card("capture.layout", icon: "rectangle.3.group") {
                Toggle(tr("control.mirror"), isOn: $model.settings.mirrored)
                HStack { Text(tr("control.offset")); Spacer(); Stepper(value: $model.settings.offset, in: -111...111) { Text(String(model.settings.offset)).monospacedDigit().frame(width: 40) } }
                Divider().padding(.vertical, 4)
                sideRow("side.top", enabled: $model.settings.topEnabled, gain: $model.settings.topGain)
                sideRow("side.left", enabled: $model.settings.leftEnabled, gain: $model.settings.leftGain)
                sideRow("side.right", enabled: $model.settings.rightEnabled, gain: $model.settings.rightGain)
                sideRow("side.bottom", enabled: $model.settings.bottomEnabled, gain: $model.settings.bottomGain)
            }
            card("capture.performance", icon: "speedometer") {
                settingSlider("control.fps", value: $model.settings.fps, range: 5...33.68, step: 1, format: { String(format: $0 == 33.68 ? "%.2f FPS" : "%.0f FPS", $0) }, help: "help.fps")
                Picker(tr("control.captureRate"), selection: $model.settings.captureFps) { ForEach([30,60,90,120,144,240], id: \.self) { Text("\($0) Hz").tag($0) } }
                Toggle(tr("control.dedup"), isOn: $model.settings.skipUnchanged)
                settingSlider("control.heartbeat", value: $model.settings.keepaliveSeconds, range: 0.05...1, step: 0.001, format: milliseconds)
                Text(tr("help.performance")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var effectsPage: some View {
        VStack(spacing: 20) {
            card("mode.title", icon: "sparkles") { modeGrid }
            card("effects.settings.\(model.settings.mode)", icon: modeIcons[model.settings.mode]) {
                effectControls
                Text(tr("effects.savedSeparately")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var effectControls: some View {
        switch model.settings.mode {
        case 0:
            Toggle(tr("control.detailMode"), isOn: $model.settings.detailMode)
            Text(tr("help.detailMode")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            settingSlider("control.depth", value: $model.settings.edgeDepth, range: 0...0.35, format: percent, help: "help.depth")
            DepthPreview(depth: model.settings.edgeDepth)
            earlyResponseControl
        case 1:
            effectColors(secondary: false)
        case 2:
            effectColors(secondary: true)
            settingSlider("effects.gradientBalance", value: $model.settings.effect.gradientBalance, range: 0.1...0.9, format: percent, help: "help.gradientBalance")
        case 3:
            effectColors(secondary: false)
            effectSpeed
            settingSlider("effects.breathingFloor", value: $model.settings.effect.breathingFloor, range: 0...0.8, format: percent, help: "help.breathingFloor")
        case 4:
            effectSpeed
            settingSlider("effects.rainbowCycles", value: $model.settings.effect.rainbowCycles, range: 0.5...3, step: 0.1, format: multiplier, help: "help.rainbowCycles")
            effectDirection
        case 5:
            effectSpeed
            settingSlider("effects.candleFlicker", value: $model.settings.effect.candleFlicker, range: 0...1, format: percent, help: "help.candleFlicker")
        case 6:
            effectSpeed
            settingSlider("effects.flameHeight", value: $model.settings.effect.flameHeight, range: 0.3...2, format: percent, help: "help.flameHeight")
        case 7:
            effectColors(secondary: true)
            effectSpeed
            settingSlider("effects.cometTail", value: $model.settings.effect.cometTail, range: 0.3...2, format: percent, help: "help.cometTail")
            effectDirection
        default:
            effectSpeed
            settingSlider("effects.auroraPink", value: $model.settings.effect.auroraPink, range: 0...2, format: percent, help: "help.auroraPink")
            effectDirection
        }
    }
    private var effectSpeed: some View {
        settingSlider("control.speed", value: $model.settings.effect.speed, range: 0.1...5, step: 0.1, format: multiplier)
    }
    private var effectDirection: some View {
        Toggle(tr("control.reverse"), isOn: $model.settings.effect.reverse).accessibilityIdentifier("control.reverse")
    }
    private func multiplier(_ value: Double) -> String { String(format: "%.1f×", value) }
    @ViewBuilder private func effectColors(secondary: Bool) -> some View {
        ColorPicker(tr("effects.primary"), selection: effectColorBinding(\.primary), supportsOpacity: false)
        if secondary {
            ColorPicker(tr("effects.secondary"), selection: effectColorBinding(\.secondary), supportsOpacity: false)
        }
        HStack(spacing: 12) {
            ForEach(Array([RGB.amber, RGB(red: 1, green: 0.3, blue: 0.15), RGB.blue, RGB(red: 0.2, green: 1, blue: 0.65), RGB(red: 1, green: 0.9, blue: 0.7)].enumerated()), id: \.offset) { _, color in
                Button { model.settings.effect.primary = color } label: { Circle().fill(color.color).frame(width: 27, height: 27).overlay(Circle().stroke(.white.opacity(0.25))) }.buttonStyle(.plain).accessibilityLabel(tr("effects.swatch"))
            }
            Spacer()
        }.padding(.top, 6)
    }
    private var profilesPage: some View {
        VStack(spacing: 20) {
            card("profile.create", icon: "plus.circle") {
                HStack { TextField(tr("profile.placeholder"), text: $model.profileName).textFieldStyle(.roundedBorder).onSubmit { model.saveProfile() }; Button(tr("profile.save")) { model.saveProfile() }.buttonStyle(.borderedProminent).disabled(model.profileName.trimmingCharacters(in: .whitespaces).isEmpty) }
                Text(tr("profile.help")).font(.caption).foregroundStyle(.secondary)
            }
            card("profile.library", icon: "square.stack.3d.up") {
                if model.profiles.isEmpty { ContentUnavailableView(tr("profile.empty"), systemImage: "square.stack.3d.up", description: Text(tr("profile.emptyHelp"))).frame(height: 170) }
                ForEach(model.profiles) { profile in
                    HStack {
                        Image(systemName: modeIcons[profile.settings.mode]).foregroundStyle(amber).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) { Text(profile.name).font(.headline); Text(tr("mode.\(profile.settings.mode)") + " · " + percent(profile.settings.brightness)).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if model.selectedProfile == profile.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(amber) }
                        Button(tr("profile.apply")) { model.activate(profile) }
                        Button { model.deleteProfile(profile.id) } label: { Image(systemName: "trash") }.help(tr("profile.delete"))
                    }.padding(.vertical, 8)
                }
            }
            card("profile.backup", icon: "externaldrive") {
                HStack { Button(tr("profile.export")) { model.exportSettings() }; Button(tr("profile.import")) { model.importSettings() }; Spacer() }
                Text(tr("profile.backupHelp")).font(.caption).foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                Button(tr("settings.reset")) { model.confirmReset = true }
                Text(tr("reset.help")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var appPage: some View {
        VStack(spacing: 20) {
            card("ambient.title", icon: "moon.stars") {
                Text(tr("ambient.description")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: openAmbient) { Label(tr("ambient.open"), systemImage: "play.fill") }
                    .accessibilityIdentifier("ambient.open")
                Text(tr("ambient.stripHelp")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("app.startup", icon: "power") {
                Toggle(tr("control.login"), isOn: $model.settings.launchAtLogin)
                Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
                Toggle(tr("control.hidden"), isOn: $model.settings.startHidden)
                Toggle(tr("control.reconnect"), isOn: $model.settings.reconnect)
                Toggle(tr("control.offQuit"), isOn: $model.settings.offOnQuit)
                Button(tr("login.settings")) { model.openLoginSettings() }
            }
            card("app.appearance", icon: "circle.lefthalf.filled") {
                Picker(tr("control.theme"), selection: $model.settings.theme) { Text(tr("theme.system")).tag("system"); Text(tr("theme.dark")).tag("dark"); Text(tr("theme.light")).tag("light") }.pickerStyle(.segmented)
                Text(tr("app.closeHelp")).font(.caption).foregroundStyle(.secondary)
            }
            card("app.device", icon: "cable.connector") {
                Picker(tr("device.port"), selection: $model.settings.port) {
                    ForEach(Array(Set(model.ports + [model.settings.port, ""])).sorted(), id: \.self) { Text($0.isEmpty ? tr("device.selectPort") : $0).tag($0) }
                }
                HStack { Button(tr("device.refresh")) { model.refreshDevices() }; Button(tr("device.retry")) { model.restartEngine() }; Spacer(); Text("115200 baud · SK0L34").font(.caption.monospaced()).foregroundStyle(.secondary) }
                Text(tr("device.identityHelp")).font(.caption).foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                HStack { Text(tr("permission.title")); Spacer(); Image(systemName: model.permission ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(model.permission ? .green : amber); Text(tr(model.permission ? "permission.granted" : "permission.required")).font(.caption) }
                if !model.permission { Button(tr("permission.allow")) { model.requestPermission() } }
            }
            card("app.diagnostics", icon: "waveform.path.ecg") {
                if let s = model.status, model.isConnected {
                    LabeledContent(tr("stat.fps"), value: String(format: "%.2f", s.fps))
                    LabeledContent(tr("stat.write"), value: String(format: "%.1f ms", s.writeMs))
                    LabeledContent(tr("stat.frames"), value: String(s.framesSent))
                    LabeledContent(tr("stat.capture"), value: "\(s.captureAccepted) / \(s.captureReceived)")
                }
                HStack { Button(tr("diagnostics.logs")) { model.openLogs() }; Button(tr("diagnostics.files")) { model.openDataFolder() }; Spacer(); Text("Glowline " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")).font(.caption).foregroundStyle(.secondary) }
                Text(tr("diagnostics.privacy")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var modeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Settings.supportedModes, id: \.self) { mode in
                Button { model.settings.mode = mode } label: {
                    HStack(spacing: 12) {
                        Image(systemName: modeIcons[mode]).font(.system(size: 20)).frame(width: 25).foregroundStyle(model.settings.mode == mode ? amber : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) { Text(tr("mode.\(mode)")).font(.system(size: 12, weight: .semibold)); Text(tr("mode.help.\(mode)")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                        Spacer(minLength: 0)
                    }.padding(13).frame(maxWidth: .infinity, minHeight: 65).background(model.settings.mode == mode ? amber.opacity(0.1) : .primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(model.settings.mode == mode ? amber.opacity(0.5) : .primary.opacity(0.07)))
                }.buttonStyle(.plain).accessibilityIdentifier("mode.\(mode)")
            }
        }
    }
    private func card<Content: View>(_ key: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr(key), systemImage: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary.opacity(0.9))
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(scheme == .dark ? 0.035 : 0.025), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.065)))
    }
    private func settingSlider(_ key: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01, format: (Double) -> String, help: String? = nil) -> some View {
        let scale = SliderScale(range: range, step: step)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text(tr(key)).font(.system(size: 12, weight: .medium)); Spacer(); Text(format(value.wrappedValue)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(minWidth: 65, alignment: .trailing) }
            steppedSlider(value, scale: scale).disabled(key == "control.brightness" && model.settings.brightnessSchedule.isActive).accessibilityLabel(tr(key)).accessibilityValue(format(value.wrappedValue)).accessibilityIdentifier(key)
            if key == "control.brightness" && model.settings.brightnessSchedule.isActive { Text(tr("schedule.manualHint")).font(.caption).foregroundStyle(.secondary) }
            if let help { Text(tr(help)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func steppedSlider(_ value: Binding<Double>, scale: SliderScale) -> some View {
        Slider(value: Binding(get: { scale.index(for: value.wrappedValue) },
                              set: { value.wrappedValue = scale.value(at: $0) }),
               in: 0...scale.lastIndex, step: 1)
    }
    private func sideRow(_ key: String, enabled: Binding<Bool>, gain: Binding<Double>) -> some View {
        HStack(spacing: 16) { Toggle(tr(key), isOn: enabled).toggleStyle(.switch).frame(width: 155, alignment: .leading); steppedSlider(gain, scale: SliderScale(range: 0...2, step: 0.01)).disabled(!enabled.wrappedValue).accessibilityLabel(tr(key) + " " + tr("control.brightness")); Text(percent(gain.wrappedValue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44) }
    }
    private func effectColorBinding(_ path: WritableKeyPath<EffectSettings, RGB>) -> Binding<Color> { Binding(get: { model.settings.effect[keyPath: path].color }, set: { model.settings.effect[keyPath: path] = RGB(color: $0) }) }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private func milliseconds(_ value: Double) -> String { String(format: "%.0f ms", value * 1000) }
    private func stat(_ key: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).font(.title3).foregroundStyle(amber); VStack(alignment: .leading, spacing: 4) { Text(tr(key)).font(.caption2).foregroundStyle(.secondary); Text(value).font(.system(size: 14, weight: .semibold)) }; Spacer(minLength: 0) }.padding(16).frame(maxWidth: .infinity).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func swatch(r: Double, g: Double, b: Double) -> some View { RoundedRectangle(cornerRadius: 6).fill(Color(red: r/255, green: g/255, blue: b/255)).frame(width: 42, height: 25).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1))) }
}


/// Use primary text in light mode, including inherited native button labels.
private struct AppearanceButtonLabels: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder func body(content: Content) -> some View {
        if scheme == .light { content.foregroundStyle(Color.primary) }
        else { content }
    }
}

struct MonitorPreview: View {
    var colors: [[Int]]
    var enabled: Bool
    private func color(_ index: Int) -> Color {
        guard enabled else { return .black }
        guard colors.indices.contains(index), colors[index].count == 3 else { return .gray.opacity(0.2) }
        let c = colors[index]; return Color(red: Double(c[0])/255, green: Double(c[1])/255, blue: Double(c[2])/255)
    }
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [color(35).opacity(0.3), color(91).opacity(0.12)], startPoint: .top, endPoint: .bottom)).blur(radius: 30).padding(-12)
                VStack(spacing: 8) {
                    HStack(spacing: 2) { ForEach(15..<56, id: \.self) { i in Capsule().fill(color(i)).frame(height: 4) } }
                    HStack(spacing: 10) {
                        VStack(spacing: 2) { ForEach((0..<15).reversed(), id: \.self) { i in Capsule().fill(color(i)).frame(width: 4) } }
                        VStack(spacing: 10) { Image(systemName: "display").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.white.opacity(0.65)); Text("Glowline").font(.system(size: 23, weight: .light, design: .rounded)).foregroundStyle(.white); Text(tr("preview.live")).font(.caption).foregroundStyle(.white.opacity(0.4)) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.04, green: 0.045, blue: 0.055), in: RoundedRectangle(cornerRadius: 8))
                        VStack(spacing: 2) { ForEach(56..<71, id: \.self) { i in Capsule().fill(color(i)).frame(width: 4) } }
                    }
                    HStack(spacing: 2) { ForEach((71..<112).reversed(), id: \.self) { i in Capsule().fill(color(i)).frame(height: 4) } }
                }.padding(12).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
            }.frame(width: 470, height: 195).padding(.top, 8)
            Text(tr("preview.caption")).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
    }
}
struct DepthPreview: View {
    var depth: Double
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.15))
                Rectangle().fill(LinearGradient(colors: [amber.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)).frame(height: geo.size.height * depth).frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(LinearGradient(colors: [amber.opacity(0.5), .clear], startPoint: .bottom, endPoint: .top)).frame(height: geo.size.height * depth).frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(LinearGradient(colors: [amber.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * depth).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(LinearGradient(colors: [amber.opacity(0.5), .clear], startPoint: .trailing, endPoint: .leading)).frame(width: geo.size.width * depth).frame(maxWidth: .infinity, alignment: .trailing)
                Text(tr("capture.preview")).font(.caption2).foregroundStyle(.secondary)
            }.clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(amber.opacity(0.2)))
        }.frame(height: 95)
    }
}
