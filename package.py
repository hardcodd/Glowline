#!/usr/bin/env python3
"""Create and round-trip verify local ZIP/DMG packages; never publish or notarize."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
from typing import Union


def run(*args: Union[str, Path]) -> None:
    command = list(map(str, args))
    if " " in command[0]:
        command = ["python3", "-c", "import subprocess,sys; subprocess.run(sys.argv[1:],check=True)", *command]
    subprocess.run(["rtk", "proxy", *command], check=True)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(directory: Path) -> dict[str, str]:
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError("Unexpected symlink in package: " + str(path.relative_to(directory)))
        if path.is_file():
            result[path.relative_to(directory).as_posix()] = digest(path)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-mount", action="store_true", help="Also mount the DMG read-only and compare its files (requires disk-image access)")
    parser.add_argument("--skip-dmg", action="store_true", help="Create only ZIP (for CI without disk-image support)")
    args = parser.parse_args()
    if args.skip_dmg and args.verify_mount:
        parser.error("--verify-mount requires DMG creation")
    root = Path(__file__).resolve().parent
    app = root / "Glowline.app"
    version = json.loads((root / "VERSION.json").read_text())
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"]) != ("local.alex.Glowline", version["version"], str(version["build"])):
        raise SystemExit("Rebuild the application with the current VERSION.json before packaging")
    run("codesign", "--verify", "--deep", "--strict", app)
    # Only known bundle paths may enter a distribution. Never package local data.
    allowed = {"Contents/Info.plist", "Contents/MacOS/Glowline", "Contents/MacOS/GlowlineEngine", "Contents/Resources/AppIcon.icns", "Contents/Resources/ru.lproj/Localizable.strings", "Contents/_CodeSignature/CodeResources"}
    if set(files(app)) != allowed:
        raise SystemExit("Unexpected or missing application bundle files")
    output = root / "build/distribution"
    output.mkdir(parents=True, exist_ok=True)
    name = f"Glowline-{version['version']}-build{version['build']}-arm64"
    archive = output / (name + ".zip")
    image = output / (name + ".dmg")
    with tempfile.TemporaryDirectory(prefix="package-", dir=root / "build") as temporary:
        staging = Path(temporary) / "Glowline"
        staging.mkdir()
        run("ditto", app, staging / "Glowline.app")
        for filename in ("INSTALL.md", "INSTALL.ru.md", "lighting-test.html"):
            (staging / filename).write_bytes((root / "docs" / filename).read_bytes())
        if (root / "LICENSE").exists():
            (staging / "LICENSE").write_bytes((root / "LICENSE").read_bytes())
        manifest = {"version": version["version"], "build": version["build"], "architecture": "arm64", "bundleIdentifier": info["CFBundleIdentifier"], "files": files(staging)}
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        expected = files(staging)
        archive.unlink(missing_ok=True)
        run("ditto", "-c", "-k", "--sequesterRsrc", staging, archive)
        restored = Path(temporary) / "restored"
        run("ditto", "-x", "-k", archive, restored)
        if files(restored) != expected:
            raise SystemExit("Archive round-trip checksum mismatch")
        run("codesign", "--verify", "--deep", "--strict", restored / "Glowline.app")
        artifacts = [archive]
        if not args.skip_dmg:
            image.unlink(missing_ok=True)
            run("hdiutil", "create", "-srcfolder", staging, "-volname", "Glowline", "-format", "UDZO", image)
            run("hdiutil", "verify", image)
            if args.verify_mount:
                mount = Path(temporary) / "mounted"
                mount.mkdir()
                run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, image)
                try:
                    for relative, checksum in expected.items():
                        candidate = mount / relative
                        if not candidate.is_file() or digest(candidate) != checksum:
                            raise SystemExit("Disk image content mismatch: " + relative)
                    run("codesign", "--verify", "--deep", "--strict", mount / "Glowline.app")
                finally:
                    run("hdiutil", "detach", mount)
            artifacts.append(image)
        checksums = "".join(f"{digest(path)}  {path.name}\n" for path in artifacts)
        (output / "SHA256SUMS").write_text(checksums)
        print(checksums, end="")
    print("Verified local packages: " + str(output))


if __name__ == "__main__":
    main()
