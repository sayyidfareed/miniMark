#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/miniMark.xcodeproj"
SCHEME="miniMark"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
STAGING="$ROOT_DIR/build/dmg"
OUTPUT="${OUTPUT:-$ROOT_DIR/build/miniMark.dmg}"
APP_SOURCE="$DERIVED_DATA/Build/Products/$CONFIGURATION/miniMark.app"
APP_STAGED="$STAGING/miniMark.app"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_STYLE="${CODE_SIGN_STYLE:-Manual}"
VOLUME_NAME="miniMark"

detach_stale_volumes() {
  local volume
  shopt -s nullglob
  for volume in /Volumes/"$VOLUME_NAME" /Volumes/"$VOLUME_NAME"\ [0-9]*; do
    if [[ -d "$volume/miniMark.app" && -L "$volume/Applications" ]]; then
      if ! hdiutil detach "$volume" >/dev/null; then
        echo "Could not eject stale installer volume: $volume" >&2
        echo "Close any Finder windows or running miniMark copy from that volume, eject it, then run this script again." >&2
        exit 1
      fi
    fi
  done
  shopt -u nullglob
}

verify_dmg_contents() {
  local verify_mount="$ROOT_DIR/build/dmg-verify"
  local staged_hash mounted_hash

  rm -rf "$verify_mount"
  mkdir -p "$verify_mount"

  hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$verify_mount" \
    "$OUTPUT" >/dev/null

  if ! staged_hash="$(shasum -a 256 "$APP_STAGED/Contents/MacOS/miniMark" | awk '{print $1}')"; then
    hdiutil detach "$verify_mount" >/dev/null || true
    rmdir "$verify_mount" 2>/dev/null || true
    echo "DMG verification failed: could not hash staged app." >&2
    exit 1
  fi

  if ! mounted_hash="$(shasum -a 256 "$verify_mount/miniMark.app/Contents/MacOS/miniMark" | awk '{print $1}')"; then
    hdiutil detach "$verify_mount" >/dev/null || true
    rmdir "$verify_mount" 2>/dev/null || true
    echo "DMG verification failed: could not hash mounted app." >&2
    exit 1
  fi

  hdiutil detach "$verify_mount" >/dev/null || true
  rmdir "$verify_mount" 2>/dev/null || true

  if [[ "$staged_hash" != "$mounted_hash" ]]; then
    echo "DMG verification failed: mounted app does not match staged app." >&2
    echo "Staged: $staged_hash" >&2
    echo "Mounted: $mounted_hash" >&2
    exit 1
  fi

  echo "Verified DMG contents match staged app."
}

XCODEBUILD_SETTINGS=(
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  CODE_SIGN_STYLE="$SIGNING_STYLE"
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCODEBUILD_SETTINGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  XCODEBUILD_SETTINGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp")
fi

if [[ -n "${RELEASE_VERSION:-}" ]]; then
  XCODEBUILD_SETTINGS+=(MARKETING_VERSION="$RELEASE_VERSION")
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  XCODEBUILD_SETTINGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi

mkdir -p "$(dirname "$OUTPUT")"
detach_stale_volumes
rm -rf "$STAGING"
rm -f "$OUTPUT"
mkdir -p "$STAGING"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  "${XCODEBUILD_SETTINGS[@]}" \
  build

rm -rf "$APP_STAGED" "$STAGING/Applications"
ditto "$APP_SOURCE" "$APP_STAGED"
touch "$APP_STAGED"
ln -sfn /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$OUTPUT"

verify_dmg_contents

if [[ "${SIGN_DMG:-0}" == "1" && "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$OUTPUT"
fi

echo "Created $OUTPUT"
