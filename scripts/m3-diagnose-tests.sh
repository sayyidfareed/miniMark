#!/usr/bin/env bash
# Shows what could be holding up xcodebuild test on this desktop. Read-only, no secrets.
echo "whoami: $(whoami)   date: $(date)"
echo "--- processes related to testing or miniMark"
ps -axo pid,ppid,etime,stat,comm | grep -E "xcodebuild|xctest|testmanagerd|miniMark|XCTest|ReportCrash|CoreSimulator" | grep -v grep
echo "--- ps for the run helper and old runs"
ps -axo pid,etime,command | grep -E "m3-test-and-screenshots|minimark-dd|m3-run" | grep -v grep | cut -c1-200
echo "--- recent testmanagerd / xctest log lines (last 15 min)"
/usr/bin/log show --last 15m --style compact --predicate 'process == "testmanagerd" OR process == "xctest" OR process == "xcodebuild"' 2>/dev/null | tail -n 40 | cut -c1-240
echo "--- crash reports from the last day"
ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -8
