# Contributing to Goose

Thanks for helping out! Bug reports, fixes and small features are all welcome. For anything big, open an issue first so we can agree on the approach before you write it.

## Setup

1. Follow **Building** in the [README](README.md). The key step is creating `Config/Local.xcconfig` with your own Team ID and bundle ID. That file is git-ignored, so never commit it, and don't put your IDs anywhere else.
2. Run the tests:
   ```bash
   nix run .#test
   ```
   Or press ⌘U in Xcode. Tests run in the Simulator and don't need signing.

Screen Time blocking, the block screen and NFC only work on a real iPhone. If your change touches any of them, say in the PR which device and iOS version you tested on.

## Guidelines

- **Nothing locks or unlocks without a tag.** That's the point of the app. Please don't add bypasses, timers that unlock automatically, or "emergency" buttons without discussing them in an issue first.
- **No network code, analytics or accounts.** Everything stays on the device.
- **Match the surrounding code:** SwiftUI, small focused types, comments only where the *why* isn't obvious.
- **Changes to the tag rules** (`TagRules` in `ProfileManager.swift`) need a test in `GooseTests/`.
- **Keep PRs focused.** One change per PR is easiest to review.

## Project layout

See the table in the README. Code that both the app and the widget need goes in `Shared/`. The widget runs in its own process and can only read what the app writes to the App Group.
