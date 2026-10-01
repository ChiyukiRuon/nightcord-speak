#!/usr/bin/env bash
#
# Downloads the UI fonts into apps/client/assets/fonts/.
#
# These files are deliberately **not** in the repository. They are ~20 MB of
# binary, and a git history never forgets: every future clone would carry them
# forever, for a payload that never changes and is one HTTP request away. See
# `docs/UI字体规范.md` §1 for what is bundled and why, and `AGENTS.md` §3.2 for
# this script's place in the setup steps.
#
# The consequence to know about: `pubspec.yaml` declares these files as font
# assets, so **a build without them fails**, loudly and with a path. That is the
# intended behaviour — the alternative (not declaring them) would silently
# render every screen in the system font, which is exactly the platform
# inconsistency the specification exists to remove.
#
# Usage:
#   scripts/fetch-fonts.sh          # download what is missing
#   scripts/fetch-fonts.sh --check  # verify only; exits non-zero if incomplete

set -euo pipefail

cd "$(dirname "$0")/.."

FONT_DIR="apps/client/assets/fonts"

# jsDelivr first, raw.githubusercontent second.
#
# Not a preference: measured from a machine where the direct GitHub host
# transferred the 17 MB Simplified Chinese font at roughly 16 KB/s and stalled
# mid-file repeatedly, while jsDelivr served it at over 1 MB/s. The second URL
# is the canonical source and stays as a fallback for anywhere jsDelivr is
# blocked.
JSDELIVR="https://cdn.jsdelivr.net/gh/google/fonts@main"
GITHUB="https://raw.githubusercontent.com/google/fonts/main"

# name|sha256|path-within-the-repo
# One CJK face per language the app ships, because they are not
# interchangeable: the same ideograph is drawn with different shapes in
# Simplified Chinese, Traditional Chinese, Japanese and Korean, and a reader of
# one notices immediately when handed another's. `docs/UI字体规范.md` §2 is where
# that rule lives; the cost — about 50 MB of fonts before a build — is the
# reason this script exists rather than the files themselves.
FILES=(
	"NotoSans-Variable.ttf|bfb7bb691513f12e734dc346c03a03f784912432d7e3fa8e56efcf906fe86b3d|ofl/notosans/NotoSans%5Bwdth%2Cwght%5D.ttf"
	"NotoSansSC-Variable.ttf|a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da|ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
	"NotoSansTC-Variable.ttf|864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f|ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf"
	"NotoSansJP-Variable.ttf|c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f|ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
	"NotoSansKR-Variable.ttf|194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252|ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf"
	"OFL.txt|1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9|ofl/notosanssc/OFL.txt"
)

check_only=false
if [[ "${1:-}" == "--check" ]]; then
	check_only=true
fi

mkdir -p "$FONT_DIR"

# sha256 of a file, or empty when it is not there.
hash_of() {
	if [[ -f "$1" ]]; then
		sha256sum "$1" | cut -d' ' -f1
	else
		echo ""
	fi
}

fetch() {
	local name="$1" want="$2" path="$3" url
	local target="$FONT_DIR/$name"
	local have
	have="$(hash_of "$target")"

	if [[ "$have" == "$want" ]]; then
		echo "ok       $name"
		return 0
	fi

	if $check_only; then
		echo "missing  $name" >&2
		return 1
	fi

	for url in "$JSDELIVR/$path" "$GITHUB/$path"; do
		echo "fetching $name"
		# `--retry-all-errors` because the failure here is a reset connection
		# rather than an HTTP status, which curl does not retry by default.
		if curl -sSL --fail --retry 3 --retry-all-errors --retry-delay 2 \
			--max-time 600 -o "$target" "$url" && [[ "$(hash_of "$target")" == "$want" ]]; then
			echo "ok       $name"
			return 0
		fi
	done

	# A wrong hash is worse than no file: it means the upstream moved or the
	# transfer was corrupted, and a font that renders *almost* right is harder
	# to notice than one that is absent.
	rm -f "$target"
	echo "FAILED   $name — could not reach either source, or the checksum did not match" >&2
	return 1
}

status=0
for entry in "${FILES[@]}"; do
	IFS='|' read -r name want path <<<"$entry"
	fetch "$name" "$want" "$path" || status=1
done

if (( status != 0 )); then
	echo >&2
	echo "One or more fonts are missing from $FONT_DIR." >&2
	echo "Run scripts/fetch-fonts.sh, or builds that declare them will fail." >&2
fi
exit $status
