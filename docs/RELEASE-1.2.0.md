# Glowline 1.2.0

[Русский](RELEASE-1.2.0.ru.md)

A native Metal night light now runs inside Glowline, alongside nine lighting modes with independent effect settings.

## New

- **Built-in Noctiluca:** open **Приложение → Запустить ночник** or the matching menu item. Fiery stars, deposited comet trails, molten fragments and colorful nebulae render locally without a browser or a separate installation. The strip continues following the screen in **Экран** mode.
- **Independent starfall:** varied sizes and speeds, occasional crossing meteor trajectories, rare giants and collisions that break only the smaller star. Giants continue into the lower part of the screen before their broad explosion.
- **Night-light controls:** fullscreen, pause, three palettes, brightness and speed, a night preset, rare black pauses and a 30/60/120-minute timer. Esc returns to Glowline; closing releases rendering resources without stopping the strip controller.
- **Nine strip modes:** Fire, Comet and Aurora join Screen, Single color, Gradient, Breathing, Rainbow and Candle. Each effect remembers its own colors and movement; profiles include these settings.

## Fixes

- Status polling continues during slider dragging and in offline self-tests.
- The application footer reads its version from the bundle instead of displaying a fixed old version.

## Install and update

Apple Silicon, macOS 15+, Skydimo SK0L34 with the fixed 112-LED layout. Build 4. ZIP and DMG contain the same application; verify them against `SHA256SUMS`.

Quit Glowline completely and replace the application at the same location. Settings and profiles remain outside the bundle. Export JSON first for a backup. Do not run a second strip controller or a diagnostic Review build for normal use.

Ad-hoc signed, without Developer ID or Apple notarization. An update can require Screen Recording permission again. Follow the [installation guide](https://github.com/hardcodd/Glowline/blob/v1.2.0/docs/INSTALL.md).

## Verification and limits

Checks cover settings, profiles, scheduling, appearance, capture, sampling, controller contracts, star trajectories, collisions, a simulated hour, GPU layout, signatures and package integrity. The native scene was measured at about 72 FPS on an M4 Pro at 3440×1440; other hardware and scenes may differ. No universal minimum FPS is guaranteed.

Downloaded-package installation on a clean Mac, a second physical controller and optical calibration remain unverified. This release contains macOS artifacts only.
