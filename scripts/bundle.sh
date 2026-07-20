#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/HomeWave.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HomeWave "$APP/Contents/MacOS/HomeWave"
cp Sources/HomeWave/Info.plist "$APP/Contents/Info.plist"
if [ -d web ]; then cp -R web "$APP/Contents/Resources/web"; fi
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
