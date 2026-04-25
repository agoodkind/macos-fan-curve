# FanCurve

Generator-first macOS app with Sparkle-based updates.

## Source of Truth

- `project.yml` is the authoritative Xcode project definition.
- `FanCurveApp.xcodeproj` is generated with `xcodegen` and is intentionally ignored.
- Build entry points regenerate the project automatically.

## Common Commands

- `make generate-project` — regenerate `FanCurveApp.xcodeproj`
- `make open-project` — regenerate and open the project in Xcode
- `make app` — regenerate, build, and stage `/Users/agoodkind/Sites/macos-fan-curve/Products/FanCurve.app`
- `make dmg` — build and package `/Users/agoodkind/Sites/macos-fan-curve/Products/FanCurve-Release.dmg`
- `make release-assets CURRENT_PROJECT_VERSION=... MARKETING_VERSION=...` — build a versioned DMG for a release
- `make prepare-sparkle-updates CURRENT_PROJECT_VERSION=... RELEASE_TAG=... GITHUB_RELEASE_BASE_URL=.../` — generate `build/sparkle-updates/appcast.xml`

## Release Shape

- Every push to `main` creates a GitHub Release tag in the same cadence as `go-makefile`:
  - `YYYYMMDDHHmm-<hex-run>-<short-sha>`
- GitHub Releases host the signed DMG asset.
- Sparkle reads a stable feed URL:
  - `https://goodkind.io/fancurve/appcast.xml`
- `goodkind.io/fancurve*` is served by the Cloudflare worker in `deploy/appcast-worker`.

## Required Secrets For CI

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_CODE_SIGN_IDENTITY`
- `APPLE_DEVELOPER_ID_P12_BASE64` or split secrets:
  - `APPLE_DEVELOPER_ID_P12_BASE64_PART1`
  - `APPLE_DEVELOPER_ID_P12_BASE64_PART2`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_PRIVATE_KEY`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## Local Sparkle Setup

- Set `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` in `Config/local.xcconfig`.
- Sparkle appcast generation also needs the private EdDSA key:
  - in Keychain via Sparkle `generate_keys`, or
  - via `SPARKLE_PRIVATE_KEY_FILE=/path/to/private-key make prepare-sparkle-updates ...`

## Notes

- The app build works without Sparkle secrets; the updater just stays disabled.
- `Sources/Views/SettingsView.swift` no longer polls GitHub Releases directly. Sparkle is the updater path now.
