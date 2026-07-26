# Task 5: Deterministic Fan Curve UI scenarios

## Status

The UI scenario target, canonical Make runner, stable accessibility identifiers,
controlled runtime fixtures, and failure evidence capture are implemented.

The macOS host did not authorize XCTest automation mode. The live UI test attempt
failed before any scenario started, so this report does not claim that the UI
scenarios passed.

## UI surface

`AppAccessibilityIdentifier` defines stable identifiers for:

- setup content, approval guidance, actions, errors, and sidebar recovery;
- dashboard telemetry, fan rows, fan control, Boost, and degraded state;
- curve control points;
- Settings tabs, background control, service rows, service actions, ownership,
  and Learn;
- manual fan probe actions;
- application Settings, About, quit, and lifecycle windows.

The Settings menu command and dashboard Settings button use distinct identifiers,
which keeps menu selection unambiguous.

## Scenarios

`FanCurveUITests` is a hostless UI test target. It drives the signed canonical
`/Applications/Fan Curve.app` by bundle identifier and verifies the running
executable path after each launch.

The target contains four scenario groups:

1. Setup covers background registration, background approval, helper
   registration, helper approval, helper repair, every mutation failure, and the
   original enabled-but-unreachable helper state. The successful repair records
   helper unregister and register evidence before the UI advances to the
   dashboard.
2. Runtime health covers healthy telemetry, unavailable readings, an unreachable
   helper, stale telemetry, ownership preemption, and recovery after every
   degraded state.
3. Controls cover curve mutation, fan control, Boost, background application,
   service rows, ownership disclosure, manual 15,000 RPM probing, automatic fan
   reset, every Settings tab, About, quit, and canonical relaunch.
4. Protocol coverage drives every declared XPC fault and verifies that both the
   app and agent reject a lower controlled-state revision.

Every scenario failure retains an XCTest screenshot, controlled app evidence,
controlled agent evidence, and the current control state as test attachments.

## Canonical runner

The Make entry point is:

```sh
make test-ui \
  UI_TEST_SESSION_PATH=/absolute/test-control-session \
  UI_TEST_RESULT_BUNDLE_PATH=/absolute/FanCurveUITests.xcresult
```

The runner requires a pre-created controlled session, verifies the signed
canonical app, uses dedicated UI test derived data, runs only the
`FanCurveUITests` scheme, and copies the single result bundle even when tests
fail. Its destructive paths are constrained to a `.xcresult` output and a
workspace-local `UITests` derived-data directory.

The normal Release app scheme does not build the UI test target. The focused
contract scheme builds the target so source drift fails a normal contract check
without starting UI automation.

## RED and GREEN evidence

The focused RED checks first failed for a missing UI test target, missing
controlled runtime health flags, missing stale-health presentation behavior, and
a missing canonical runner script.

Before the live UI attempt, these focused checks passed:

- `make test-control-contract`: 26 passed, 0 failed.
- `make test-agent`: 32 passed, 0 failed.
- `make test`: 125 passed, 0 failed. This run preceded the final runner contract
  test, which brings the expected total to 126.

The final runner and UI source compiled after the Settings identifier correction
and the accepted-revision restoration. The subsequent contract test process did
not enter any XCTest method because the host XCTest service remained wedged after
the automation authorization timeout.

## Live UI evidence

The controlled app was installed and launched successfully with:

```sh
make run FANCURVE_TEST_CONTROL_PATH=/tmp/FanCurveUITestSession.X3GgtF
```

The live runner command was:

```sh
make test-ui \
  UI_TEST_SESSION_PATH=/tmp/FanCurveUITestSession.X3GgtF \
  UI_TEST_RESULT_BUNDLE_PATH=/tmp/FanCurveUITests-live.xcresult
```

The runner failed with `xcodebuild` status 65 before any scenario ran:

```text
FanCurveUITests-Runner failed to initialize for UI testing.
Timed out while enabling automation mode.
```

The preserved result bundle at `/tmp/FanCurveUITests-live.xcresult` reports one
harness failure, zero passed tests, and zero skipped tests. Unified logging shows
`testmanagerd` requested automation mode, then
`automationmode-writer` reported that authentication was required. The timeout
followed 60 seconds later.

The host has Developer Mode enabled, but it lacks the interactive first-use
authorization that macOS requires for UI automation. Task 6 must grant that
authorization inside the Tart guest before using this runner as validation
evidence.

## Verification

- `make fmt`: passed.
- `shellcheck Scripts/RunFanCurveUITests.sh`: passed.
- `make lint-swiftlint lint-complexity swiftcheck-extra`: passed.
- `make lint-deadcode`: passed.
- `make log-audit`: passed.
- `make launch-agent-audit`: passed.
- `make run-audit`: passed.
- `make test-control-contract`: passed with 26 tests before the live UI attempt.
  The final rerun compiled the contract and UI targets, then was interrupted
  because the host XCTest service did not start any test method.
- `make test-agent`: passed with 32 tests before the live UI attempt. Post-attempt
  reruns were blocked during XCTest session preparation.
- `make test`: passed with 125 tests before the final runner contract addition.
  Post-attempt reruns were blocked during XCTest session preparation.
- `make test-ui UI_TEST_SESSION_PATH=/tmp/FanCurveUITestSession.X3GgtF
  UI_TEST_RESULT_BUNDLE_PATH=/tmp/FanCurveUITests-live.xcresult`: failed before
  scenario execution because macOS automation mode required authentication.
- `make verify`: passed its audits and build preconditions, then was interrupted
  when its test phase remained blocked during XCTest session preparation.
- `make run`: passed after the controlled attempt and restored the canonical
  production app without `FANCURVE_TEST_CONTROL_PATH`.

No `xcodebuild` or `xctest` process from these attempts remains running.
