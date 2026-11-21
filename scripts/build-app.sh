#!/usr/bin/env bash
# Builds Genesis and creates the build/Genesis.app bundle.
#   ./scripts/build-app.sh            this Mac's architecture
#   ./scripts/build-app.sh universal  Apple silicon + Intel (needs full Xcode)
#   ./scripts/build-app.sh install    like the default, then copies the app to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-native}"
APP="build/Genesis.app"

if [[ "$MODE" == "universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Genesis" "$APP/Contents/MacOS/Genesis"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: enough to run the app on your own Mac.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "codesign failed; the app still runs on this Mac."

echo "Built $APP"

if [[ "$MODE" == "install" ]]; then
    rm -rf "/Applications/Genesis.app"
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Genesis.app"
fi
