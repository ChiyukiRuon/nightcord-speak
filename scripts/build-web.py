#!/usr/bin/env python3
"""Pass deployment environment to Flutter without putting tokens in argv."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


def main():
    root = Path(__file__).resolve().parent.parent
    url = os.environ.get("NIGHTCORD_GATEWAY_URL", os.environ.get("NIGHTCORD_GATEWAY", "")).strip()
    token = os.environ.get("NIGHTCORD_GATEWAY_TOKEN", "")
    if url:
        try:
            parsed = urlsplit(url)
            valid = (parsed.scheme in ("ws", "wss") and parsed.hostname
                     and parsed.port != 0 and parsed.username is None
                     and not parsed.query and not parsed.fragment)
        except ValueError:
            valid = False
        if not valid:
            sys.exit("NIGHTCORD_GATEWAY_URL must be a ws/wss address without credentials, query or fragment")
        if os.environ.get("CF_PAGES") and parsed.scheme != "wss":
            sys.exit("Cloudflare Pages requires NIGHTCORD_GATEWAY_URL to use wss://")
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("Flutter is missing; use scripts/build-pages.sh on Cloudflare Pages")
    # NamedTemporaryFile uses owner-only permissions on Unix. Keep the name,
    # not its contents, in Flutter's command line and always remove it.
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", encoding="utf-8", delete=False) as file:
        json.dump({"NIGHTCORD_GATEWAY_URL": url, "NIGHTCORD_GATEWAY_TOKEN": token}, file)
        config = Path(file.name)
    try:
        return subprocess.call(
            [flutter, "build", "web", "--release", f"--dart-define-from-file={config}"],
            cwd=root / "apps/client",
        )
    finally:
        config.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
