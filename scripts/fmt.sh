#!/usr/bin/env bash
#
# Formats (or checks) only this project's crates.
#
# `cargo fmt --all` cannot be used: it also formats local path dependencies,
# which would reformat the vendored tsclientlib using our rustfmt.toml and then
# fail its own style check. rustfmt's `ignore` option does not help because it
# is nightly-only and does not apply to explicitly-passed files.
#
# Usage:
#   scripts/fmt.sh          # apply formatting
#   scripts/fmt.sh --check  # verify, for CI

set -euo pipefail

cd "$(dirname "$0")/.."

# Maintained by hand: every workspace member except the ones under vendor/.
PACKAGES=(
	-p ts-model
	-p ts-events
	-p ts-protocol
	-p ts-session
	-p ts-identity
	-p ts-protocol-ts3
	-p ts-protocol-ts6
	-p ts-protocol-tsclient
	-p ts-audio
	-p ts-core
	-p ts-ffi
	-p nightcord-cli
)

if [[ "${1:-}" == "--check" ]]; then
	cargo fmt "${PACKAGES[@]}" -- --check
else
	cargo fmt "${PACKAGES[@]}"
fi
