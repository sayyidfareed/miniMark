#!/usr/bin/env bash
# Runs on the M3 as the logged-in desktop user (it opens windows).
# 1. Builds the tests and runs each test class with a time limit, so one hung test
#    cannot hold the whole run.  2. Builds the app with the screenshot mode and has it
#    draw its own window to 2880x1800 PNGs (no screen capture).  Output: build/m3-run/.
set -uo pipefail

# The run helper executes a copy of this script from its own folder, with the repo as the working directory.
ROOT="$(pwd)"
[[ -d "$ROOT/miniMark.xcodeproj" ]] || { echo "run from the repo root: miniMark.xcodeproj not found in $ROOT"; exit 2; }
# Everything this run writes goes into one fresh folder under build/m3-run (git-ignored).
# Nothing outside it is created or deleted, and no earlier run's output is touched.
RUN_ROOT="$ROOT/build/m3-run"
OUT="$RUN_ROOT/$(date +%Y%m%dT%H%M%S)-$$"
DD="$OUT/derived"
mkdir -p "$OUT/screenshots" "$DD"
ln -sfn "$OUT" "$RUN_ROOT/latest"
cd "$ROOT"

# Run a command, kill it after $1 seconds. Prints "TIMEOUT" and returns 124 if it had to.
run_limited() {
  local limit="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited == 60 )); then state_report "60s into: $*" >> "$OUT/hang-state.txt" 2>&1; fi
    if (( waited >= limit )); then
      pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null
      echo "TIMEOUT after ${limit}s"
      return 124
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid"
}

echo "git commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)" | tee "$OUT/summary.txt"

# Read-only look at the desktop session and at anything left over from earlier runs.
state_report() {
  echo "=== state $(date +%T) ($1)"
  # Only the lock flags are kept from the console-user record; it also holds the account name.
  ioreg -n Root -d1 2>/dev/null | grep -oE '"(IOConsoleLocked|CGSSessionScreenIsLocked|kCGSSessionOnConsoleKey)" = [A-Za-z0-9]+'
  pmset -g powerstate IODisplayWrangler 2>/dev/null | tail -n 3
  pmset -g assertions 2>/dev/null | grep -E "^ +(PreventUserIdleDisplaySleep|UserIsActive|PreventSystemSleep) +[0-9]"
  ps -u "$(id -u)" -o pid,ppid,etime,stat,comm | grep -E "xcodebuild|xctest|testmanagerd|miniMark|XCTRunner" | grep -v grep
}
state_report "start" > "$OUT/preflight.txt" 2>&1

# Keep the display awake while this script runs (the assertion ends when the script does).
# A sleeping or locked screen stops apps from drawing, which would leave the tests and screenshots empty.
/usr/bin/caffeinate -u -t 3 >/dev/null 2>&1
/usr/bin/caffeinate -dims -w $$ >/dev/null 2>&1 &

xcodebuild -project miniMark.xcodeproj -scheme miniMark -destination "platform=macOS" \
  -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- build-for-testing > "$OUT/build-for-testing.log" 2>&1
echo "build-for-testing exit: $?" | tee -a "$OUT/summary.txt"

STATUS=0
HOST_STARTED=1
for cls in MarkdownDocumentTests DocumentStatsTests MarkdownFormattingTests MarkdownExportTests PreviewSupportTests; do
  if (( HOST_STARTED == 0 )); then echo "$cls: skipped, an earlier class never started a test" | tee -a "$OUT/summary.txt"; continue; fi
  run_limited 180 xcodebuild -project miniMark.xcodeproj -scheme miniMark -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- test-without-building \
    -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
    -only-testing:"miniMarkTests/$cls" > "$OUT/test-$cls.log" 2>&1
  code=$?
  passed=$(grep -c "passed on" "$OUT/test-$cls.log")
  failed=$(grep -c "failed on" "$OUT/test-$cls.log")
  echo "$cls: exit $code, passed $passed, failed $failed" | tee -a "$OUT/summary.txt"
  grep -E "failed on|error:|TIMEOUT" "$OUT/test-$cls.log" | head -n 8 | tee -a "$OUT/summary.txt"
  last=$(grep -E "Test case '.*' started" "$OUT/test-$cls.log" | tail -n 1)
  [[ $code -ne 0 ]] && echo "  last started: $last" | tee -a "$OUT/summary.txt"
  [[ $code -ne 0 ]] && STATUS=1
  if (( code == 124 && passed + failed == 0 )); then
    HOST_STARTED=0
    /usr/bin/log show --last 4m --style compact --predicate 'process == "testmanagerd" OR process == "xcodebuild" OR process == "miniMark" OR process == "xctest"' 2>/dev/null | tail -n 60 | cut -c1-260 > "$OUT/hang-log.txt"
  fi
done

xcodebuild -project miniMark.xcodeproj -scheme miniMark -configuration Release \
  -destination "platform=macOS" -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SNAPSHOT_MODE' \
  build > "$OUT/build.log" 2>&1 || { echo "release build failed; see build.log" | tee -a "$OUT/summary.txt"; exit 1; }

APP="$DD/Build/Products/Release/miniMark.app"
{
  echo "release binary:"
  lipo -archs "$APP/Contents/MacOS/miniMark" 2>&1
} | tee -a "$OUT/summary.txt"

state_report "before screenshots" >> "$OUT/preflight.txt" 2>&1
# The sandboxed app can only write inside its own container; it reports that folder, and the PNGs are copied out below.
run_limited 150 "$APP/Contents/MacOS/miniMark" --snapshot minimark-shots > "$OUT/snapshot.log" 2>&1
grep "^snapshot:" "$OUT/snapshot.log" | tee -a "$OUT/summary.txt"
SHOTS="$(sed -n 's/^snapshot-output: //p' "$OUT/snapshot.log" | tail -n 1)"
if [[ -n "$SHOTS" && -d "$SHOTS" ]]; then
  cp "$SHOTS"/*.png "$OUT/screenshots/" 2>/dev/null || true
fi

{
  echo "screenshots:"
  count=$(ls "$OUT"/screenshots/*.png 2>/dev/null | wc -l | tr -d ' ')
  if (( count != 4 )); then echo "  expected 4 screenshots, found $count"; STATUS=1; fi
  for f in "$OUT"/screenshots/*.png; do
    [[ -e "$f" ]] || { echo "  none written"; break; }
    echo "  $(basename "$f") $(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | tail -n 3 | tr -s ' \n' ' ')"
  done
} | tee -a "$OUT/summary.txt"

# Derived data is large; remove only the folder this run created inside its own output folder.
if [[ "$DD" == "$RUN_ROOT"/*/derived && -d "$DD" ]]; then rm -rf -- "$DD"; fi
exit "$STATUS"
