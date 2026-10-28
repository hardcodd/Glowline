# Glowline 1.3.0

[Русский](RELEASE-1.3.0.ru.md)

Glowline focuses on screen-following and decorative LED lighting. Noctiluca has moved to the standalone Dream Away project and is no longer bundled with Glowline.

## Changes

- Removed the built-in night light, its menu entries, idle-launch controls and Metal resources. Existing strip settings, profiles, scheduling and nine lighting modes are retained.
- Added optional experimental early screen response, preserving edge sampling. It is disabled by default; compare it with normal capture on your setup before enabling it for regular use.
- Shared controller-identity and half-float decoding checks, with additional offline contracts and build compatibility fixes.
- Windows 11 x64 sources and CI are available; this release distributes macOS packages only. Windows hardware use remains unverified.

## Install and update

Apple Silicon, macOS 15+, Skydimo SK0L34 with the fixed 112-LED layout. Build 5. ZIP and DMG contain the same application; verify them against `SHA256SUMS`.

Quit Glowline completely and replace the application at the same location. Export settings first for a backup. Settings and profiles remain outside the bundle and are preserved. Do not run competing strip controllers. Old night-light preferences are no longer used; they do not configure Dream Away.

Ad-hoc signed, without Developer ID or Apple notarization. Screen Recording permission may need to be granted again. Follow the [installation guide](https://github.com/hardcodd/Glowline/blob/v1.3.0/docs/INSTALL.md).

## Verification and limits

The release checks cover builds, offline settings/profile/schedule/UI contracts, capture and controller behavior, signatures, ZIP extraction checksums and read-only DMG contents. They do not replace physical hardware or interactive installation tests.

Installation of the downloaded package on a clean Mac, a second physical controller, reboot/login behavior and optical calibration remain unverified.
