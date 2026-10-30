#!/usr/bin/env bash
# Prints where a request-run script executes. No secrets, no network.
echo "whoami: $(whoami)"
echo "pwd: $(pwd)"
echo "script: ${BASH_SOURCE[0]}"
echo "dirname: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "--- ls pwd"; ls -la . | head -20
echo "--- ls script dir and parent"; ls -la "$(dirname "${BASH_SOURCE[0]}")" | head -20; ls -la "$(dirname "${BASH_SOURCE[0]}")/.." | head -20
echo "--- xcodebuild: $(command -v xcodebuild || echo none)"
echo "--- workspace roots"; ls /Volumes/AgentWorkspace/Projects 2>&1 | head -5; ls /Volumes/AgentWorkspace/System/mac-builds/work 2>&1 | head -5
