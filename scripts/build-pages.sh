#!/usr/bin/env bash
# Pages 未预装 Flutter 时，安装固定版本 SDK，再构建静态网页。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  # EO 的工作目录与 TMPDIR 都可能位于 /dev/shm；SDK 单独使用 /tmp。
  sdk_dir="$(mktemp -d "${NIGHTCORD_FLUTTER_TMPDIR:-/tmp}/nightcord-flutter.XXXXXX")"
  trap 'rm -rf -- "$sdk_dir"' EXIT
  # 使用与 Flutter 相同的调用方式，先确认 chmod 可执行，再下载 SDK。
  if ! find "$sdk_dir" -maxdepth 0 -type d -exec chmod 755 {} +; then
    echo "Cannot execute chmod during Flutter setup. Check the build environment permissions or deploy a prebuilt web artifact." >&2
    exit 1
  fi
  if [[ "$(uname -s)" == "Linux" ]]; then
    # 直接执行原生程序，检测 SDK 所在挂载点是否允许执行二进制文件。
    cp /bin/true "$sdk_dir/exec-check"
    if ! "$sdk_dir/exec-check"; then
      echo "Flutter SDK directory does not allow native executables: $sdk_dir. Set NIGHTCORD_FLUTTER_TMPDIR to an executable filesystem." >&2
      exit 1
    fi
    rm -f -- "$sdk_dir/exec-check"
  fi
  echo "Installing Flutter SDK in $sdk_dir"
  git clone --depth 1 --branch "${FLUTTER_VERSION:-3.47.5}" \
    https://github.com/flutter/flutter.git "$sdk_dir/flutter"
  export PATH="$sdk_dir/flutter/bin:$PATH"
fi

bash scripts/fetch-fonts.sh
python3 scripts/build-web.py
