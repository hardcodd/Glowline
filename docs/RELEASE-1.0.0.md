# Glowline 1.0.0

Native macOS ambient lighting for **Skydimo SK0L34 USB monitor strips with 112 LEDs**. First public binary release, build 2.

[Русские примечания](https://github.com/hardcodd/Glowline/blob/v1.0.0/docs/RELEASE-1.0.0.ru.md) · [Full guide and screenshot](https://github.com/hardcodd/Glowline/blob/v1.0.0/README.md)

## Requirements and compatibility

- Apple Silicon (arm64), macOS 15 or later. The interface is Russian.
- Skydimo SK0L34 with the fixed 112-LED layout, 115200-baud serial protocol and 342-byte RGB frames.
- No author-specific serial-number lock. The controller must return the expected SK0L34 model response; LED count/layout are not negotiated.
- Other strip lengths/models, Intel Macs and Bluetooth/Wi-Fi controllers are not supported. A second physical controller has not been tested.

## Features

- Screen synchronization through ScreenCaptureKit; solid color, gradient, breathing, rainbow and candle modes.
- Brightness, warmth up to 90%, saturation, gamma, RGB and per-side correction.
- Adjustable edge depth, fade-in/fade-out, mirror, LED offset, display selection and frame pacing.
- Menu-bar controls, optional login launch/hidden startup, named profiles and JSON import/export.
- Local processing without saved/uploaded screen images, accounts or a cloud service.

## Reliability changes

- Accepts bare or CRLF-terminated SK0L34 identities, including fragmented replies; rejects malformed/delayed trailers before sending LED frames.
- Older settings and profiles inherit missing fields without discarding saved values.
- Capture errors clear old screen colors and appear in status. Automatic recovery has a three-restart budget and backoff.
- Initial capture frequency is retained during asynchronous startup.

## Download and first launch

Download **one** application package below: ZIP or DMG. Both contain the same app, English/Russian installation guides, MIT license and file-hash manifest. `SHA256SUMS` contains the hashes of both downloads. No developer tools are needed to run the app. GitHub's automatically generated “Source code” archives are source checkouts, not the application.

1. Copy `Glowline.app` to `~/Applications/` and open it.
2. **No paid Developer ID certificate or Apple notarization is included.** If macOS blocks the app because the developer cannot be verified, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open** for Glowline. Use only the trusted official download; do not disable Gatekeeper globally. [Apple's instructions](https://support.apple.com/en-us/102445).
3. Quit other strip-control apps and select your USB port under **Приложение**.
4. Grant **Screen Recording** for screen synchronization; reopen the app if requested. Other modes do not need screen access.

For updates, export profiles, quit Glowline and replace the app at the same location. Settings remain outside the bundle. A changed signature may require Screen Recording permission again. [Installation, update and removal guide](https://github.com/hardcodd/Glowline/blob/v1.0.0/docs/INSTALL.md).

## Validation and known limits

The local full build, C/Swift contracts, C AddressSanitizer/UndefinedBehaviorSanitizer, synthetic capture-failure test, ZIP extraction/hash/signature verification and DMG integrity check passed. Previous hardware tests covered all six modes on one installed SK0L34 setup; new recovery paths are covered by automated tests.

Clean-Mac downloaded-package launch, a second physical controller, sleep/wake, login after reboot and mounted-DMG installation remain unverified. Gatekeeper exceptions may be unavailable on managed Macs. No optical calibration, guaranteed FPS or measured end-to-end latency is claimed.

MIT licensed. Independent project; not an official Skydimo application. [Report an issue](https://github.com/hardcodd/Glowline/issues).
