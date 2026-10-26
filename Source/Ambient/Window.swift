import AppKit
import MetalKit
import IOKit.pwr_mgt

enum AmbientScene: String, CaseIterable {
    case starfall

    var title: String { tr("ambient.scene.starfall") }

    /// Unknown and legacy numeric scene IDs select the retained scene without restoring removed effects.
    init(savedID: String?) {
        self = Self(rawValue: savedID ?? "") ?? .starfall
    }
}

enum NoctilucaStrings {
    static let title = tr("ambient.window.title")
    static let palettes = [tr("ambient.palette.0"), tr("ambient.palette.1"), tr("ambient.palette.2")]
    static let help = tr("ambient.keys")
}

final class LightView: MTKView {
    var keyAction: ((String) -> Void)?
    var activity: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { keyAction?(event.charactersIgnoringModifiers?.lowercased() ?? "") }
    override func mouseMoved(with event: NSEvent) { activity?() }
    override func mouseDown(with event: NSEvent) {
        activity?()
        if event.clickCount == 2 { window?.toggleFullScreen(nil) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved,.activeAlways,.inVisibleRect], owner: self))
    }
}

/// In-process ambient window owned by Glowline; closing it never terminates the host application.
@MainActor final class AmbientWindowController: NSObject, MTKViewDelegate, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var window: NSWindow?
    private var view: LightView!
    private var renderer: MetalRenderer!
    private var universe = Universe()
    private let defaults = UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "Glowline") + ".ambient")!
    private var overlay = NSView()
    private let status = NSTextField(labelWithString: "METAL · GPU")
    private var panel: NSPanel?
    private var brightness: Float = 1
    private var speed: Float = 0.7
    private var palette = 0
    private var scene = AmbientScene.starfall
    private var fill = true
    private var darkness = true
    private var paused = false
    private var last: Double = 0
    private var lastActivity = CACurrentMediaTime()
    private var sampleStart = CACurrentMediaTime()
    private var frames = 0
    private var intervals: [Double] = []
    private var cycleStart = CACurrentMediaTime()
    private var blackSince: Double?
    private var deadline: Double?
    private var timerMinutes = 0
    private var nightSnapshot: (Float, Float, Int)?
    private var displayAssertion: IOPMAssertionID = 0
    private var hasAssertion = false
    private var needsReset = true

    func show(fullscreen: Bool = true) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        do {
            guard let shader = Bundle.main.url(forResource: "Noctiluca", withExtension: "metal") else { throw RenderFailure.unavailable("Missing bundled Noctiluca.metal") }
            renderer = try MetalRenderer(shaderURL: shader)
            load()
            let screen = NSScreen.main
            let rect = NSRect(x: 0,y: 0,width: 1280,height: 600)
            let window = NSWindow(contentRect: rect,styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
            self.window = window
            window.isReleasedWhenClosed = false
            window.title = NoctilucaStrings.title; window.backgroundColor = .black; window.delegate = self
            window.collectionBehavior = [.fullScreenPrimary]
            window.acceptsMouseMovedEvents = true
            view = LightView(frame: rect,device: renderer.device)
            view.colorPixelFormat = .bgra8Unorm
            view.clearColor = MTLClearColorMake(0,0,0,1)
            view.framebufferOnly = true; view.autoResizeDrawable = false
            let refresh = screen?.maximumFramesPerSecond ?? 60
            // An even display divisor leaves a predictable GPU budget for rare large events.
            view.preferredFramesPerSecond = refresh >= 120 ? refresh/2 : 60
            view.delegate = self
            view.keyAction = { [weak self] in self?.key($0) }
            view.activity = { [weak self] in self?.showControls() }
            window.contentView = view
            makeOverlay()
            window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
            if fullscreen { window.toggleFullScreen(nil) }
            setAwake(true)
        } catch { fatalUI(error) }
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        view.isPaused = true; view.delegate = nil
        view.keyAction = nil; view.activity = nil
        panel?.close(); panel = nil
        setAwake(false)
        window = nil; view = nil; renderer = nil
        onClose?()
    }
    func windowDidResize(_ notification: Notification) { if view != nil { layoutOverlay() } }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let realDelta = last == 0 ? 1/60 : now - last
        last = now
        // Render at physical monitor dimensions, not a hidden Retina 2x supersample.
        let size = CGSize(width: max(1,view.bounds.width),height: max(1,view.bounds.height))
        if view.drawableSize != size { view.drawableSize = size }
        guard let window, window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible), let drawable = view.currentDrawable else { return }
        let dt = paused || (deadline.map { now >= $0 } ?? false) ? 0 : min(0.05,realDelta) * Double(speed)
        let drain = darkness && now-cycleStart >= 240
        let frame = universe.advance(delta: dt,aspect: Float(size.width/size.height),palette: palette,births: !drain)
        var envelope: Float = 1
        if let deadline { envelope = Float(clamp((deadline-now)/20,0,1)) }
        if drain && universe.stars.isEmpty {
            if blackSince == nil { blackSince = now }
            envelope = 0
            if now - blackSince! >= (darkness ? 3 : 0) {
                universe = Universe(); cycleStart = now; blackSince = nil
            }
        }
        do {
            try renderer.render(frame: frame,time: Float(universe.time),delta: Float(dt),brightness: brightness,
                                fade: envelope,fill: fill,output: drawable.texture,drawable: drawable,reset: needsReset)
            needsReset = false
        } catch { view.isPaused = true; fatalUI(error); return }
        frames += 1
        if realDelta > 0 && realDelta < 0.5 { intervals.append(realDelta) }
        if now-sampleStart >= 1 {
            let fps = Double(frames)/(now-sampleStart)
            let gpu = renderer.metrics.snapshot()
            if gpu.errors > 0 { view.isPaused = true; fatalUI(RenderFailure.unavailable("Metal command execution failed")); return }
            status.stringValue = String(format: "METAL · %.0f FPS · GPU %.1f ms",fps,gpu.p95)
            if intervals.count > 1200 { intervals.removeFirst(intervals.count-1200) }
            let sorted = intervals.sorted()
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]*1000
            let record: [String: Any] = ["fps":fps,"frameP95ms":p95,"gpuMedianMs":gpu.median,"gpuP95ms":gpu.p95,"gpuMaxMs":gpu.max,"gpuErrors":gpu.errors,"width":drawable.texture.width,"height":drawable.texture.height,"stars":universe.stars.count,"gpu":renderer.device.name]
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted,.sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("noctiluca-metal-live.json"),options: .atomic)
            }
            frames = 0; sampleStart = now
        }
        overlay.isHidden = now-lastActivity > 5 && panel?.isVisible != true
        if overlay.isHidden { NSCursor.setHiddenUntilMouseMoves(true) }
        if deadline.map({ now >= $0 }) == true { setAwake(false); view.isPaused = true }
    }

    private func makeOverlay() {
        overlay = NSView(frame: view.bounds); overlay.autoresizingMask = [.width,.height]
        let title = NSTextField(labelWithString: "N O C T I L U C A")
        title.font = .systemFont(ofSize: 13,weight: .medium); title.textColor = .white
        title.frame = NSRect(x: 30,y: view.bounds.height-50,width: 300,height: 22)
        title.autoresizingMask = [.minYMargin]
        overlay.addSubview(title)
        status.font = .monospacedDigitSystemFont(ofSize: 11,weight: .regular); status.textColor = .lightGray
        status.alignment = .right; status.frame = NSRect(x: view.bounds.width-410,y: view.bounds.height-50,width: 380,height: 22)
        status.autoresizingMask = [.minXMargin,.minYMargin]; overlay.addSubview(status)
        let help = NSTextField(labelWithString: NoctilucaStrings.help)
        help.font = .systemFont(ofSize: 11); help.textColor = .lightGray
        help.frame = NSRect(x: 30,y: 26,width: 950,height: 20); overlay.addSubview(help)
        let settings = NSButton(title: tr("ambient.settings"),target: self,action: #selector(showSettings))
        settings.frame = NSRect(x: view.bounds.width-160,y: 22,width: 130,height: 32)
        settings.autoresizingMask = [.minXMargin]; overlay.addSubview(settings)
        view.addSubview(overlay)
    }
    private func layoutOverlay() { overlay.frame = view.bounds }
    private func showControls() { lastActivity = CACurrentMediaTime(); overlay.isHidden = false }

    private func key(_ key: String) {
        showControls()
        switch key {
        case "f", "а": window?.toggleFullScreen(nil)
        case " ": togglePause()
        case "s", "ы": showSettings()
        case "n", "т": night()
        case "h", "р": lastActivity = 0; panel?.orderOut(nil)
        case "\u{1b}": if panel?.isVisible == true { panel?.orderOut(nil) } else { close() }
        default: break
        }
    }

    @objc private func showSettings() {
        showControls()
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        let p = NSPanel(contentRect: NSRect(x: 0,y: 0,width: 390,height: 650),styleMask: [.titled,.closable,.utilityWindow],backing: .buffered,defer: false)
        p.title = tr("ambient.settings.title"); p.isFloatingPanel = true; p.collectionBehavior = [.fullScreenAuxiliary]
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        p.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: p.contentView!.leadingAnchor,constant: 24),stack.trailingAnchor.constraint(equalTo: p.contentView!.trailingAnchor,constant: -24),stack.topAnchor.constraint(equalTo: p.contentView!.topAnchor,constant: 24)])
        func label(_ title: String) { stack.addArrangedSubview(NSTextField(labelWithString: title)) }
        func menu(_ items: [String], selected: Int, tag: Int) {
            let popup = NSPopUpButton(); popup.addItems(withTitles: items); popup.selectItem(at: selected)
            popup.tag = tag; popup.target = self; popup.action = #selector(changeMenu(_:)); stack.addArrangedSubview(popup)
        }
        label(tr("ambient.brightness"))
        let light = NSSlider(value: Double(brightness*100),minValue: 3,maxValue: 100,target: self,action: #selector(slide(_:)))
        light.tag = 0; light.widthAnchor.constraint(equalToConstant: 330).isActive = true; stack.addArrangedSubview(light)
        label(tr("ambient.speed"))
        let rate = NSSlider(value: Double(speed),minValue: 0.2,maxValue: 1.3,target: self,action: #selector(slide(_:)))
        rate.tag = 1; rate.widthAnchor.constraint(equalToConstant: 330).isActive = true; stack.addArrangedSubview(rate)
        menu(AmbientScene.allCases.map(\.title),selected: AmbientScene.allCases.firstIndex(of: scene) ?? 0,tag: 0)
        menu(NoctilucaStrings.palettes,selected: palette,tag: 1)
        menu([tr("ambient.timer.off"),tr("ambient.timer.30"),tr("ambient.timer.60"),tr("ambient.timer.120")],selected: [0,30,60,120].firstIndex(of: timerMinutes) ?? 0,tag: 2)
        for (title,on,tag) in [(tr("ambient.darkness"),darkness,0),(tr("ambient.fill"),fill,1)] {
            let box = NSButton(checkboxWithTitle: title,target: self,action: #selector(check(_:)))
            box.state = on ? .on : .off; box.tag = tag; stack.addArrangedSubview(box)
        }
        stack.addArrangedSubview(NSButton(title: tr("ambient.night"),target: self,action: #selector(night)))
        let asleep = deadline.map { CACurrentMediaTime() >= $0 } ?? false
        stack.addArrangedSubview(NSButton(title: paused || asleep ? tr("ambient.resume") : tr("ambient.pause"),target: self,action: #selector(pause)))
        stack.addArrangedSubview(NSButton(title: tr("ambient.fullscreen"),target: self,action: #selector(fullscreen)))
        stack.addArrangedSubview(NSButton(title: tr("ambient.giant"),target: self,action: #selector(previewGiant)))
        p.center(); p.makeKeyAndOrderFront(nil); panel = p
    }
    @objc private func slide(_ sender: NSSlider) {
        if sender.tag == 0 { brightness = sender.floatValue/100 } else { speed = sender.floatValue }
        nightSnapshot = nil; save()
    }
    @objc private func changeMenu(_ sender: NSPopUpButton) {
        switch sender.tag {
        case 0: scene = AmbientScene.allCases[sender.indexOfSelectedItem]
        case 1: palette = sender.indexOfSelectedItem; nightSnapshot = nil
        default:
            let minutes = [0,30,60,120][sender.indexOfSelectedItem]
            timerMinutes = minutes
            deadline = minutes == 0 ? nil : CACurrentMediaTime()+Double(minutes*60)
            view.isPaused = false; paused = false; last = 0
            setAwake(true)
        }
        save()
    }
    @objc private func check(_ sender: NSButton) {
        if sender.tag == 0 { darkness = sender.state == .on; cycleStart = CACurrentMediaTime(); blackSince = nil }
        else { fill = sender.state == .on }
        save()
    }
    @objc private func night() {
        if let previous = nightSnapshot { brightness = previous.0; speed = previous.1; palette = previous.2; nightSnapshot = nil }
        else { nightSnapshot = (brightness,speed,palette); brightness = 0.18; speed = 0.35; palette = 2 }
        save(); panel?.orderOut(nil)
    }
    private func togglePause() {
        if deadline.map({ CACurrentMediaTime() >= $0 }) == true {
            deadline = nil; timerMinutes = 0; paused = false; view.isPaused = false; setAwake(true); last = 0
        } else { paused.toggle() }
    }
    @objc private func pause() { togglePause(); panel?.orderOut(nil) }
    @objc private func fullscreen() { panel?.orderOut(nil); window?.toggleFullScreen(nil) }
    @objc private func previewGiant() {
        universe = Universe(seed: 1); universe.stageGiant(includeDescent: true); scene = .starfall; needsReset = true
        paused = false; deadline = nil; timerMinutes = 0; cycleStart = CACurrentMediaTime(); blackSince = nil
        view.isPaused = false; setAwake(true); panel?.orderOut(nil)
        intervals.removeAll(); last = 0
    }
    private func load() {
        if defaults.object(forKey: "brightness") != nil { brightness = clamp(defaults.float(forKey: "brightness"),0.03,1) }
        if defaults.object(forKey: "speed") != nil { speed = clamp(defaults.float(forKey: "speed"),0.2,1.3) }
        palette = clamp(defaults.integer(forKey: "palette"),0,2)
        // Removed experimental scene IDs and automatic cycling restore to the retained scene.
        scene = AmbientScene(savedID: defaults.string(forKey: "scene"))
        if defaults.object(forKey: "fill") != nil { fill = defaults.bool(forKey: "fill") }
        if defaults.object(forKey: "darkness") != nil { darkness = defaults.bool(forKey: "darkness") }
    }
    private func save() {
        defaults.removeObject(forKey: "journey")
        for (key,value) in ["brightness":brightness,"speed":speed,"palette":palette,"scene":scene.rawValue,"fill":fill,"darkness":darkness] as [String: Any] { defaults.set(value,forKey: key) }
    }
    private func setAwake(_ awake: Bool) {
        if awake && !hasAssertion {
            hasAssertion = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,IOPMAssertionLevel(kIOPMAssertionLevelOn),"Noctiluca ambient playback" as CFString,&displayAssertion) == kIOReturnSuccess
        } else if !awake && hasAssertion { IOPMAssertionRelease(displayAssertion); hasAssertion = false }
    }
    private func fatalUI(_ error: Error) {
        let alert = NSAlert(); alert.messageText = tr("ambient.error")
        alert.informativeText = String(describing: error); alert.runModal()
        if window != nil { close() } else { onClose?() }
    }
}
