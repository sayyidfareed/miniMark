#!/usr/bin/env bash
# Builds, signs and uploads miniMark to App Store Connect (TestFlight and App Store). Only run when the
# release is ready: each upload uses up a build number. Set BUILD for later uploads (BUILD=2 ...).
set -euo pipefail
export BUILD="${BUILD:-1}"
exec bash "$(pwd)/scripts/mas-archive-and-upload.sh" upload
