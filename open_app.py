#!/usr/bin/env python3
"""Open the installed app, stopping only the preserved rollback controller."""
from pathlib import Path
import json
import os
import signal
import subprocess
import time

root = Path(__file__).resolve().parent
status = Path.home() / "Library/Application Support/Glowline/previous-controller-status.json"
try:
    pid = int(json.loads(status.read_text())["pid"])
    result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True)
    if result.stdout.strip() == str(root / "PreviousController/ambilight-srgb"):
        os.kill(pid, signal.SIGTERM)
        for _ in range(30):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
except (OSError, ValueError, KeyError):
    pass
subprocess.run(["/usr/bin/open", str(Path.home() / "Applications/Glowline.app")], check=True)
