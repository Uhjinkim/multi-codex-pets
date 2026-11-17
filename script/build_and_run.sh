#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MultiCodexPets"
APP_VERSION="0.1.0"
BUILD_VERSION="1"
APP_ICON_NAME="CompanionPets-v1"
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
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build|build|--install|install|--notarize|notarize|--release|release) ;;
  *)
    echo "usage: $0 [run|--build|--release|--install|--notarize|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-multi-codex-pets}"
if [[ "$MODE" == "--notarize" || "$MODE" == "notarize" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ {print $2}')"
    IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')"
    if [[ "$IDENTITY_COUNT" != "1" ]]; then
      echo "Set CODE_SIGN_IDENTITY to the intended Developer ID Application identity; found $IDENTITY_COUNT." >&2
      exit 1
    fi
    SIGNING_IDENTITY="$IDENTITIES"
  fi
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
fi

swift test
BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--install" || "$MODE" == "install" || "$MODE" == "--notarize" || "$MODE" == "notarize" || "$MODE" == "--release" || "$MODE" == "release" ]]; then
  BUILD_CONFIGURATION="release"
fi
swift build --configuration "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

ICON_BUILD_DIR="$ROOT_DIR/.build/app-icon"
mkdir -p "$ICON_BUILD_DIR"
xcrun actool --compile "$ICON_BUILD_DIR" --platform macosx   --minimum-deployment-target "$MIN_SYSTEM_VERSION" --app-icon "$APP_ICON_NAME"   --output-partial-info-plist "$ICON_BUILD_DIR/partial-info.plist"   "$ROOT_DIR/Design/AppIcon/$APP_ICON_NAME.icon"

case "$MODE" in
  --build|build|--release|release|--install|install|--notarize|notarize) ;;
  *) pkill -x "$APP_NAME" >/dev/null 2>&1 || true ;;
esac
mkdir -p "$APP_MACOS"
mkdir -p "$APP_CONTENTS/Resources"
RESOURCE_BUNDLE="$(dirname "$BUILD_BINARY")/MultiCodexPets_MultiCodexPets.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing app resources: $RESOURCE_BUNDLE" >&2
  exit 1
fi
rsync -a "$RESOURCE_BUNDLE/" "$APP_CONTENTS/Resources/MultiCodexPets_MultiCodexPets.bundle/"
cp "$ICON_BUILD_DIR/Assets.car" "$ICON_BUILD_DIR/$APP_ICON_NAME.icns" "$APP_CONTENTS/Resources/"
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
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>CFBundleIconName</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
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

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ "$MODE" == "--notarize" || "$MODE" == "notarize" ]]; then
  SIGNATURE_INFO="$(codesign --display --verbose=4 "$APP_BUNDLE" 2>&1)"
  if [[ "$SIGNATURE_INFO" != *"Authority=Developer ID Application:"* ]]; then
    echo "Notarization requires a Developer ID Application signature." >&2
    exit 1
  fi
  NOTARY_DIR="$ROOT_DIR/.build/notary"
  mkdir -p "$NOTARY_DIR"
  SUBMISSION="$NOTARY_DIR/$APP_NAME.zip"
  RESULT="$NOTARY_DIR/result.json"
  ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMISSION"
  xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json >"$RESULT"
  if [[ "$(plutil -extract status raw -o - "$RESULT")" != "Accepted" ]]; then
    echo "Notarization was not accepted. See $RESULT; the installed app was not replaced." >&2
    exit 1
  fi
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
  ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-$APP_VERSION.zip"
  echo "Notarized archive: $DIST_DIR/$APP_NAME-$APP_VERSION.zip"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build|--release|release)
    echo "Built $APP_BUNDLE"
    ;;
  --install|install|--notarize|notarize)
    INSTALL_BUNDLE="/Applications/$APP_NAME.app"
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    mkdir -p "$INSTALL_BUNDLE"
    rsync -a --delete "$APP_BUNDLE/" "$INSTALL_BUNDLE/"
    codesign --verify --deep --strict "$INSTALL_BUNDLE"
    APP_BUNDLE="$INSTALL_BUNDLE"
    touch "$APP_BUNDLE"
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
    echo "usage: $0 [run|--build|--release|--install|--notarize|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
