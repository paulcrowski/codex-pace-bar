# Codex Pace Bar

Unofficial macOS menu bar app that shows whether your Codex weekly usage is below pace, on pace, or above pace.

## Download

**[Download the latest ready build for macOS](https://github.com/awronski/codex-pace-bar/releases/latest/download/CodexPaceBar.dmg)**

<img src="docs/screenshots/popover.png?v=2026-06-16" alt="Codex Pace Bar popover" width="472">

Codex Pace Bar answers one question at a glance: are you using your weekly Codex limit faster or slower than the current reset window pace?

> Was I rushing, or was I dragging?

<p>
  <img src="docs/screenshots/was-i-rushing-or-was-i-dragging.jpg" alt="Whiplash rushing or dragging scene" width="720">
</p>

## Status

Ready DMG builds are available from GitHub Releases. The package script ad-hoc signs local builds by default and supports Developer ID signing and Apple notarization for public releases.

The app depends on Codex's local app-server API, so future Codex CLI changes may require an app update.

## Requirements

### To Run

- macOS 15.0 or newer.
- [Codex CLI](https://developers.openai.com/codex/cli) installed and already logged in.

Codex Pace Bar starts the local Codex app-server through the Codex CLI. By default it looks for `codex` on your `PATH`, then checks common install locations such as `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `~/.local/bin/codex`, mise-managed `npm-openai-codex` installs, `~/.npm-global/bin/codex`, and `~/.bun/bin/codex`.

If your Codex CLI is installed somewhere else, set the exact executable path in Settings.

### To Build

- Swift 6 toolchain / Xcode command line build tools.

## What It Shows

- Seven visual segments representing the full weekly limit window.
- Filled usage based on Codex rate-limit data.
- A vertical pace marker based on exact elapsed time in the current reset window.
- A popover with used, ideal, remaining, reset time, and hours until reset.
- If usage is above pace, the popover shows how long to wait for the ideal pace to catch up.
- A chart of usage percentage during the current weekly window.
- A run-out forecast that learns recency-weighted hourly usage patterns for workdays and weekends from the last 30 days.
- A recent-pace forecast while the history-based model is still learning.

![Codex Pace Bar menu bar item](docs/screenshots/menu-bar.png)

## Settings

<img src="docs/screenshots/settings.png?v=06760d5" alt="Codex Pace Bar settings" width="626">

Settings are intentionally small:

- Codex executable path.
- Refresh interval.
- Pace delta threshold.
- Daily notification when usage is well above pace.
- Forecast notification when predicted usage indicates the weekly limit may run out before reset.
- History-based forecasting, enabled by default and configurable in Settings.
- Launch at login, enabled by default and configurable in Settings.
- Bar color scheme.
- Installed app version with a link to the GitHub repository.

Settings are stored in `UserDefaults`.
Usage history is stored locally in Application Support for 30 days. Reset metadata never deletes it; the chart derives the current continuous usage series from the retained archive. A validated rolling backup protects the previous file state.

More detail is documented in [architecture](docs/ARCHITECTURE.md), [privacy and notifications](docs/PRIVACY.md), and [release instructions](docs/RELEASING.md).

History-based forecasting groups observed percentage-point changes by workday or weekend and local hour. Recent weeks receive more weight, token reset transitions are excluded, and gaps longer than 90 minutes are not assigned to a specific working period. The chart plots the resulting hourly projection directly, so expected inactive periods appear as plateaus instead of being averaged into a straight line. The learned model requires at least seven days of history, 24 hours of usable observations, and one percentage point of observed usage. Until then, the app falls back to the recent-pace forecast, which requires three samples spanning 30 minutes and one percentage point of change.

## Build And Run

This project is intentionally shell-built. It does not require creating or opening an Xcode project.

```bash
./script/build_and_run.sh --verify
```

The script builds the SwiftPM executable, stages `dist/Codex Pace Bar.app`, launches it, and verifies that the process is running.

Run tests with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Depending on your local Swift toolchain setup, `DEVELOPER_DIR` may not be needed.

## Package DMG

Create a local ad-hoc-signed DMG:

```bash
./script/package_dmg.sh
```

Create a Developer ID-signed DMG for release:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

Create a signed and notarized release DMG using a stored `notarytool` profile:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
NOTARY_PROFILE="your-notary-profile" \
./script/package_dmg.sh
```

The script builds the app in release mode, signs the app bundle, and writes `dist/CodexPaceBar.dmg`. With `NOTARIZE=1`, it submits and staples both the app and DMG.

Ad-hoc signing is enough to seal the local app bundle, but it is not a substitute for Apple Developer ID signing and notarization. Public downloads may still show Gatekeeper warnings until release builds are notarized.

## Privacy

Codex Pace Bar is local-first: the main pace bar, usage history, and Task Monitor stay on this Mac by default.

- No analytics or telemetry.
- No external backend is required.
- The optional Phone notifications feature sends only generic task status to the ntfy topic you explicitly pair; it is disabled by default.
- Project name and duration are sent only when the separate "Phone notification details" option is enabled; prompts, responses, code, and full paths are never sent.
- No OpenAI credentials are requested or stored.
- Account and rate-limit data is read only through the local Codex app-server using your existing Codex session.
- Usage history contains local timestamps, percentage used, limit identifiers, and reset metadata for up to 30 days.
- Task Monitor stores local task metadata for up to 30 days and offers a delete-history action.

Debug information is redacted and limited to operational details such as selected executable path, app-server status, detected window durations, percentage values, reset timestamp presence, errors, and timestamps.

## Unofficial Project

Codex Pace Bar is an unofficial third-party project. It is not affiliated with, endorsed by, sponsored by, or maintained by OpenAI.

Codex, OpenAI, and related names are trademarks or registered trademarks of their respective owners.

## Limitations

- The app depends on Codex's local app-server interface.
- The app-server API is experimental.
- The app currently targets macOS 15.0+.
- Local ad-hoc builds are not notarized; public releases should continue to use Developer ID signing and notarization.
- Forecasts use percentage-based usage history because the app-server rate-limit response does not provide raw token spending totals.

## License

MIT. See [LICENSE](LICENSE).
