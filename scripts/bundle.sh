#!/usr/bin/env bash
# Build "Claude Profiles.app" from the SwiftPM product into build/.
#   UNIVERSAL=1 scripts/bundle.sh   arm64 + x86_64 (needs Xcode, not only the CLT)
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(cat VERSION)
out=build
app="$out/Claude Profiles.app"
build_flags=(-c release --product ClaudeProfiles)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then build_flags+=(--arch arm64 --arch x86_64); fi

swift build "${build_flags[@]}"
bin_dir=$(swift build "${build_flags[@]}" --show-bin-path)

rm -rf "$app" "$out/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ClaudeProfiles" "$app/Contents/MacOS/ClaudeProfiles"
sed "s/__VERSION__/$version/g" Resources/Info.plist > "$app/Contents/Info.plist"

# The binary draws its own icon; without one the app keeps the generic icon.
if "$app/Contents/MacOS/ClaudeProfiles" --render-icon "$out/AppIcon.iconset"; then
    iconutil -c icns "$out/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
else
    echo "warning: could not render the app icon" >&2
fi

codesign --force --sign - "$app"
echo "$app"
