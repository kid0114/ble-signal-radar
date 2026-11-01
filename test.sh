#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d "${TMPDIR:-/tmp}/signal-radar-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
target="$(uname -m)-apple-macosx13.0"
# Compile the shared contract alone: it must not require AppKit, CoreBluetooth or a backend.
xcrun swiftc -target "$target" -parse-as-library -emit-module -module-name SensorCore \
    Sources/Core/*.swift -emit-module-path "$work/SensorCore.swiftmodule"
sources=(Sources/Core/*.swift Sources/Analysis/*.swift Sources/App/Configuration.swift Sources/App/TrackingTarget.swift
         Sources/Backends/BLE/BLEAdvertisement.swift Sources/Backends/AirPods/*.swift Tests/*.swift)
xcrun swiftc -target "$target" "${sources[@]}" -o "$work/Tests"
"$work/Tests"
