# Glowline — macOS Ambient Lighting for Skydimo SK0L34

Glowline is a native macOS menu-bar app that syncs a **Skydimo SK0L34 USB monitor backlight with 112 LEDs** to the edges of your screen. It provides six lighting modes, adjustable warm bias lighting, per-side color correction and local profiles in a SwiftUI interface.

[Download for Apple Silicon](https://github.com/hardcodd/Glowline/releases/latest) · [Русское руководство](РУКОВОДСТВО.md) · [Installation and updates](docs/INSTALL.md) · [Report an issue](https://github.com/hardcodd/Glowline/issues)

![Glowline macOS app showing screen-synced Skydimo SK0L34 112-LED ambient lighting, brightness and warmth controls](docs/images/glowline-macos-ambient-lighting.png)

*Actual running application; Russian interface. The monitor outline previews transmitted colors, not measured light output. Minor wording differs in version 1.0.0.*

**Version 1.0.0, build 2:** Apple Silicon, macOS 15+. The download is ad-hoc signed, without a paid Developer ID certificate or Apple notarization. First launch may require a manual exception in macOS settings; see below.

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
5. For **Экран** mode, grant Glowline **Screen Recording** permission in macOS Privacy & Security. Quit and reopen it if requested. The other five modes work without screen access.
6. Check login-launch status under **Приложение**. Login launch and hidden startup are enabled by default; macOS may require approval in Login Items.

Do not disable Gatekeeper globally. A warning that the app is damaged or will harm your computer requires investigation; it is not the ordinary unidentified-developer prompt. A managed Mac may prohibit exceptions. Downloaded-package first launch on a clean Mac has not yet been verified.

Closing the settings window leaves the menu-bar app and lighting running. Reopen settings from the Glowline menu-bar icon; quit through that menu or **Command-Q**. The menu also offers the light switch, lighting modes and saved profiles.

For checksum verification, updates, permission recovery and removal, see the [installation guide](docs/INSTALL.md).

## Lighting modes

| Mode in the app | Behavior |
| --- | --- |
| Экран — Screen | Samples screen edges and sends corresponding colors to the strip |
| Один цвет — Solid | One adjustable color across the strip |
| Градиент — Gradient | Two colors distributed around the strip |
| Дыхание — Breathing | Animated brightness changes |
| Радуга — Rainbow | Moving multicolor effect |
| Свеча — Candle | Warm animated glow |

The master light switch sends black without losing your settings. Effect colors, speed and direction are adjustable where applicable.

## Settings

| Page | Controls |
| --- | --- |
| Освещение | Live color-output preview, brightness, warmth and quick mode selection |
| Цвет и теплота | Brightness, warmth, saturation, gamma, RGB gains and black threshold |
| Захват экрана | Display, weighted edge depth, fade-in/fade-out, mirror, LED offset, side enable/gain controls, capture rate and output pacing |
| Режимы и эффекты | Mode, effect colors, speed and direction |
| Мои профили | Named profiles, JSON import/export and reset to defaults |
| Приложение | USB port, reconnect, launch at login, hidden startup, off-on-quit, appearance, permissions and log |

Controls apply automatically. Defaults are brightness **100%**, warmth **50%**, mirror enabled, edge depth **15%**, fade-out time constant **180 ms**, immediate fade-in, capture **120 Hz**, output limit **33.68 FPS** and static heartbeat **100 ms**. Warmth can be increased to **90%**; it is an artistic adjustment, not a calibrated Kelvin value.

Capture rate and LED output rate are separate. The serial link limits throughput; 120 Hz capture does not mean 120 FPS on the strip. Unchanged-frame suppression reduces redundant writes. A prior moving-pattern test on one setup produced approximately 26.6 output FPS; this is not a guaranteed rate or a latency measurement.

After a capture error, old screen colors are cleared and the app reports the failure. With reconnect enabled and light on, recovery is limited to three restarts with backoff; ten healthy seconds reset the budget. If it still fails, check permissions and use **Переподключить**.

## Profiles, updates and privacy

Settings, profiles and bounded diagnostic files are stored locally in `~/Library/Application Support/Glowline/`, separately from the app. Screen images and audio are not saved or uploaded. Glowline has no account requirement or cloud service.

Export JSON from **Мои профили** before updating. Quit the app, replace it at the same location and keep the old copy until the update works. Existing settings and profiles are retained; missing older fields receive defaults. Invalid data or unsupported schemas are rejected, and unreadable startup settings are backed up. A signature change may require Screen Recording approval again.

Resetting lighting defaults preserves your selected USB port and named profiles. An imported profile may contain another Mac's port; select yours again. See [update and removal instructions](docs/INSTALL.md).

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

Packaging creates ZIP, DMG and `SHA256SUMS` under `build/distribution/`, with the app, both installation guides, MIT license and a file-hash manifest. It verifies ZIP extraction, extracted signatures and DMG integrity. `--skip-dmg` makes only ZIP; `--verify-mount` additionally checks mounted image contents when macOS permits it. Packaging never uploads or submits to Apple.

For Developer ID signing and notarization preparation, see [distribution documentation](docs/DISTRIBUTION.md). Version and build are in `VERSION.json`; application code is in `Source/`, resources in `Resources/` and additional tests in `Tests/`.

## Verification limits

Local automated checks cover color/control logic, fragmented and invalid controller replies, settings migration, profiles, capture-failure invalidation and bounded recovery. C contracts have also been run with AddressSanitizer and UndefinedBehaviorSanitizer. The CI workflow runs builds and offline contracts on macOS 15/26; it does not test a real strip or screen-permission dialogs.

Earlier physical testing on one installed setup covered all six modes, brightness, master-off, profiles, screen capture and serial frame progression. The release candidate's new recovery paths have automated coverage. Clean-Mac installation, a second physical controller, sleep/wake and login after reboot remain unverified. DMG integrity passed locally; mounted-image installation was not verified. No optical calibration or measured input-to-light latency is claimed.

## License

Glowline is distributed under the [MIT License](LICENSE). This project is independent of Skydimo and is not an official Skydimo application.
