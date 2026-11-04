#!/usr/bin/env bash
# Mac App Store archive for miniMark, signed for the Ideius LLC team with Xcode's cloud-managed certificates.
# Two ways to authenticate with Apple, picked automatically:
#   - if ~/.appstoreconnect/minimark.conf exists (KEY_ID=... and ISSUER_ID=...) and the matching
#     ~/.appstoreconnect/AuthKey_<KEY_ID>.p8 file is there, an App Store Connect API key is used (headless Mac);
#   - otherwise the Apple account signed in to Xcode is used (Xcode, Settings, Accounts).
# The script only passes the key's path and ids to xcodebuild; it never prints or copies the key.
#
#   scripts/mas-archive-and-upload.sh export     builds, signs and writes a package under build/appstore/ (nothing is sent)
#   scripts/mas-archive-and-upload.sh upload     the same, then uploads the build to App Store Connect
#
# BUILD=2 scripts/mas-archive-and-upload.sh upload    sets the build number (each upload of a version needs a new one)
# DRY=1 scripts/mas-archive-and-upload.sh export      test mode: ad-hoc signing, archive only (used by the M3 build helper)
set -euo pipefail

MODE="${1:-export}"
[[ "$MODE" == "export" || "$MODE" == "upload" ]] || { echo "usage: $0 export|upload"; exit 2; }
TEAM="TTM4RN4K88"
BUILD="${BUILD:-1}"

# The approval helper runs a copy of this script with the repo as the working directory; run by hand it sits in scripts/.
[[ -d miniMark.xcodeproj ]] || cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -d miniMark.xcodeproj ]] || { echo "miniMark.xcodeproj not found; run from the repo folder"; exit 2; }

STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="$PWD/build/appstore/$STAMP"
mkdir -p "$OUT"
echo "Output folder: $OUT"

# The archive itself is signed ad hoc: a headless Mac has no development certificate and cannot unlock a
# keychain without someone at the screen. The export step re-signs it for the Mac App Store with Apple's
# cloud-managed distribution certificate, which needs no private key on this Mac.
SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="$TEAM")
AUTH=()
CONF="$HOME/.appstoreconnect/minimark.conf"
if [[ -f "$CONF" ]]; then
  KEY_ID=""; ISSUER_ID=""
  # shellcheck disable=SC1090
  . "$CONF"
  KEY_FILE="$HOME/.appstoreconnect/AuthKey_${KEY_ID}.p8"
  if [[ -n "$KEY_ID" && -n "$ISSUER_ID" && -f "$KEY_FILE" ]]; then
    AUTH=(-authenticationKeyPath "$KEY_FILE" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")
    echo "Authenticating with the App Store Connect API key $KEY_ID"
  else
    echo "$CONF exists but the key id, issuer id or key file is missing"; exit 2
  fi
else
  echo "No API key configured; using the Apple account signed in to Xcode"
fi
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
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "== 3/3 Done"
ls -la "$OUT/export" 2>/dev/null || true
if [[ "$MODE" == "upload" ]]; then
  echo "Uploaded. In App Store Connect the build appears under the version after Apple finishes processing (usually minutes)."
else
  echo "Signed package written. Nothing was sent to Apple."
fi
