#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MultiCodexPets"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-multi-codex-pets}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
MODE="${1:---notarize}"
case "$MODE" in
  --notarize|--local) ;;
  *) echo "usage: $0 [--notarize|--local]" >&2; exit 2 ;;
esac

if [[ "$MODE" != "--local" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ {print $2}')"
    IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')"
    if [[ "$IDENTITY_COUNT" != "1" ]]; then
      echo "Set CODE_SIGN_IDENTITY to the intended Developer ID Application identity; found $IDENTITY_COUNT." >&2
      exit 1
    fi
    SIGNING_IDENTITY="$IDENTITIES"
  fi

  codesign --verify --deep --strict "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
fi
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
if [[ "$MODE" == "--local" ]]; then DMG_PATH="$ROOT_DIR/dist/$APP_NAME-local.dmg"; fi
mkdir -p "$ROOT_DIR/.build"
LAYOUT_PYTHON="$ROOT_DIR/.build/dmg-tools/bin/python"
if [[ ! -x "$LAYOUT_PYTHON" ]]; then
  python3 -m venv "$ROOT_DIR/.build/dmg-tools"
fi
"$LAYOUT_PYTHON" -m pip install --quiet -r "$ROOT_DIR/script/requirements-dmg.txt"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.build/dmg.XXXXXX")"
MOUNT_POINT="$WORK_DIR/mount"
cleanup() {
  if mount | grep -Fq " on $MOUNT_POINT ("; then hdiutil detach "$MOUNT_POINT" -quiet || true; fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$WORK_DIR/contents"
ditto "$APP_BUNDLE" "$WORK_DIR/contents/$APP_NAME.app"
ln -s /Applications "$WORK_DIR/contents/Applications"
mkdir -p "$WORK_DIR/contents/.background"
swift "$ROOT_DIR/script/dmg_background.swift" "$WORK_DIR/contents/.background/installer.png" "$APP_BUNDLE"
hdiutil create -volname "$APP_NAME" -srcfolder "$WORK_DIR/contents" \
  -fs HFS+ -format UDRW "$WORK_DIR/installer.dmg"
hdiutil attach "$WORK_DIR/installer.dmg" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen -quiet
"$LAYOUT_PYTHON" "$ROOT_DIR/script/dmg_layout.py" "$MOUNT_POINT"
test -s "$MOUNT_POINT/.DS_Store"
sync
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert "$WORK_DIR/installer.dmg" -format UDZO -o "$WORK_DIR/final.dmg"
hdiutil verify "$WORK_DIR/final.dmg"
if [[ "$MODE" == "--local" ]]; then
  mv -f "$WORK_DIR/final.dmg" "$DMG_PATH"
  echo "Local preview DMG (not notarized): $DMG_PATH"
  exit 0
fi
DMG_OUTPUT="$DMG_PATH"
DMG_PATH="$WORK_DIR/final.dmg"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

RESULT="$ROOT_DIR/.build/notary/dmg-result.json"
mkdir -p "$(dirname "$RESULT")"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json >"$RESULT"
if [[ "$(plutil -extract status raw -o - "$RESULT")" != "Accepted" ]]; then
  echo "DMG notarization was not accepted. See $RESULT." >&2
  exit 1
fi
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
mv -f "$DMG_PATH" "$DMG_OUTPUT"
DMG_PATH="$DMG_OUTPUT"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$APP_NAME.dmg" >"$APP_NAME.dmg.sha256")
echo "Notarized DMG: $DMG_PATH"
