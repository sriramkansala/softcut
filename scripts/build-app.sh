#!/bin/bash
# Builds Softcut.app (release) into ./dist. Usage: scripts/build-app.sh
# Signs with the first "Apple Development" identity if one exists, otherwise ad-hoc.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Softcut.app"
BUNDLE_ID="app.glide.Glide"

swift build -c release --product Glide

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Glide" "$APP/Contents/MacOS/Glide"

# The 3D devices the Mockups tab offers. The .blend sources and the textures they were built from stay in the project;
# the app only needs the exports, the studio light and the pictures in the tab.
if [ -d Mockups ]; then
    rsync -a --exclude '*.blend' --exclude '*.blend1' --exclude 'keyboard.png' --exclude 'lens.png' --exclude 'grille-*.png' Mockups/ "$APP/Contents/Resources/Mockups/"
else
    echo "No Mockups folder; building without the 3D devices. See the README to make them."
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>Softcut</string>
    <key>CFBundleDisplayName</key><string>Softcut</string>
    <key>CFBundleExecutable</key><string>Glide</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Softcut records your voice when the Microphone option is on.</string>
    <key>NSCameraUsageDescription</key>
    <string>Softcut shows your webcam in the video when the Webcam option is on.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Softcut turns what you said into captions. Recognition happens on this Mac.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Softcut records system audio when the System audio option is on.</string>
</dict>
</plist>
PLIST

cat > dist/Glide.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.device.camera</key><true/>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Screen Recording permission across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)
if [ -n "${IDENTITY:-}" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --options runtime --entitlements dist/Glide.entitlements --sign "$IDENTITY" "$APP"
else
    echo "No developer identity found; signing ad-hoc (Screen Recording permission resets after each rebuild)."
    codesign --force --entitlements dist/Glide.entitlements --sign - "$APP"
fi

echo "Built $APP"
