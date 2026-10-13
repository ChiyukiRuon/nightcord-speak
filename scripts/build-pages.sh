#!/usr/bin/env bash
# Pages 未预装 Flutter 时，安装固定版本 SDK，再构建静态网页。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  # 在工作目录安装 SDK，避免 TMPDIR 指向禁止执行程序的 /dev/shm 等挂载点。
  sdk_dir="$(mktemp -d "$PWD/.nightcord-flutter.XXXXXX")"
  trap 'rm -rf -- "$sdk_dir"' EXIT
  echo "Installing Flutter SDK in $sdk_dir"
  git clone --depth 1 --branch "${FLUTTER_VERSION:-3.47.5}" \
    https://github.com/flutter/flutter.git "$sdk_dir/flutter"
  export PATH="$sdk_dir/flutter/bin:$PATH"
fi

bash scripts/fetch-fonts.sh
python3 scripts/build-web.py
