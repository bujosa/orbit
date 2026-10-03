#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Orbit.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Orbit" "$app_path/Contents/MacOS/Orbit"
cp "$binary_dir/orbit-agent" "$app_path/Contents/Resources/orbit-agent"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources/cursor-runtime"
cp Resources/cursor-runtime/package.json Resources/cursor-runtime/package-lock.json "$app_path/Contents/Resources/cursor-runtime/"
npm ci --omit=dev --prefix "$app_path/Contents/Resources/cursor-runtime" --no-audit --no-fund
swift Scripts/make-icon.swift "$app_path/Contents/Resources"
codesign --force --sign - "$app_path/Contents/Resources/orbit-agent"
codesign --force --sign - "$app_path/Contents/MacOS/Orbit"
codesign --force --sign - "$app_path"
printf 'Built %s\n' "$app_path"
