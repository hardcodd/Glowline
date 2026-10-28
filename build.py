#!/usr/bin/env python3
"""Build and locally sign the native Apple Silicon application with the installed SDK."""
from pathlib import Path
import subprocess, shutil, plistlib, json, argparse, os
from typing import Union
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sign-identity", default="-", help="Developer ID identity, or '-' for a local ad-hoc build")
parser.add_argument("--output-app", type=Path, help="Build a separate candidate bundle at this path")
args = parser.parse_args()
root = Path(__file__).resolve().parent
version = json.loads((root / "VERSION.json").read_text())
if not isinstance(version["build"], int) or version["build"] < 1:
    raise SystemExit("VERSION.json build must be a positive integer")
work = root / "build"
work.mkdir(parents=True, exist_ok=True)
source = root / "Source"
app = args.output_app.resolve() if args.output_app else root / "Glowline.app"
contents = app / "Contents"
macos = contents / "MacOS"
resources = contents / "Resources"
macos.mkdir(parents=True, exist_ok=True)
resources.mkdir(parents=True, exist_ok=True)
def run(*args: Union[str, Path, int]) -> None:
    command = list(map(str, args))
    # RTK's proxy can split an executable path containing spaces; keep it as argv.
    if " " in command[0]:
        command = ["python3", "-c", "import subprocess,sys; subprocess.run(sys.argv[1:],check=True)", *command]
    subprocess.run(["rtk", "proxy", *command], check=True)
run("xcrun", "clang", "-fobjc-arc", "-O3", "-Wall", "-Werror", "-Wno-unused-function", "-mmacosx-version-min=15.0", "-framework", "Foundation", "-framework", "ScreenCaptureKit", "-framework", "CoreGraphics", "-framework", "CoreMedia", "-framework", "CoreVideo", "-arch", "arm64", source/"Engine/main.m", "-o", macos/"GlowlineEngine")
run("xcrun", "swiftc", "-swift-version", "5", "-O", "-module-cache-path", work/"ModuleCache", "-target", "arm64-apple-macos15.0", "-framework", "AppKit", "-framework", "SwiftUI", "-framework", "ServiceManagement", "-framework", "CoreGraphics", *[source/name for name in ["Settings.swift", "SliderScale.swift", "Model.swift", "Interface.swift", "Recovery.swift", "App.swift"]], root/"Tests/test_recovery.swift", root/"Tests/test_model.swift", root/"Tests/test_appearance.swift", "-o", macos/"Glowline")
# Remove the retired scene resource when rebuilding an existing bundle.
(resources/"Noctiluca.metal").unlink(missing_ok=True)
shutil.copytree(root/"Resources", resources, dirs_exist_ok=True)
if not (resources/"AppIcon.icns").exists():
    run("xcrun", "swiftc", "-module-cache-path", work/"ModuleCache", source/"Icon.swift", "-o", work/"make-icon")
    run(work/"make-icon", work/"icon.png")
    iconset = work/"AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for size in [16, 32, 128, 256, 512]:
        for factor, suffix in [(1, ""), (2, "@2x")]:
            run("sips", "-z", size*factor, size*factor, work/"icon.png", "--out", iconset/f"icon_{size}x{size}{suffix}.png")
    run("iconutil", "-c", "icns", iconset, "-o", resources/"AppIcon.icns")
info = {"CFBundleIdentifier":"local.alex.Glowline", "CFBundleName":"Glowline", "CFBundleDisplayName":"Glowline", "CFBundleExecutable":"Glowline", "CFBundlePackageType":"APPL", "CFBundleShortVersionString":version["version"], "CFBundleVersion":str(version["build"]), "CFBundleDevelopmentRegion":"ru", "CFBundleLocalizations":["ru"], "CFBundleIconFile":"AppIcon", "LSMinimumSystemVersion":"15.0", "LSUIElement":True, "NSHighResolutionCapable":True, "LSApplicationCategoryType":"public.app-category.utilities", "NSPrincipalClass":"NSApplication"}
(contents/"Info.plist").write_bytes(plistlib.dumps(info))
run("xcrun", "swiftc", "-parse-as-library", "-module-cache-path", work/"ModuleCache", "-target", "arm64-apple-macos15.0", source/"SliderScale.swift", root/"Tests/test_slider_steps.swift", "-o", work/"test-slider-steps")
run(work/"test-slider-steps")
run("xcrun", "swiftc", "-parse-as-library", "-module-cache-path", work/"ModuleCache", "-target", "arm64-apple-macos15.0", source/"Settings.swift", root/"Tests/test_schedule.swift", "-o", work/"test-schedule")
run(work/"test-schedule")
run("xcrun", "clang", "-O2", "-Wall", "-Werror", "-Wno-unused-function", "-I", source/"Engine", root/"Tests/test_controls.c", "-o", work/"test-controls")
run(work/"test-controls")
run("xcrun", "clang", "-O2", "-Wall", "-Werror", "-Wno-unused-function", "-I", source/"Engine", root/"Tests/test_sampling.c", "-o", work/"test-sampling")
run(work/"test-sampling")
run("xcrun", "clang", "-O2", "-Wall", "-Werror", "-Wno-unused-function", "-I", source/"Engine", root/"Tests/test_early_response.c", "-o", work/"test-early-response")
run(work/"test-early-response")
run("xcrun", "clang", "-O2", "-Wall", "-Werror", "-I", source/"Engine", root/"Tests/test_controller.c", "-o", work/"test-controller")
run(work/"test-controller")
run("xcrun", "clang", "-fobjc-arc", "-O2", "-Wall", "-Werror", "-Wno-unused-function", "-mmacosx-version-min=15.0", "-I", source/"Engine", "-framework", "Foundation", "-framework", "ScreenCaptureKit", "-framework", "CoreGraphics", "-framework", "CoreMedia", "-framework", "CoreVideo", root/"Tests/test_capture.m", "-o", work/"test-capture")
run(work/"test-capture")
signing = ["codesign", "--force", "--sign", args.sign_identity]
if args.sign_identity != "-":
    signing += ["--options", "runtime", "--timestamp"]
run(*signing, "--identifier", "local.alex.Glowline.engine", macos/"GlowlineEngine")
run(*signing, "--identifier", info["CFBundleIdentifier"], app)
run("codesign", "--verify", "--deep", "--strict", app)
try:
    run(macos/"Glowline", "--self-test")
except subprocess.CalledProcessError:
    # Optimized Swift traps can omit assertion text; retain a CI stack without hiding failure.
    if os.environ.get("GITHUB_ACTIONS") == "true":
        subprocess.run(["rtk", "proxy", "xcrun", "lldb", "--batch", "--no-lldbinit",
                        "--one-line", "run", "--one-line-on-crash", "thread backtrace all",
                        "--", str(macos/"Glowline"), "--self-test"], timeout=60, check=False)
    raise
print(f"Built: {app}")
