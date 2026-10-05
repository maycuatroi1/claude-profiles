#!/usr/bin/env bash
# Install build/Claude Profiles.app into ~/Applications (or $PREFIX) and start it.
#   scripts/install.sh            install and open
#   scripts/install.sh --no-open  install only
#   scripts/install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id=tech.omelet.ClaudeProfiles
prefix=${PREFIX:-$HOME/Applications}
target="$prefix/Claude Profiles.app"

bundle_id_of() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# Quit the running copy and wait: a new copy started while the old one is
# still alive sees two instances and exits.
stop_app() {
    pkill -x ClaudeProfiles || true
    for _ in $(seq 50); do
        pgrep -x ClaudeProfiles >/dev/null || return 0
        sleep 0.2
    done
    echo "warning: Claude Profiles is still running" >&2
}

if [[ -e "$target" && "$(bundle_id_of "$target")" != "$bundle_id" ]]; then
    echo "error: $target exists and is not Claude Profiles; leaving it alone" >&2
    exit 1
fi

if [[ "${1:-}" == --uninstall ]]; then
    stop_app
    rm -rf "$target"
    echo "removed $target"
    echo "profiles and sync state remain in ~/Library/Application Support/$bundle_id"
    exit 0
fi

[[ -d "build/Claude Profiles.app" ]] || scripts/bundle.sh
stop_app
mkdir -p "$prefix"
rm -rf "$target"
ditto "build/Claude Profiles.app" "$target"
echo "installed $target"

if [[ "${1:-}" != --no-open ]]; then
    open "$target"
    echo "look for the two-person icon in the menu bar"
fi
