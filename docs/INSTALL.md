# Install, update and remove Glowline

[Русский](INSTALL.ru.md)

Requires Apple Silicon, macOS 15 or later, and a compatible SK0L34 strip with 112 LEDs. The interface is Russian. No Python, RTK or developer tools are needed to run the packaged application.


Current settings save automatically after edits and return on launch. Named profiles are separate snapshots: save again to update one. Schedule and Color detail are disabled by default; enable them on their respective pages. Open the included `lighting-test.html` in a browser: `F` for fullscreen, Space to pause, `H` for controls.

For the built-in Metal night light, choose **Приложение → Запустить ночник** in Glowline itself. No browser or second app is needed. **Esc** returns to Glowline, **F** toggles fullscreen and **S** opens night-light settings. The animation does not require Screen Recording permission; screen-following strip lighting does.

## Install

1. Verify the download against `SHA256SUMS` from the same trusted distribution.
2. Extract the ZIP or open the DMG. Copy `Glowline.app` to `~/Applications/` (create the folder if needed). Run it from that permanent location.
3. Quit Skydimo and other controllers. Choose the USB serial port under **Приложение**.
4. For screen mode, grant Screen Recording in macOS Privacy & Security, then quit and reopen Glowline if requested. Other lighting modes work without screen permission.
5. Check the actual login-launch registration under **Приложение**; macOS may require approval in Login Items.

## First launch without an Apple Developer ID certificate

Version 1.2.0 is ad-hoc signed and is not notarized by Apple. If macOS blocks the first launch because it cannot verify the developer or check the app:

1. Try opening the installed Glowline copy once, then dismiss the warning.
2. Open **System Settings → Privacy & Security**, scroll to the Glowline security message and click **Open Anyway**.
3. Confirm **Open**, authenticating if requested. macOS normally remembers the exception for this copy.

Use this only for the official GitHub download you trust. [Apple explains the procedure](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally or treat a damaged-app/malware warning as the same prompt. Managed Macs may prohibit exceptions. First launch of the downloaded package on a clean Mac remains unverified.

To check a ZIP download, use the built-in Terminal tool and compare its output with the corresponding line in `SHA256SUMS`:

```sh
shasum -a 256 Glowline-1.2.0-build4-arm64.zip
```

For DMG, use its filename instead. A matching checksum detects a changed download; it does not replace a Developer ID certificate or notarization.

## Update and recover

Export settings from **Мои профили**. Quit Glowline completely before replacing the app at the same location. Keep the old app until the new one works. Settings and profiles remain in `~/Library/Application Support/Glowline/` and are not inside the app bundle. Missing fields from older settings inherit defaults; unsupported schemas and invalid values are rejected, with a backup of unreadable startup data.

A different signature can require Screen Recording permission again. If an enabled switch still gives no capture, remove only Glowline from the permission list, add the installed copy and reopen it. Recheck the selected USB port and login status. To return to the previous build, quit Glowline and restore the saved app; do not run both copies or another strip controller simultaneously.

After a capture error, stale screen colors are cleared. With automatic reconnect enabled and light on, up to three restarts are attempted with backoff; ten healthy seconds reset the budget. If it still fails, check permission and use **Переподключить**. No screens or audio are saved or uploaded.

## Remove

Disable **Запускать при входе в macOS**, verify the registration status and quit Glowline. Delete the app. Settings remain for reinstalling. To erase them too, first export anything needed, then delete only `~/Library/Application Support/Glowline/`. Remove Glowline's Screen Recording entry in macOS if desired. Do not remove other applications or their permissions.

Night-light preferences are stored separately in the `local.alex.Glowline.ambient` UserDefaults domain. After quitting Glowline, `defaults delete local.alex.Glowline.ambient` removes only these preferences if they exist.
