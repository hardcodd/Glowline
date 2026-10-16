# Glowline 1.1.0

[Русский](RELEASE-1.1.0.ru.md)

Daily brightness scheduling and clearer color separation, preserving current settings and profiles.

## New

- **Schedule:** set local day/night start times and brightness for each period. Works across all modes; disabled by default. Turning it off restores manual brightness. Included in profiles.
- **Color detail:** compare dominant-hue sampling with original averaging under Capture. Disabled by default; LED count and saturation do not change.
- **Whole slider increments:** 1 percentage point, 1 ms, 0.01 gamma and 0.1× speed. Existing saved values remain exact until edited.
- **Lighting test:** offline HTML with six scenes, pause and fullscreen for any monitor aspect ratio. `lighting-test.html` is included in the package.

## Fixes

- Dark-to-system appearance switching and light-theme label readability.
- Engine status decoding that caused false reconnects and a blank color preview.
- Short Russian default README, with an English translation and updated full guides.

## Install and update

Apple Silicon, macOS 15+, Skydimo SK0L34 with the fixed 112-LED layout. Build 3. Download either ZIP or DMG; both contain the same app. Checksums are in `SHA256SUMS`.

Quit Glowline completely and replace it at the same location. Current settings save automatically outside the app. Profiles are separate snapshots: save again after adjustments to update one. Export JSON before updating for a backup.

Ad-hoc signed, without Developer ID or Apple notarization. First launch may require Open Anyway; an update may require Screen Recording permission again. See `INSTALL.md` in the package or the [installation guide](https://github.com/hardcodd/Glowline/blob/main/docs/INSTALL.md).

Automated checks cover scheduling, settings/profiles, slider steps, appearance, sampling, capture and the controller protocol, plus signatures and package integrity. Downloaded-package installation on a clean Mac, a second physical controller and optical calibration remain unverified.
