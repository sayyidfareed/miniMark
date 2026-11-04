#!/usr/bin/env bash
# Read-only: says whether this Mac can sign a Mac App Store build. Prints each signing identity's
# label (kind, organisation, team id) without its hash, and counts of other things. Changes nothing.
set -uo pipefail
echo "date: $(date)"
echo "--- code-signing identities (valid only)"
security find-identity -v -p codesigning 2>/dev/null | sed -E 's/^ *[0-9]+\) [0-9A-F]+ "(.*)".*$/  \1/'
echo "--- installer identities (Mac Installer Distribution / 3rd Party Mac Developer Installer)"
security find-identity -v 2>/dev/null | sed -E 's/^ *[0-9]+\) [0-9A-F]+ "(.*)".*$/  \1/' | grep -i "installer" || echo "  none"
echo "--- identities that exist but are not valid (expired or missing key)"
security find-identity 2>/dev/null | grep -i "CSSMERR\|EXPIRED" | sed -E 's/^ *[0-9]+\) [0-9A-F]+ "(.*)".*$/  \1/' | head -n 10
echo "--- provisioning profiles on disk (count)"
ls ~/Library/MobileDevice/Provisioning\ Profiles ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles 2>/dev/null | grep -c provision | sed 's/^/  /'
xcodebuild -version 2>/dev/null | head -2
