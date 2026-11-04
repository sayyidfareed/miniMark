#!/usr/bin/env bash
# Installs the current miniMark Release build on this Mac for hands-on testing (signed ad hoc, sandboxed,
# same code as the App Store build). An existing /Applications/miniMark.app is moved, not deleted, to
# ~/miniMark-rollback/<time>/ so it can be put back. Nothing is uploaded anywhere.
set -euo pipefail
ROOT="$(pwd)"
[[ -d "$ROOT/miniMark.xcodeproj" ]] || { echo "run from the repo root"; exit 2; }
STAMP="$(date +%Y%m%dT%H%M%S)"
DD="${TMPDIR:-/tmp}"; DD="${DD%/}/minimark-install-$STAMP"
mkdir -p "$DD"
echo "commit: $(git rev-parse --short HEAD)"
xcodebuild -project miniMark.xcodeproj -scheme miniMark -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DD" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build > "$DD/build.log" 2>&1 \
  || { tail -30 "$DD/build.log"; exit 1; }
APP="$DD/Build/Products/Release/miniMark.app"
codesign --verify --deep --strict "$APP"
echo "built: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"), $(lipo -archs "$APP/Contents/MacOS/miniMark")"
if pgrep -x miniMark >/dev/null; then echo "miniMark is running; quit it first, then run again"; exit 3; fi
if [[ -d /Applications/miniMark.app ]]; then
  BACK="$HOME/miniMark-rollback/$STAMP"; mkdir -p "$BACK"
  mv /Applications/miniMark.app "$BACK/miniMark.app"
  echo "previous copy moved to $BACK/miniMark.app"
fi
ditto "$APP" /Applications/miniMark.app
xattr -dr com.apple.quarantine /Applications/miniMark.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/miniMark.app || true
touch /Applications/miniMark.app
echo "installed: /Applications/miniMark.app"
if [[ "$DD" == "${TMPDIR:-/tmp}"* && "$(basename "$DD")" == "minimark-install-$STAMP" ]]; then rm -rf -- "$DD"; fi
