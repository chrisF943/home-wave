#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Preflight: fail fast with a readable message instead of a cryptic toolchain
# error, or a build that succeeds and then can't launch.
if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: HomeWave is macOS-only (found $(uname -s))." >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "error: no Swift toolchain found. Install the Command Line Tools with:" >&2
    echo "         xcode-select --install" >&2
    exit 1
fi
OS_VERSION="$(sw_vers -productVersion)"
if [ "$(printf '%s\n14.2\n' "$OS_VERSION" | sort -V | head -1)" != "14.2" ]; then
    echo "error: HomeWave needs macOS 14.2 or later (found $OS_VERSION)." >&2
    echo "       The Core Audio process-tap API it captures system audio with" >&2
    echo "       does not exist on earlier versions." >&2
    exit 1
fi

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
