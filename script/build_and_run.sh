#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MultiCodexPets"
BUNDLE_ID="com.opensource.MultiCodexPets"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build|build|--install|install) ;;
  *)
    echo "usage: $0 [run|--build|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

swift test
BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--install" || "$MODE" == "install" ]]; then
  BUILD_CONFIGURATION="release"
fi
swift build --configuration "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

if [[ "$MODE" != "--build" && "$MODE" != "build" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
mkdir -p "$APP_MACOS"
mkdir -p "$APP_CONTENTS/Resources"
RESOURCE_BUNDLE="$(dirname "$BUILD_BINARY")/MultiCodexPets_MultiCodexPets.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing app resources: $RESOURCE_BUNDLE" >&2
  exit 1
fi
rsync -a "$RESOURCE_BUNDLE/" "$APP_CONTENTS/Resources/MultiCodexPets_MultiCodexPets.bundle/"
cp "$BUILD_BINARY" "$APP_BINARY.new"
chmod +x "$APP_BINARY.new"
mv -f "$APP_BINARY.new" "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>ko</string></array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    echo "Built $APP_BUNDLE"
    ;;
  --install|install)
    INSTALL_BUNDLE="/Applications/$APP_NAME.app"
    mkdir -p "$INSTALL_BUNDLE"
    rsync -a --delete "$APP_BUNDLE/" "$INSTALL_BUNDLE/"
    codesign --verify --deep --strict "$INSTALL_BUNDLE"
    APP_BUNDLE="$INSTALL_BUNDLE"
    open_app
    echo "Installed $INSTALL_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
