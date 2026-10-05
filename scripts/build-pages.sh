#!/usr/bin/env bash
# Pages has no Flutter preset. Install the pinned SDK, then build the static UI.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  sdk_dir="$(mktemp -d "${TMPDIR:-/tmp}/nightcord-flutter.XXXXXX")"
  trap 'rm -rf -- "$sdk_dir"' EXIT
  git clone --depth 1 --branch "${FLUTTER_VERSION:-3.47.5}" \
    https://github.com/flutter/flutter.git "$sdk_dir/flutter"
  export PATH="$sdk_dir/flutter/bin:$PATH"
fi

bash scripts/fetch-fonts.sh
python3 scripts/build-web.py
