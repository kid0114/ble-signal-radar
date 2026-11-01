#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d "${TMPDIR:-/tmp}/signal-radar-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" Configuration.swift SignalModel.swift Tests.swift -o "$work/Tests"
"$work/Tests"
