#!/bin/bash
# Assembles and signs dist/AI Pulse.app from the SwiftPM build products.
#
# Signing with a real Apple Development identity (not ad-hoc) is what makes
# the Keychain stop re-prompting on every rebuild: the keychain item's ACL
# matches the app's designated requirement (identifier + team), which is
# stable across builds, whereas ad-hoc signatures change per binary.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="dist/AI Pulse.app"
VERSION="0.1.0"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"

cp ".build/$CONFIG/AIPulseApp" "$APP/Contents/MacOS/AIPulse"
# Embed the CLI so hook configs can reference a stable path inside the app.
# It lives in Helpers/, NOT MacOS/: "AIPulse" and "aipulse" are the same path
# on case-insensitive filesystems and the CLI would clobber the app binary.
cp ".build/$CONFIG/aipulse" "$APP/Contents/Helpers/aipulse"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>me.leog.aipulse</string>
    <key>CFBundleName</key>
    <string>AI Pulse</string>
    <key>CFBundleDisplayName</key>
    <string>AI Pulse</string>
    <key>CFBundleExecutable</key>
    <string>AIPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Leo Giovanetti</string>
</dict>
</plist>
PLIST

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --identifier me.leog.aipulse.cli "$APP/Contents/Helpers/aipulse"
    codesign --force --sign "$IDENTITY" --identifier me.leog.aipulse "$APP"
else
    echo "WARNING: no Apple Development identity found; ad-hoc signing." >&2
    echo "Keychain will re-prompt after every rebuild until a real identity is used." >&2
    codesign --force --sign - "$APP/Contents/Helpers/aipulse"
    codesign --force --sign - "$APP"
fi

codesign --verify --deep "$APP"
echo "Built: $APP"
