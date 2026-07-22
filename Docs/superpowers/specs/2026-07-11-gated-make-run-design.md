# Gated Make Run Design

## Summary

`make run` must build the Debug app through the `swift-mk` build gate before it installs and launches `/Applications/Fan Curve.app`. The current recipe calls `app-local` directly, so the compile has no live gated Make ancestor and `swift-mk` refuses it.

## Build flow

The `run` target will invoke a recursive Debug `build` target instead of invoking `app-local` directly. `swift-mk build` will run the required gates and call the existing `SWIFT_BUILD_CMD`, which reaches `app-local`, builds the app, and stages `Products/Fan Curve.app` while the gate's Make process remains in its ancestry.

After that gated build succeeds, the existing deployment flow will replace `/Applications/Fan Curve.app`, terminate existing Fan Curve user-interface processes by bundle identifier, and open the canonical installed app. A gate or compile failure will stop the recipe before it changes the installed app.

## Enforcement

`Scripts/AuditMakeRun.swift` will require the `run` recipe to use `CONFIGURATION=Debug build`. It will no longer accept a direct `CONFIGURATION=Debug app-local` compile. Existing checks for the canonical `/Applications` destination, recursive copy, bundle-identifier termination, forbidden launch-control operations, and canonical `open` command will remain.

## Scope

The change is limited to `Makefile` and `Scripts/AuditMakeRun.swift`. It will not change `swift-makefile`, gate-proof semantics, app source, login-item registration, launch-agent behavior, or the untracked Boost button plan.

## Verification

1. Change the audit first and confirm `make run-audit` rejects the current direct `app-local` recipe.
2. Change the Makefile and confirm `make run-audit` passes.
3. Run `make run` and confirm the gated Debug build installs and launches `/Applications/Fan Curve.app`.
4. Confirm the running executable is `/Applications/Fan Curve.app/Contents/MacOS/FanCurve`.
5. Run `make verify` and confirm every project audit and test passes.
