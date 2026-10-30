#!/usr/bin/env bash
# Runs on the M3 as the logged-in desktop user (it opens windows).
# 1. Runs the unit tests.  2. Builds the app and has it draw its own window to
# 2880x1800 PNGs (no screen capture).  Everything lands in build/m3-run/.
set -uo pipefail

# The run helper executes a copy of this script from its own folder, with the repo as the working directory.
ROOT="$(pwd)"
[[ -d "$ROOT/miniMark.xcodeproj" ]] || { echo "run from the repo root: miniMark.xcodeproj not found in $ROOT"; exit 2; }
OUT="$ROOT/build/m3-run"
DD="$(mktemp -d "${TMPDIR:-/tmp}/minimark-dd.XXXXXX")"
rm -rf "$OUT"
mkdir -p "$OUT/screenshots"
cd "$ROOT"

xcodebuild -project miniMark.xcodeproj -scheme miniMark -destination "platform=macOS" \
  -derivedDataPath "$DD" -resultBundlePath "$OUT/test.xcresult" CODE_SIGN_IDENTITY=- \
  test > "$OUT/test.log" 2>&1
TEST_STATUS=$?
{
  echo "git commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "test exit status: $TEST_STATUS"
  grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|error:" "$OUT/test.log" | tail -n 20
} | tee "$OUT/summary.txt"

xcodebuild -project miniMark.xcodeproj -scheme miniMark -configuration Release \
  -destination "platform=macOS" -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SNAPSHOT_MODE' \
  build > "$OUT/build.log" 2>&1 || { echo "release build failed; see build.log" | tee -a "$OUT/summary.txt"; exit 1; }

APP="$DD/Build/Products/Release/miniMark.app"
"$APP/Contents/MacOS/miniMark" --snapshot minimark-shots > "$OUT/snapshot.log" 2>&1 &
PID=$!
for _ in $(seq 1 120); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
kill "$PID" 2>/dev/null || true

SHOTS="$(sed -n 's/^snapshot-output: //p' "$OUT/snapshot.log" | tail -n 1)"
if [[ -n "$SHOTS" && -d "$SHOTS" ]]; then
  cp "$SHOTS"/*.png "$OUT/screenshots/" 2>/dev/null || true
fi

{
  echo "screenshots:"
  for f in "$OUT"/screenshots/*.png; do
    [[ -e "$f" ]] || { echo "  none written"; break; }
    echo "  $(basename "$f") $(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | tail -n 3 | tr -s ' \n' ' ')"
  done
} | tee -a "$OUT/summary.txt"

rm -rf "$DD"
exit "$TEST_STATUS"
