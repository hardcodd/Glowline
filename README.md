# Glowline — macOS Ambient Lighting for Skydimo

Glowline is a native macOS menu-bar app for screen-synced monitor backlighting with a Skydimo SK0L34 112-LED strip. It combines ScreenCaptureKit screen capture, adjustable warm bias lighting, six lighting modes and local profiles in a SwiftUI settings window.

**Status:** in development; source build only. No GitHub release is available yet. Compatible SK0L34 controllers can use their own serial identity; support remains limited to the fixed 112-LED layout and protocol described below.

[Русское руководство](РУКОВОДСТВО.md)

[Features](#features) · [Compatibility](#compatibility) · [Build and limitations](#build-and-limitations) · [Troubleshooting](#troubleshooting)

## Features

- Screen-synced ambient lighting with adjustable edge capture and per-side controls.
- Screen, solid color, gradient, breathing, rainbow and candle modes.
- Brightness, warmth, RGB color correction and separate fade-in/fade-out controls.
- Native menu-bar access, optional login launch and hidden startup.
- Named profiles with local persistence and JSON import/export.
- Local screen processing without saved or uploaded screen images.

## Compatibility

| Requirement | Current support |
| --- | --- |
| Operating system | macOS 15 or later |
| Architecture | Apple Silicon (arm64) |
| Controller | Skydimo SK0L34, fixed 112-LED layout |
| Device verification | Complete `Moni-A` response: `SK0L34,` plus seven device-specific bytes, optionally followed by CR LF; no serial-number lock |
| Serial transport | 115200 baud; USB serial port selected in settings |
| Screen mode | macOS Screen Recording permission |
| Interface language | Russian |
| Build tools | Apple Command Line Tools, Python 3 and RTK |

Select your controller's USB serial port under **Приложение** on first launch. New installations have no preselected port; existing saved port settings are retained. The engine checks the model/protocol response before sending lighting frames and accepts different serial suffixes. The handshake does not report LED count: your strip must have the same 112-LED layout and use the existing 342-byte frame format at 115200 baud. Other strip lengths, generic RGB controllers, Intel Macs and other operating systems are not supported by this build.

## Open and use

After building, place `Glowline.app` in `~/Applications/`. Open **Open-Glowline.command**, or launch Glowline from Applications. The command launcher expects RTK at `/opt/homebrew/bin/rtk`. Closing the window leaves the menu-bar controller running. Quit through the Glowline menu or Command-Q.

Screen mode requires macOS Screen Recording permission for Glowline. If macOS requests a restart, quit and reopen the app. If a rebuild leaves the switch enabled but the app still reports no access, remove only Glowline from the Screen Recording list and add the installed copy again: toggling can retain a stale signature requirement. Other modes do not require screen access. All processing is local; screen images are not saved or uploaded.

Login launch and hidden login launch are enabled by default. Check the actual registration status under **Приложение**. Login launch occurs after the user signs in, not before authentication. The **Приложение** page links to macOS Login Items when approval is required.

## Controls and defaults

- Screen, solid color, gradient, breathing, rainbow and candle modes.
- Brightness, warmth, saturation, gamma, RGB gains and black threshold.
- Capture depth, separate fade-in/fade-out, mirror, LED offset and individual side controls.
- Display, capture frequency, output pacing, unchanged-frame suppression and heartbeat.
- Named profiles, JSON import/export, local persistence and reset to the accepted defaults.

Accepted defaults: brightness 100%, warmth 50%, intentional mirror, weighted capture depth 15%, fade-out time constant 180 ms, immediate fade-in, capture 120 Hz, output pacing limit 33.68 FPS and 100 ms static heartbeat. Warmth can increase to 90%; neutral color is removed from green and blue without changing pure RGB primaries at neutral gain/saturation settings. The warmth scale is not a Kelvin measurement.

The serial transport remains 115200 baud. The pacing limit is not a promise of actual LED FPS; status shows actual writes. Static scenes intentionally send fewer identical packets. External USB hub power resolved the observed slight flicker in the tested setup.

## Profiles and local data

Settings, profiles, bounded logs and diagnostics live in `~/Library/Application Support/Glowline/`. Export JSON from **Мои профили** before experimenting. Reset restores the initial warm configuration while preserving the selected USB port. Imported profiles may contain another machine's port; select yours again if needed.

Quit Skydimo and any other program controlling the strip before opening Glowline. Competing controllers cannot safely share its serial port.

## Build and limitations

Install Apple Command Line Tools, Python 3 and [RTK](https://github.com/rtk-ai/rtk). From the project directory, run:

```sh
rtk proxy python3 build.py
```

The build runs C color/control contracts and Swift settings/profile/status contracts, then creates and locally signs `Glowline.app`. To try the built app:

```sh
rtk proxy open ./Glowline.app
```

Source is in `Source/`, retained C tests in `Tests/`; Swift contracts are embedded in the app's self-test path. There are no third-party application dependencies; the build script invokes development tools through RTK. This is an ad-hoc signed local build, not a notarized distribution. Rebuilding can require Screen Recording approval again. It supports compatible SK0L34 controllers with the fixed 112-LED layout; it does not flash firmware or change the display’s color profile.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Screen mode has no capture access | Grant Screen Recording permission to the app copy you use; restart if requested. See the permission recovery steps above after rebuilding. |
| Controller unavailable or busy | Quit other lighting controllers, check USB connectivity and select the correct serial port. |
| Controller response rejected | Check the selected port and protocol compatibility. Incomplete replies and other models are rejected; a different serial number is allowed. |
| Flicker with a USB hub | Check the hub's external power supply. |
| App remains active after closing its window | Use the menu-bar Quit action or Command-Q. |
| Login launch needs approval | Check the app's registration status and macOS Login Items. |

## Previously verified on one setup

Earlier local testing with the connected strip covered all six modes, live brightness, master-off (112 black RGB outputs), named profile restore, native JSON export/import, window close with continued processing, hidden launch and login registration. These results describe one setup and do not establish compatibility with other controllers.

The compatibility update is covered by simulated handshakes with different binary suffixes, fragmented replies, wrong models and timeout/truncation cases, plus settings validation and existing color/profile checks. A second physical controller has not been tested.

A 15-second moving-pattern test in Firefox produced 26.45–26.81 output FPS (median 26.60), with no queued old packets. Full-screen tests produced RGB 255/0/0, 0/255/0 and 1/1/255 for the primaries; accepted warm white was 255/210/128. Firefox was returned to its original tab and exited full screen. These are digital output checks, not optical colorimeter measurements. Login registration and hidden launch were checked without rebooting the Mac.

## Source layout

- `Source/`: SwiftUI/AppKit app and Objective-C capture/serial engine.
- `Resources/`: application icon and Russian localization.
- `Tests/`: retained C color/control contracts.
- `build.py`: local build, contract checks and ad-hoc signing.
- `open_app.py`, `Open-Glowline.command`: launcher for the app in `~/Applications/`.
