#!/bin/zsh
# Builds Proteus.app next to this script.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
APP="Proteus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Proteus "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/TVDLogo.pdf Resources/SplashArt.jpg "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Proteus</string>
    <key>CFBundleIdentifier</key><string>com.tsevis.proteus</string>
    <key>CFBundleExecutable</key><string>Proteus</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
