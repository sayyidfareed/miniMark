#!/usr/bin/env bash
# Mac App Store archive for miniMark. Run it on a Mac whose Xcode is signed in to the Ideius LLC developer
# account (Xcode, Settings, Accounts). It signs with Xcode's cloud-managed certificates; no key or password
# is read or stored by this script.
#
#   release/archive-and-upload.sh export     builds, signs and writes a package under build/appstore/ (nothing is sent)
#   release/archive-and-upload.sh upload     the same, then uploads the build to App Store Connect
#
# BUILD=2 release/archive-and-upload.sh upload    sets the build number (each upload of a version needs a new one)
# DRY=1 release/archive-and-upload.sh export      test mode: ad-hoc signing, archive only (used by the M3 build helper)
set -euo pipefail

MODE="${1:-export}"
[[ "$MODE" == "export" || "$MODE" == "upload" ]] || { echo "usage: $0 export|upload"; exit 2; }
TEAM="TTM4RN4K88"
BUILD="${BUILD:-1}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -d miniMark.xcodeproj ]] || { echo "miniMark.xcodeproj not found next to this script's folder"; exit 2; }

STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="$PWD/build/appstore/$STAMP"
mkdir -p "$OUT"
echo "Output folder: $OUT"

SIGNING=(DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates)
if [[ "${DRY:-0}" == "1" ]]; then
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

echo "== 1/3 Archive (version from the project, build $BUILD)"
xcodebuild -project miniMark.xcodeproj -scheme miniMark -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/miniMark.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD" "${SIGNING[@]}" archive

APP="$OUT/miniMark.xcarchive/Products/Applications/miniMark.app"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/miniMark")"
echo "version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"

DEST="export"
[[ "$MODE" == "upload" ]] && DEST="upload"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$OUT/ExportOptions.plist"

if [[ "${DRY:-0}" == "1" ]]; then
  echo "DRY run: archive and export options checked; not signing or exporting."
  exit 0
fi

echo "== 2/3 Sign and $MODE"
xcodebuild -exportArchive -archivePath "$OUT/miniMark.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates

echo "== 3/3 Done"
ls -la "$OUT/export" 2>/dev/null || true
if [[ "$MODE" == "upload" ]]; then
  echo "Uploaded. In App Store Connect the build appears under the version after Apple finishes processing (usually minutes)."
else
  echo "Signed package written. Nothing was sent to Apple."
fi
