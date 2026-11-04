#!/usr/bin/env bash
# Read-only: says whether this Mac can sign a Mac App Store build. Prints identity kinds and team ids only; changes nothing.
set -uo pipefail
echo "whoami: $(whoami)   date: $(date)"
echo "--- code-signing identities (kind and team id only)"
security find-identity -v -p codesigning 2>/dev/null | sed -E 's/^ *[0-9]+\) [0-9A-F]+ "([^"(]*)(\([A-Z0-9]+\))?.*"/  \1 \2/' | sed 's/Apple Development: .*(/Apple Development: (name hidden) (/; s/Apple Distribution: .*(/Apple Distribution: (name hidden) (/; s/3rd Party Mac Developer Application: .*(/3rd Party Mac Developer Application: (name hidden) (/; s/3rd Party Mac Developer Installer: .*(/3rd Party Mac Developer Installer: (name hidden) (/' | head -n 20
echo "--- installer identities"
security find-identity -v 2>/dev/null | grep -c "Installer" | sed 's/^/  installer identities: /'
echo "--- Xcode accounts signed in (count only)"
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -c teamID | sed 's/^/  teams known to Xcode: /'
echo "--- provisioning profiles for app.minimark.miniMark"
ls ~/Library/MobileDevice/Provisioning\ Profiles 2>/dev/null | wc -l | sed 's/^/  profiles on disk: /'
xcodebuild -version 2>/dev/null | head -2
