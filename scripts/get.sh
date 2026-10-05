#!/usr/bin/env bash
# Download a Claude Profiles release and install it into ~/Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/maycuatroi1/claude-profiles/main/scripts/get.sh | bash
#
# Environment: VERSION=0.1.0 picks a release (default: the latest),
# PREFIX=/Applications installs elsewhere, NO_OPEN=1 skips starting the app.
#
# The release is ad-hoc signed, not notarized. A file fetched with curl carries
# no quarantine flag, so Gatekeeper does not stop it; a browser download does.
set -euo pipefail

repo=maycuatroi1/claude-profiles
bundle_id=tech.omelet.ClaudeProfiles
prefix=${PREFIX:-$HOME/Applications}
target="$prefix/Claude Profiles.app"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "Claude Profiles is a macOS app"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 13 )) || fail "Claude Profiles needs macOS 13 or later"

version=${VERSION:-}
if [[ -z "$version" ]]; then
    version=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
        sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)
    [[ -n "$version" ]] || fail "could not find the latest release of $repo"
fi

zip="Claude-Profiles-$version.zip"
url="https://github.com/$repo/releases/download/v$version"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "downloading Claude Profiles $version"
curl -fsSL -o "$work/$zip" "$url/$zip"
curl -fsSL -o "$work/$zip.sha256" "$url/$zip.sha256"
(cd "$work" && shasum -a 256 -c "$zip.sha256" >/dev/null) || fail "checksum mismatch for $zip"
ditto -x -k "$work/$zip" "$work/unpacked"
app="$work/unpacked/Claude Profiles.app"
[[ -d "$app" ]] || fail "$zip does not contain Claude Profiles.app"

if [[ -e "$target" ]]; then
    existing=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)
    [[ "$existing" == "$bundle_id" ]] || fail "$target exists and is not Claude Profiles; leaving it alone"
fi

# Quit a running copy and wait for it, or the new one would see two
# instances and exit.
pkill -x ClaudeProfiles || true
for _ in $(seq 50); do
    pgrep -x ClaudeProfiles >/dev/null || break
    sleep 0.2
done

mkdir -p "$prefix"
rm -rf "$target"
ditto "$app" "$target"
echo "installed $target"

if [[ -z "${NO_OPEN:-}" ]]; then
    open "$target"
    echo "look for the two-person icon in the menu bar"
fi
