#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
swift build -c release
BUILD_CONFIGURATION=release bash script/build_and_run.sh --build-only

APP_BUNDLE="$ROOT_DIR/dist/Codex Pace Bar.app"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "release_gate PASS"
