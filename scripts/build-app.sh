#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c debug
GRAPHENE_BIN_DIR="$(swift build -c debug --show-bin-path)"
GRAPHENE_APP_DIR="${GRAPHENE_APP_DIR:-$PWD/.build/Graphene.app}"
# Never replace the binary under a running instance that uses the real profile:
# macOS kills a process whose executable is rewritten or re-signed beneath it.
for pid in $(pgrep -f "$GRAPHENE_APP_DIR/Contents/MacOS/Graphene" || true); do
  if ! ps -E -o command= -p "$pid" | grep -q "GRAPHENE_DATA_DIR="; then
    echo "error: Graphene (pid $pid) is running from $GRAPHENE_APP_DIR with the real profile." >&2
    echo "Quit it first, or build elsewhere: GRAPHENE_APP_DIR=\$PWD/.build/Graphene-dev.app $0" >&2
    exit 1
  fi
done
mkdir -p "$GRAPHENE_APP_DIR/Contents/MacOS" "$GRAPHENE_APP_DIR/Contents/Resources"
cp "$GRAPHENE_BIN_DIR/Graphene" "$GRAPHENE_APP_DIR/Contents/MacOS/Graphene"
cp -R "$GRAPHENE_BIN_DIR/Graphene_Graphene.bundle/" "$GRAPHENE_APP_DIR/Contents/Resources/"
swift scripts/make-icon.swift "$PWD/.build/Graphene.iconset"
iconutil -c icns "$PWD/.build/Graphene.iconset" -o "$GRAPHENE_APP_DIR/Contents/Resources/Graphene.icns"
cat > "$GRAPHENE_APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Graphene</string>
<key>CFBundleDisplayName</key><string>Graphene</string>
<key>CFBundleIdentifier</key><string>com.graphene.browser</string>
<key>CFBundleIconFile</key><string>Graphene</string>
<key>CFBundleExecutable</key><string>Graphene</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>Web URL</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
</dict></array>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.graphene.browser.note-reference</string>
<key>UTTypeDescription</key><string>Graphene note</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Websites can use your camera only after you allow access.</string>
<key>NSMicrophoneUsageDescription</key><string>Websites can use your microphone only after you allow access.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - "$GRAPHENE_APP_DIR"
printf '%s\n' "$GRAPHENE_APP_DIR"
