#!/bin/bash
# Builds R2 Mapper.app and signs it with your Apple Development identity so
# macOS permissions (Input Monitoring, Accessibility) survive rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/R2 Mapper.app"
# First Apple Development identity by hash (names can be ambiguous); ad-hoc if none.
DEFAULT_IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
IDENTITY="${SIGN_IDENTITY:-${DEFAULT_IDENTITY:--}}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos14.0 Sources/Ring.swift Sources/Config.swift Sources/Output.swift Sources/EventFilter.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/R2Mapper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.r2mapper</string>
    <key>CFBundleName</key><string>R2 Mapper</string>
    <key>CFBundleExecutable</key><string>R2Mapper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
