#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Building penumbra..."
swift build -c release 2>&1

BINARY=".build/release/penumbra"
APP_DIR="penumbra.app/Contents/MacOS"

mkdir -p "$APP_DIR"
cp "$BINARY" "$APP_DIR/penumbra"
cp Resources/Info.plist penumbra.app/Contents/Info.plist

echo "Built penumbra.app"
