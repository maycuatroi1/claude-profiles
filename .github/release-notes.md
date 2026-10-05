Universal app for Apple silicon and Intel Macs, macOS 13 or later.

**Homebrew:**

```bash
brew install --cask maycuatroi1/tap/claude-profiles
```

**Or install with one command** (downloads this release, checks its SHA-256, installs into `~/Applications` and starts it):

```bash
curl -fsSL https://raw.githubusercontent.com/maycuatroi1/claude-profiles/main/scripts/get.sh | bash
```

**Or download the zip below**, unzip it and move `Claude Profiles.app` to Applications. The app is not notarized, so macOS blocks the first launch of a browser download. Either open System Settings, Privacy & Security, and click *Open Anyway*, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Claude Profiles.app"
```

Unofficial; not affiliated with or endorsed by Anthropic.
