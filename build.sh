#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d "${TMPDIR:-/tmp}/signal-radar-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sources=(Sources/Core/*.swift Sources/Analysis/*.swift Sources/Backends/BLE/*.swift
         Sources/Backends/AirPods/*.swift Sources/App/*.swift Sources/UI/*.swift)
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" "${sources[@]}" -o "$work/SignalRadar"
app="$PWD/BLE Signal Radar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$work/SignalRadar" "$app/Contents/MacOS/SignalRadar.new"
mv -f "$app/Contents/MacOS/SignalRadar.new" "$app/Contents/MacOS/SignalRadar"
codesign --force --sign - "$app"
printf 'Built: %s\n' "$app"
