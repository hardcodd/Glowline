# Glowline for Windows 11

[Русский](WINDOWS.ru.md) · [Project](../README.en.md)

The Windows source targets **Windows 11 x64**, for AMD and Intel processors, and the same **Skydimo SK0L34 / 112-LED** layout as the macOS app. Windows 10, other controllers and other strip lengths are unsupported. The Windows port is not part of the published 1.2.0 macOS release.

## Run

Extract the Windows ZIP to a permanent folder and open `Glowline.exe`. The app uses Windows components and a statically linked C++ runtime; installing Visual Studio is only necessary for development. The executable is unsigned.

Quit other programs controlling the strip. Under **Приложение**, refresh devices and select the controller's **COM** port. Glowline opens only the selected port, exclusively, and verifies the full SK0L34 response before sending LED frames. It does not flash firmware or negotiate another baud rate. The USB serial driver must match the Windows machine's architecture; an x64 app running on Windows ARM still needs an ARM64 device driver.

Under **Захват экрана**, select a display for **Экран** mode. Windows Graphics Capture supplies linear RGBA-half frames; the cursor is excluded. Protected content and the secure desktop cannot be captured. A capture failure clears the output and exposes an error. Other effects run without screen capture. Display-only virtual adapters use the system WARP renderer when hardware Direct3D is unavailable; this can reduce performance.

Closing the window keeps Glowline in the notification area. Click its icon to reopen settings, or select **Выйти** to quit. **Гасить ленту при выходе** controls the final blackout. The startup option registers the current executable's path for the current Windows user; turn it off before moving or deleting that folder.

## Settings and profiles

The seven sections expose the nine modes, independent effect parameters, color correction, LED mapping and per-side gains, day/night brightness schedule, capture/output rates, profiles and application preferences. The schedule uses Windows local time; equal day/night start times use manual brightness. Settings save automatically. Profiles are explicit snapshots and must be updated separately.

The Russian interface follows the current macOS app’s seven sections, labels and parameters, with dark, light and system appearance. Sliders support arrow keys, Home/End and numeric entry; LED offset changes in single steps. An active schedule disables manual brightness. Turning a side off disables its gain. File/color dialogs, the title bar and startup settings follow Windows conventions.

Under **Приложение → Открыть диагностику**, the app saves and opens `diagnostics.txt` beside the settings: connection/capture state, frame rate, write duration, frame counters and current errors. This is a snapshot taken when the button is pressed.

Preferences are stored in `%LOCALAPPDATA%\Glowline\settings.json`. Import/export uses schema 1 JSON, including profiles and per-mode controls. A macOS USB path is cleared on Windows; select the COM port again. Windows display selection uses its own `windowsDisplay` field. Corrupt startup data is preserved in a sibling backup; a future schema is refused without replacing it.

Recovery is bounded to an initial attempt plus three retries after 5, 10 and 20 seconds. Ten healthy seconds replenish each recovery budget. **Переподключить** retries immediately. The reconnect preference controls automatic serial recovery.

The experimental early-response capture switch is available only on macOS.

## Build and check

Install Visual Studio 2022 C++ Build Tools with these components:

- `Microsoft.VisualStudio.Workload.VCTools`
- `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`
- `Microsoft.VisualStudio.Component.Windows11SDK.26100`
- `Microsoft.VisualStudio.Component.VC.Llvm.Clang`

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\package-windows.ps1
```

The output is `build\windows-x64\Glowline.exe`. The build runs offline settings, scheduling, recovery and color/protocol contracts. These touch neither USB nor saved preferences. In an interactive Windows session, run the additional checks:

```powershell
.\build\windows-x64\Glowline.exe --ui-test "$env:TEMP\Glowline-ui-report.txt"
.\build\windows-x64\Glowline.exe --capture-test "$env:TEMP\Glowline-capture-report.txt"
```

The capture check temporarily fills the primary display with red and blue test surfaces. Both commands write a report and return a nonzero exit code on failure. GUI and capture checks require a logged-in desktop and are separate from headless CI. The x64 build, ZIP round-trip, offline contracts, seven UI sections and red/blue capture checks passed in a Windows 11 ARM VM through x64 emulation. This does not establish performance, USB-driver compatibility or optical acceptance on physical AMD/Intel hardware.

The GitHub workflow builds and retains a Windows x64 candidate as an Actions artifact; it does not publish a release.
