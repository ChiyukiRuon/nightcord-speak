#!/bin/sh
set -eu

# Launch Services runs this separately signed helper after the sandboxed client
# exits. It is independent of Flutter and the Rust core.
UPDATER_SOURCE="$PROJECT_DIR/Updater"
UPDATER_BUNDLE="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Helpers/NightcordUpdater.app"
UPDATER_CONTENTS="$UPDATER_BUNDLE/Contents"
mkdir -p "$UPDATER_CONTENTS/MacOS"
cat > "$UPDATER_CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chiyukiruon.nightcordClient.updater</string>
<key>CFBundleName</key><string>NightcordUpdater</string>
<key>CFBundleExecutable</key><string>NightcordUpdater</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>10.15.4</string>
</dict></plist>
PLIST
UPDATER_ARCH=$(uname -m)
xcrun swiftc -parse-as-library -O -target "$UPDATER_ARCH-apple-macosx10.15.4" \
  "$UPDATER_SOURCE/UpdateTransaction.swift" "$UPDATER_SOURCE/Main.swift" \
  -o "$UPDATER_CONTENTS/MacOS/NightcordUpdater"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$UPDATER_BUNDLE"
