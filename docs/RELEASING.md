# Releasing Codex Pace Bar

## Local validation

Run the following from the repository root:

```bash
swift test
swift build -c release
bash script/release_gate.sh
```

The release gate runs the test suite, release build, app staging, and strict code-signature verification. `git diff --check` should also be clean before committing.

## Local DMG

For a local ad-hoc artifact:

```bash
bash script/package_dmg.sh
hdiutil verify dist/CodexPaceBar.dmg
```

Ad-hoc signing proves bundle integrity but does not satisfy Gatekeeper or Apple notarization.

## Public release

Public artifacts must use Developer ID signing and notarization:

```bash
RELEASE=1 \
BUILD_NUMBER=2 \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
NOTARY_PROFILE="your-notarytool-profile" \
bash script/package_dmg.sh
```

`RELEASE=1` fails closed unless signing, notarization, and a notarytool profile are supplied. The script rejects a build number that is not greater than the last recorded release number, staples and validates the app and DMG, and only then records the new build number.

## Acceptance checklist

- `swift test` passes.
- `swift build -c release` passes.
- `bash script/release_gate.sh` passes.
- `hdiutil verify` reports a valid DMG checksum.
- `codesign --verify --deep --strict` passes.
- For public distribution, `spctl` accepts the app and `xcrun stapler validate` reports a stapled ticket on a clean Mac.
- The UI is manually checked separately from build and test results, including Settings accessibility labels, Task Monitor refresh, sleep/wake, and phone delivery only when a real device is paired.
