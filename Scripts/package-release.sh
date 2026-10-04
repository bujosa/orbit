#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/build-app.sh
app_path="$PWD/dist/Orbit.app"
codesign --verify --deep --strict "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
architecture=$(lipo -archs "$app_path/Contents/MacOS/Orbit")
case "$architecture" in
  arm64|x86_64) ;;
  *) printf 'Unsupported release architecture: %s\n' "$architecture" >&2; exit 1 ;;
esac
for executable in "$app_path/Contents/MacOS/orbitctl" "$app_path/Contents/Resources/orbit-agent"; do
  [[ "$(lipo -archs "$executable")" == "$architecture" ]] || {
    printf 'Mismatched executable architecture\n' >&2
    exit 1
  }
done
if [[ -n "$(find "$app_path" -type f \( -name devices.json -o -name state.json -o -name '*.env' -o -name '*.pem' -o -name '*.key' \) -print -quit)" ]]; then
  printf 'Private state or credential file found in app bundle\n' >&2
  exit 1
fi
release_directory="$PWD/dist/release"
archive_name="Orbit-v${version}-macos-${architecture}.zip"
mkdir -p "$release_directory"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_directory/$archive_name"
(cd "$release_directory" && shasum -a 256 "$archive_name" > SHA256SUMS)
printf 'Packaged %s\n' "$release_directory/$archive_name"
