# Glowline — monitor ambient lighting for macOS and Windows 11

Glowline syncs a **Skydimo SK0L34 USB backlight with 112 LEDs** to colors at the edges of your screen. It runs in the macOS menu bar with a Russian interface and local settings.

**[Download Glowline 1.3.0 for macOS](https://github.com/hardcodd/Glowline/releases/latest)** · [Windows 11 x64](docs/WINDOWS.md) · [User guide](docs/USER-GUIDE.en.md) · [Русский](README.md)

![Glowline interface: lighting preview, brightness and warmth](docs/images/glowline-macos-ambient-lighting.png)

*Version 1.3.0 includes scheduling and nine lighting modes. The outline previews transmitted colors.*

## macOS requirements

An **Apple Silicon Mac running macOS 15+**, a **Skydimo SK0L34 USB controller** and the fixed **112-LED** strip layout. Intel Macs and other models/lengths are unsupported. One physical setup has been tested; see the [compatibility guide](docs/USER-GUIDE.en.md#compatible-led-strip).

## macOS quick start

1. Download ZIP or DMG and copy `Glowline.app` to `~/Applications/`.
2. Open the app. If macOS blocks it, follow the [installation guide](docs/INSTALL.md#first-launch-without-an-apple-developer-id-certificate): this release uses ad-hoc signing without Apple notarization.
3. Quit other strip controllers and select the USB port under **Приложение**.
4. For **Экран** (Screen) mode, grant Screen Recording in macOS settings. Other modes need no screen access.

Closing the window keeps lighting running. Reopen settings through the menu-bar icon; quit completely with **Command-Q**.

## Windows 11 x64

A separate port for AMD and Intel provides a Russian interface, nine modes, scheduling and profiles. It builds from the current source and has not been published in releases. It requires Windows 11 and the same SK0L34 / 112-LED controller. [Run, build and verification limits](docs/WINDOWS.md).

## Features

Version 1.3.0 includes the following features.

- **Nine modes:** screen, solid, gradient, breathing, rainbow, candle, fire, comet and aurora.
- **Color and warmth:** brightness, saturation, gamma and per-side correction.
- **Color detail:** switch between dominant-hue sampling and standard averaging.
- **Brightness schedule:** editable day/night start times and brightness, easy to adjust seasonally. Disabled by default.
- **Per-effect controls:** colors, motion and artistic settings are remembered independently for each mode.
- **Profiles:** save settings and import/export JSON.
- **Light, dark and system appearance**, login launch and menu-bar controls.

Current settings **save automatically**, including across a complete quit. Profiles are separate snapshots: save one again to update it after adjustments. App updates preserve settings and profiles.

## Guides and help

[Full user guide](docs/USER-GUIDE.en.md) · [Installation and updates](docs/INSTALL.md) · [What's new in 1.3.0](docs/RELEASE-1.3.0.md) · [Report an issue](https://github.com/hardcodd/Glowline/issues)

Download and open the offline [lighting test](docs/lighting-test.html) in a browser to compare colors on any aspect ratio, including ultrawide monitors. `F` toggles fullscreen, Space pauses and `H` hides controls.

Source and [build instructions](docs/USER-GUIDE.en.md#build-from-source) are available under [MIT](LICENSE). Glowline is independent and is not an official Skydimo application. Screenshots and audio are never saved or uploaded.
