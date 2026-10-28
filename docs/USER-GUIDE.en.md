# Glowline — macOS Ambient Lighting for Skydimo SK0L34

Glowline is a native macOS menu-bar app that syncs a **Skydimo SK0L34 USB monitor backlight with 112 LEDs** to the edges of your screen. It provides nine lighting modes, adjustable warm bias lighting, per-side color correction and local profiles in a SwiftUI interface.

[Download for Apple Silicon](https://github.com/hardcodd/Glowline/releases/latest) · [Русское руководство](../РУКОВОДСТВО.md) · [Installation and updates](INSTALL.md) · [Report an issue](https://github.com/hardcodd/Glowline/issues)

This guide describes Glowline 1.2.0, including Fire, Comet, Aurora, per-effect controls and the built-in Metal night light.

![Glowline macOS app showing screen-synced Skydimo SK0L34 112-LED ambient lighting, brightness and warmth controls](images/glowline-macos-ambient-lighting.png)

*Actual running application; Russian interface. The monitor outline previews transmitted colors, not measured light output. The current interface includes Schedule and nine lighting modes.*

**Version 1.2.0, build 4:** Apple Silicon, macOS 15+. The download is ad-hoc signed, without a paid Developer ID certificate or Apple notarization. First launch may require a manual exception in macOS settings; see below.

[Compatible LED strip](#compatible-led-strip) · [Install and first launch](#install-and-first-launch) · [Lighting modes](#lighting-modes) · [Settings](#settings) · [Troubleshooting](#troubleshooting) · [Build from source](#build-from-source)

## Compatible LED strip

**Use a Skydimo SK0L34 controller with the fixed 112-LED monitor-strip layout.** A Skydimo product name, connector type or matching LED count alone does not establish compatibility.

| Requirement | Supported configuration |
| --- | --- |
| Computer | Apple Silicon Mac; Intel Macs are not supported |
| Operating system | macOS 15 or later; see verification limits below |
| LED controller and strip | Skydimo SK0L34, 112 LEDs, the existing fixed perimeter layout |
| USB protocol | Serial connection at 115200 baud; 342-byte RGB frames |
| Identity response | `Moni-A` query returns `SK0L34,` plus seven device-specific bytes, optionally followed by CR LF |
| Screen synchronization | Screen Recording permission in macOS |
| Interface | Russian |

There is **no lock to the author's serial number**. Compatible controllers may have different device-specific bytes. Glowline verifies the model response before sending colors, but the handshake does not report LED count or physical arrangement. You must check that your strip matches the 112-LED layout. Other lengths/models, generic RGB strips, Bluetooth/Wi-Fi controllers and Windows/Linux are not supported. Glowline does not flash firmware.

One physical SK0L34 setup has been tested. A second physical controller has not; protocol tests with different identities are not a hardware compatibility guarantee.

## Install and first launch

No Python, RTK, Xcode or paid Apple developer account is needed to run the packaged app.

1. Download the **arm64 ZIP or DMG** and `SHA256SUMS` from [GitHub Releases](https://github.com/hardcodd/Glowline/releases/latest). Choose either archive format; the application is the same.
2. Extract the ZIP or open the DMG. Copy `Glowline.app` to `~/Applications/` and launch it from that permanent location. Create the folder if needed.
3. If macOS blocks the app because the developer cannot be verified or Apple cannot check it, dismiss the warning. Open **System Settings → Privacy & Security**, find the Glowline message and click **Open Anyway**, then confirm **Open**. Only do this for the official download you trust. macOS normally remembers this exception for that copy. [Apple's instructions](https://support.apple.com/en-us/102445).
4. Quit Skydimo and any other app controlling the strip. Under **Приложение**, select your USB serial port. A fresh installation has no preselected port.
5. For **Экран** mode, grant Glowline **Screen Recording** permission in macOS Privacy & Security. Quit and reopen it if requested. The other eight modes work without screen access.
6. Check login-launch status under **Приложение**. Login launch and hidden startup are enabled by default; macOS may require approval in Login Items.

Do not disable Gatekeeper globally. A warning that the app is damaged or will harm your computer requires investigation; it is not the ordinary unidentified-developer prompt. A managed Mac may prohibit exceptions. Downloaded-package first launch on a clean Mac has not yet been verified.

Closing the settings window leaves the menu-bar app and lighting running. Reopen settings from the Glowline menu-bar icon; quit through that menu or **Command-Q**. The menu also offers the light switch, lighting modes and saved profiles.

For checksum verification, updates, permission recovery and removal, see the [installation guide](INSTALL.md).

## Lighting modes

| Mode in the app | Behavior |
| --- | --- |
| Экран — Screen | Samples screen edges and sends corresponding colors to the strip |
| Один цвет — Solid | One adjustable color across the strip |
| Градиент — Gradient | Two colors distributed around the strip |
| Дыхание — Breathing | Animated brightness changes |
| Радуга — Rainbow | Moving multicolor effect |
| Свеча — Candle | Warm animated glow |
| Пламя — Fire | Hot embers and animated tongues of flame |
| Комета — Comet | Moving light with a fading colored tail |
| Северное сияние — Aurora | Smooth overlapping waves of color |

The master light switch sends black without losing your settings. Effect colors, speed and direction are adjustable where applicable.

Comet uses both selected colors for its long fading tail, with a light core. Aurora uses its own emerald, teal, blue, violet and pink palette; Fire uses coal-to-yellow tones. Fire has its own vertical orientation without changing the screen-mode sampling map. Speed is adjustable for every animation; Reverse is available for Rainbow, Comet and Aurora. Profiles preserve the new modes; existing mode IDs are unchanged. Their appearance on physical LEDs needs separate assessment.

On the **Режимы и эффекты** page, the panel below the mode grid shows only controls for the selected effect:

| Mode | Dedicated controls |
| --- | --- |
| Screen | Color detail and capture depth; shared with the capture page |
| Solid | Color and preset swatches |
| Gradient | Two colors and transition midpoint |
| Breathing | Color, speed and minimum glow between pulses |
| Rainbow | Speed, direction and spectrum density |
| Candle | Speed and flicker strength |
| Fire | Speed and flame height |
| Comet | Two colors, speed, direction and tail length |
| Aurora | Speed, direction and pink contribution |

Each effect independently remembers its colors, speed, direction and artistic parameters across switching and relaunch. Profiles and JSON exports include all sets. Older settings and profiles use their previous colors and speed as initial values; opening them does not overwrite other modes. Brightness, schedule, color calibration, smoothing, layout and performance remain global. A saved profile is a snapshot: save it again after tuning.

## Built-in Noctiluca night light

In Glowline 1.2.0 for macOS, the night light is part of Glowline itself. Open **Приложение → Запустить ночник** or the matching Glowline menu item. No separate app, browser or Internet connection is required. The night light renders locally with Metal; no separate runtime is installed.

**In development:** the scene description below refers to the current review version; the installed 1.2.0 release may differ.

Automatic launch immediately fills the display: the macOS menu bar, Dock, cursor and night-light controls are hidden from the start. Closing the night light restores the normal desktop interface.

In **Приложение**, enable **Запускать ночник при бездействии** and choose 1, 3, 5, 10, 15, 30 or 60 minutes. Automatic launch is off by default, with a 5-minute delay selected. Glowline must remain running. A visible fullscreen or nearly maximized window of another app on any connected display blocks launch; hidden Spaces are not inspected. Moving the mouse or pressing a key closes an automatically opened night light without opening settings. System display sleep remains effective; waking starts a fresh wait. These preferences are separate from strip profiles and the night-light session timer. Manual launch and its keyboard controls retain their behavior.

Massive superheated asteroids fall with irregular rotating silhouettes, dark crust and large glowing fractures. Soft glow follows each visible silhouette and preserves its hue. Small rocky meteors are more common than massive hot arrivals. Asteroids can take opposing lateral diagonals of up to 50 degrees, approach the camera or recede into the distance, with total 3D inclination limited to 60 degrees. Only one large body and its remaining effects can be present at a time. Collisions destroy the smaller body while the larger one retains its motion. Smoke remains along the traveled path. Massive superheated asteroids turn into lava in their own color on ground impact; ordinary rocky bodies scatter angular incandescent fragments. Both impacts eject dust and sparks. Select **Экран** mode to make the strip follow the image; opening the night light does not change strip settings.

Asteroids and meteors fall at different distances over lunar regolith: nearby bodies appear larger and distant ones shrink near the horizon. Bodies grow when approaching the fixed camera and shrink when receding; impact locations stay inside the frame. Physical size and mass are independent of camera distance. Slow and distant arrivals have a minimum initial projected speed of 0.45 image heights per scene second; the massive superheated class uses 1.1, about 2.5 times its former floor. Ordinary arrivals are about 40% faster overall; forced edge lanes have been removed and all bodies use randomized straight 3D paths. Tail sparks decelerate behind their source without ballistic downward acceleration; breakup fragments retain gravity.

Bolides travel substantially faster than ordinary bodies, starting at 4.8 image heights per scene second. The first appears after 2–4 seconds, with later intervals varying roughly from 12 to 25 seconds according to activity and at most one present at a time. Impact produces an expanding hot flash, colored sparks, stronger terrain lighting, a wider crater and more cooling debris. Bolides are additional events; the size distribution above describes ordinary arrivals. Pause and the overall speed control apply to the entire event.

Soil erupts from an expanding ring on the struck surface: fine fast material leaves first and travels farther, while later coarser grains land near the crater. Fragment sizes remain small compared with the crater. Soil and dust follow ballistic arcs under the same gravity without air drag; dust deposits on contact rather than billowing like smoke. Dry soil reflects the impact and lava light without acquiring an incandescent glow. After excavation, unstable crater walls and rims collapse: material moves downhill with conserved volume until it reaches a stable slope of approximately 34°. Terrain physics uses a fixed 1/120 scene-second step; pause freezes the entire event. The ejecta model follows impact scaling relationships with scene-specific coefficients; it is not a calibrated reconstruction of a real impact.

Bolide explosions produce a broad colored fireball and an expanding shock front. The bright phase fades more slowly and reaches screen-edge capture zones. Strip response requires Screen mode and actual capture of the scene. Digital image-signal checks do not replace optical assessment of the installed strip.

An automatic **meteor shower** becomes eligible after 8–12 scene seconds; a short recovery after a major event can defer its start. Waves last 6–8 seconds and vary in the number of small fast meteors. Each wave shares a diagonal direction while varying in distance, flight lane, speed and color: wakes and flashes span a broad range of hues around a shared theme. Waves leave at least 24 seconds between them; the next gap depends on activity and chance. Major events slightly reduce arrival pressure for 1.5–3.5 seconds. Ordinary bodies and bolides continue appearing; individual shower members are skipped when capacity is full. Pause and scene speed apply to the schedule; entering a dark pause stops new arrivals from the current wave.

A massive asteroid or bolide hitting the ground causes a light whole-scene tremor. It decays within 0.85 scene seconds, with combined displacement capped at 0.4% of image height. Small bodies and air breakups do not trigger it. Trajectories and craters keep their world coordinates, controls stay still, and pausing freezes the tremor too.

Scene direction changes arrival density, directional preference and color theme at irregular intervals. Short calm passages and intense activity have no scripted order. Related hues combine with frequent contrasting accents: complementary colors and colors spaced a third of the way around the color wheel. Some flights oppose the prevailing direction; lanes and depths remain independent. Bodies already in flight retain their original color and trajectory. The selected palette remains in effect.

Tail shapes vary: superheated asteroids leave long plasma wakes with several streams; some smaller bodies leave a unified dusty wake with luminous filaments; others leave sparkling trains. Deposited material continues dispersing after impact.

Cool gray regolith occupies a narrow strip at the bottom of the frame and is almost invisible in the default darkness. Approaching bodies reveal the terrain with colored light; ejecta dust also responds to their illumination. Small existing craters and granular shading break up the initial terrain. On contact, a body raises a spreading dust plume; the contact core opens immediately and the excavation front expands outward with the ejecta curtain. Short local fractures reveal the bowl; the low broken rim rises during that expansion, followed by dry slope collapse and thin distant deposits. Irregular radial rays and scattered soil extend beyond the rim. Oblique impacts bias the persistent deposit pattern along the incoming trajectory. Later strikes modify the existing terrain. Craters persist until the night light closes, including window resizing and dark pauses; they are not saved to disk. Superheated asteroids turn into lava lakes inside their craters. Rocky meteors and bolides retain opaque tumbling fragments: they rebound, settle, cool and crumble into solid ash.

**Esc** closes the night light and returns to Glowline. **F** toggles fullscreen, **Space** pauses, **S** opens settings, **N** toggles the night preset and **H** hides controls. The scene selector currently contains **Starfall** (Звездопад); the experimental flowing-light scenes and automatic cycling have been removed. Settings include three palettes, 3–100% brightness, 0.2–1.3× speed, fill or 21:9 framing, rare black pauses and a 30/60/120-minute timer. The timer fades during its final 20 seconds, then stops rendering; Space resumes playback. Ambient preferences are separate from strip profiles. Closing releases GPU resources and display-sleep prevention without quitting Glowline.

A bolide shock wave is an expanding spherical shell in world space. The leading front compresses the image behind it, while the following rarefied layer stretches it in the opposite direction; a short irregular wake adds heat shimmer. The shell emits very little light of its own. Refraction respects opaque scene depth and preserves the colored flash hues. The front slows and fades over 1.6 scene seconds. As it crosses the surface, it strips loose soil and crests, lifts dust and grains and carries material farther from the crater. Ejected packets land and dry slopes settle; transported soil volume is conserved. Pause freezes the wave, ejecta and deposition.

On impact, a superheated asteroid rapidly becomes a lava lake in the fallen body’s color within its own crater, without scattering pieces of its body. Sparks, dust and ballistic soil ejecta remain. The color is captured at impact and survives palette changes. Molten material lights nearby dust and terrain in that same color; a dark crust grows from the shoreline toward the center, leaving hot cracks that gradually dim. Emission ends after eight scene seconds, while the crater and fused floor persist. Pause freezes cooling. Only superheated asteroids create lava lakes: rocky meteors, bolides and meteor-shower members do not. Dry rims collapse in short local avalanches without prolonged viscous flow.

Rendering uses Metal, bounded asteroid geometry, HDR compositing and a fixed GPU particle pool; smoke is reconstructed from half linear resolution. Displays at 120 Hz or above use half their refresh rate (72 FPS at 144 Hz); others target 60 FPS. Actual FPS and GPU timing appear in the window. These are targets, not universal hardware guarantees.

## Settings

| Page | Controls |
| --- | --- |
| Освещение | Live color-output preview, brightness, warmth and quick mode selection |
| Цвет и теплота | Brightness, warmth, saturation, gamma, RGB gains and black threshold |
| Расписание | Daily local-time periods with separate day/night brightness |
| Захват экрана | Display, weighted edge depth, fade-in/fade-out, mirror, LED offset, side enable/gain controls, capture rate and output pacing |
| Режимы и эффекты | Nine modes and a dedicated panel for the selected effect |
| Мои профили | Named profiles, JSON import/export and reset to defaults |
| Приложение | Built-in night-light launch, USB port, reconnect, launch at login, hidden startup, off-on-quit, appearance, permissions and log |

Appearance offers **Как в macOS** (follow macOS), **Тёмное** (dark) and **Светлое** (light). System mode follows macOS after either manual theme; the light theme pairs a bright amber accent with dark labels for readability.

Connection status keeps updating while a slider is dragged. Notices do not shift the scrollable settings; dismiss the connection banner with its close button.

Controls apply and save automatically, including across a complete quit and restart. Named profiles are separate snapshots: save again after adjustments to update one. Defaults are brightness **100%**, warmth **50%**, mirror enabled, edge depth **15%**, fade-out time constant **180 ms**, immediate fade-in, capture **120 Hz**, output limit **33.68 FPS** and static heartbeat **100 ms**. Warmth can be increased to **90%**; it is an artistic adjustment, not a calibrated Kelvin value.

Sliders use 1 percentage point for percentages, 1 ms for time, 0.01 for gamma, 0.1× for effect speed and 1 FPS, with the exact 33.68 FPS endpoint retained. Existing saved values and profiles remain unchanged until you move a control.

**Daily brightness:** the **Расписание** page provides two repeating local-time periods with editable start times and brightness in 1% steps. For example, 100% from 08:00 and 50% from 22:00; adjust times manually by season. Initially disabled, it works in all modes while Glowline runs, including hidden in the menu bar. It picks the current period after waking or clock/timezone changes. Disabling restores the saved manual brightness; equal start times use manual brightness with an explanation. Master off always wins. Current brightness is shown on the overview and schedule pages; manual brightness sliders are unavailable during an active schedule. Profiles and JSON exports include the schedule; older profiles disable it. Save your profile again after configuring it.

**Детализация цвета** on the capture page switches from the original linear-light average to a representative dominant hue within each LED zone. It is off by default, including in older profiles. It keeps the mean peak level and leaves saturation, warmth and zone boundaries unchanged; it does not increase the LED count. Balanced competing hues and mostly neutral scenes fall back toward the average. Hue changes can be more noticeable, and the result can shift the scene's color balance. At zero edge depth, both modes use the same center-point sample. Toggle it live on a paused scene to compare, or turn it off to restore the original method. Profiles include this choice when saved.

Capture rate and LED output rate are separate. The serial link limits throughput; 120 Hz capture does not mean 120 FPS on the strip. Unchanged-frame suppression reduces redundant writes. A prior moving-pattern test on one setup produced approximately 26.6 output FPS; this is not a guaranteed rate or a latency measurement.

After a capture error, old screen colors are cleared and the app reports the failure. With reconnect enabled and light on, recovery is limited to three restarts with backoff; ten healthy seconds reset the budget. If it still fails, check permissions and use **Переподключить**.

Download and open the offline [lighting test](lighting-test.html) in a browser. It fits any aspect ratio, including ultrawide. `F` toggles fullscreen, `H` hides controls, Space pauses and `1`–`6` select scenes.

**Ранняя реакция** (Early response) is an experimental switch on the capture page and the Screen effect panel. It adds a faint highlight signal from objects up to halfway into the image from each edge, fading toward the center. Tangential zone boundaries stay unchanged. Existing edge light is not dimmed and uniform fills are not boosted; mixed scenes may become brighter and shift a zone's hue. Black threshold and color correction still apply and may suppress faint signals. The depth diagram shows the primary capture area without this extra signal. At zero depth the experiment has no effect. It defaults to off, including in older profiles; it switches live and is included when saving a profile. It changes sampling rather than physical LED count or controller speed.

## Profiles, updates and privacy

Settings, profiles and bounded diagnostic files are stored locally in `~/Library/Application Support/Glowline/`, separately from the app. Screen images and audio are not saved or uploaded. Glowline has no account requirement or cloud service.

Export JSON from **Мои профили** before updating. Quit the app, replace it at the same location and keep the old copy until the update works. Existing settings and profiles are retained; missing older fields receive defaults. Invalid data or unsupported schemas are rejected, and unreadable startup settings are backed up. A signature change may require Screen Recording approval again.

Resetting lighting defaults preserves your selected USB port and named profiles. An imported profile may contain another Mac's port; select yours again. See [update and removal instructions](INSTALL.md).

## Troubleshooting

| Symptom | Action |
| --- | --- |
| macOS blocks first launch | Use the per-app **Open Anyway** steps above; do not turn off system protection |
| No screen colors | Grant Screen Recording to the installed copy, then reopen; after a signature change, remove only Glowline from the permission list and add the installed copy again if needed |
| Controller unavailable or busy | Quit other lighting apps, check USB and select the correct port |
| Identity rejected | Confirm SK0L34 protocol and 112-LED hardware; other models and malformed replies are rejected |
| Flicker through a USB hub | Check the strip's power and the hub's external power supply |
| Colors mapped to the wrong side | Check mirror, LED offset and per-side controls; a different physical layout is not automatically detected |
| App runs after window closes | This is menu-bar behavior; use Quit or Command-Q |
| Login launch needs approval | Check registration status and macOS Login Items |

Include macOS version, Mac architecture, controller model, LED count and reproduction steps in a [bug report](https://github.com/hardcodd/Glowline/issues). Review logs and exported profiles before posting; they can contain local paths or your USB-port identifier.

## Build from source

Requires Apple Silicon, Apple Command Line Tools, Python 3 and [RTK](https://github.com/rtk-ai/rtk). From the checkout:

```sh
rtk proxy python3 build.py
rtk proxy open ./Glowline.app
```

The builder compiles the SwiftUI/AppKit app and Objective-C ScreenCaptureKit/serial engine, runs C/Swift contracts and verifies its ad-hoc signature. No third-party runtime library is bundled. A source build can require Screen Recording approval again.

```sh
rtk proxy python3 package.py
```

Packaging creates ZIP, DMG and `SHA256SUMS` under `build/distribution/`, with the app, both installation guides, MIT license, offline lighting test and a file-hash manifest. It verifies ZIP extraction, extracted signatures and DMG integrity. `--skip-dmg` makes only ZIP; `--verify-mount` additionally checks mounted image contents when macOS permits it. Packaging never uploads or submits to Apple.

For Developer ID signing and notarization preparation, see [distribution documentation](DISTRIBUTION.md). Version and build are in `VERSION.json`; application code is in `Source/`, resources in `Resources/` and additional tests in `Tests/`.

The night light compiles from `Source/Ambient/` into the same Glowline executable; `Resources/Noctiluca.metal` is bundled. To inspect the UI and GPU without a second strip controller, use `rtk python3 build.py --output-app /tmp/GlowlineReview.app --ambient-review`. This build has separate state and does not change live profiles, permissions or login registration. Build a regular candidate with `--output-app /tmp/GlowlineCandidate.app`, then package it using `rtk python3 package.py --app /tmp/GlowlineCandidate.app --output-dir /tmp/GlowlinePackages --skip-dmg`. Run GPU diagnostics without starting the controller with `rtk /tmp/GlowlineCandidate.app/Contents/MacOS/Glowline --ambient-benchmark /tmp/GlowlineGPU`; it writes PNGs and a JSON report of GPU time, which differs from window FPS.

Terrain lives in `Source/Ambient/Sand.swift`: a fixed 1024×1024 field spanning 128×128 world units at 0.125-unit spacing. Each cell stores height, two slopes and scorch. The core opens at contact; outward excavation scales with √(R/g), with local fracture windows up to 65 ms and distant deposition windows of 180 ms. The lip rises during excavation. Formation duration depends on crater size and deposit distance. Residual time since swept contact is applied in the same frame. Temporary formation patches are then removed; old craters have no count or time expiry. Single-hit depths stay between 0.10 and 0.22 units, with an accumulated floor at −0.28 and deposits limited to 0.14. Impact energy primarily widens the crater; subsequent small impacts remain visible. Low broken rims, thinner distant ejecta rays and broad low ballistic fans keep the foreground open. Slope collapse and shock transport conserve volume; the initial artistic excavation/deposition profile does not model full mass balance. Three GPU snapshots update only after terrain changes and share the renderer's in-flight frame gate. Debris illumination is accumulated on the GPU into a separate 1024×1024 map in terrain coordinates and applied to the real ground geometry. This map clears every frame, while craters persist. Terrain and Metal contracts:

Indexed terrain and body meshes reuse vertices; destroyed shells are rejected before expensive shading. Local avalanche work arrays are reused. These optimizations preserve particle counts, brightness and flash size.

[Simulation modules and CPU/GPU contracts](AMBIENT.md).

```sh
rtk xcrun swiftc -O -module-cache-path /tmp/glowline-module-cache -parse-as-library Source/Ambient/Camera.swift Source/Ambient/MeteorShower.swift Source/Ambient/SceneDirector.swift Source/Ambient/SceneMath.swift Source/Ambient/BodyModel.swift Source/Ambient/SceneBody.swift Source/Ambient/BodyContacts.swift Source/Ambient/SimulationFrame.swift Source/Ambient/ParticleModel.swift Source/Ambient/ParticleEmitter.swift Source/Ambient/SceneSimulation.swift Source/Ambient/Sand.swift Tests/test_sand.swift -o /tmp/glowline-sand-tests
rtk /tmp/glowline-sand-tests
rtk xcrun swiftc -O -module-cache-path /tmp/glowline-module-cache -parse-as-library Source/Ambient/Camera.swift Source/Ambient/MeteorShower.swift Source/Ambient/SceneDirector.swift Source/Ambient/SceneMath.swift Source/Ambient/BodyModel.swift Source/Ambient/SceneBody.swift Source/Ambient/BodyContacts.swift Source/Ambient/SimulationFrame.swift Source/Ambient/ParticleModel.swift Source/Ambient/ParticleEmitter.swift Source/Ambient/SceneSimulation.swift Source/Ambient/Sand.swift Source/Ambient/Renderer.swift Tests/test_sand_gpu.swift -o /tmp/glowline-sand-gpu-tests
rtk /tmp/glowline-sand-gpu-tests
```

## Verification limits

Local automated checks cover color/control logic, fragmented and invalid controller replies, settings migration, profiles, capture-failure invalidation and bounded recovery. C contracts have also been run with AddressSanitizer and UndefinedBehaviorSanitizer. The CI workflow runs builds and offline contracts on macOS 15/26; it does not test a real strip or screen-permission dialogs.

Earlier physical testing on one installed setup covered all six modes, brightness, master-off, profiles, screen capture and serial frame progression. The release candidate's new recovery paths have automated coverage. Clean-Mac installation, a second physical controller, sleep/wake and login after reboot remain unverified. DMG integrity passed locally; mounted-image installation was not verified. No optical calibration or measured input-to-light latency is claimed.

## License

Glowline is distributed under the [MIT License](../LICENSE). This project is independent of Skydimo and is not an official Skydimo application.
