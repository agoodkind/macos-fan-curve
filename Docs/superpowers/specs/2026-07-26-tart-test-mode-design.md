# Tart Test Mode Design

## Summary

Fan Curve will add an opt-in Debug test mode that runs the production app, background
agent, Agent XPC transport, controller, persistence, and SwiftUI code inside a Tart
virtual machine. Test mode will replace only macOS Service Management results and SMC
hardware access. A separate Release smoke suite will use real `SMAppService`
registration in a disposable Tart clone.

The existing Debug scenario path replaces `FanCurveAgentClient` and bypasses Agent XPC.
This work will retire that path so normal Debug builds use production behavior unless an
end-to-end test explicitly supplies a test-control session.

## Correct production setup

Production setup will enable the Background Agent before installing the System Helper.
The app may call `SMAppService` only to bootstrap the Background Agent because Agent XPC
does not exist before that service starts.

After Agent XPC connects, the app will send helper status, install, repair, and System
Settings commands through the agent. The agent will own helper `SMAppService` access and
translate it into the existing product-level runtime setup state. The app will no longer
register the helper daemon directly.

An enabled but unreachable helper will remain a repair state. Repair will unregister and
register the helper through the agent, preserving the behavior merged in PR #33.

## Keep test mode close to production

The app and agent will select dependencies at their composition roots:

- Production Service Management adapters call `SMAppService`.
- A Debug test adapter reports controlled agent and helper states and controlled
  registration results.
- The production hardware adapter uses the existing privileged-helper XPC client.
- A Debug test hardware adapter returns controlled sensors, fans, ownership, and failures
  and records every fan command.

No alternate view, controller, model, persistence layer, app-to-agent protocol, or XPC
transport will exist for test mode. Focused Debug fault hooks may reject a real command,
return malformed encoded data, interrupt a connection, or duplicate an event. Each hook
will modify one production XPC boundary behavior without replacing the connection.

All test-only adapters and hooks will compile under `#if DEBUG`. A Debug app will activate
them only when `FANCURVE_TEST_CONTROL_PATH` names a valid test session. A normal
`make run` will continue to use real Service Management and hardware paths.

## Control state and evidence

A Debug-only `FanCurveTestControl` command-line tool will own a versioned JSON control
contract. The tool will atomically update a session directory, wait for app and agent
acknowledgments, and read recorded events.

The control state will include:

- Agent and helper service status: not registered, approval required, or enabled.
- The next registration, unregistration, Settings, hardware, or XPC operation result.
- Sensor temperatures, fan readings, ownership rows, load values, and runtime flags.
- XPC fault selection for malformed replies, rejected commands, duplicate events,
  interruption, invalidation, and reconnect.
- A monotonic revision used for condition-based synchronization.

The app and agent will acknowledge each applied revision separately. Recorded evidence
will include service mutations, app-to-agent commands, hardware reads, fan writes, fan
auto resets, XPC faults, and process lifecycle events. Tests will wait for revisions and
observable UI state instead of fixed delays.

## Tart harness

Fan Curve will own a thin Swift Tart runner and guest script exposed through Make targets.
The host runner will:

1. Clone `fan-curve-e2e-20260725` to a uniquely named disposable virtual machine.
2. Start the clone headlessly with the repository and artifact directory shared.
3. Wait for the guest agent, IP address, SSH, and logged-in desktop session.
4. Copy the source to the guest's local disk and run the canonical Make targets there.
5. Collect `.xcresult` bundles, screenshots, unified logs, launchd state, registration
   state, and test-control evidence.
6. Stop and delete only the validated disposable clone.

The runner will trap interruption, terminate child processes, and clean temporary files.
It will keep the clone only when an explicit diagnostic option requests that behavior.

The deterministic suite will install the canonical Debug app at
`/Applications/Fan Curve.app`. A prepared agent registration in the disposable guest will
keep the real Mach service available; controlled agent states will gate whether the app
connects to it.

The Release smoke suite will start from a clean disposable clone, install the Release app
at the same canonical path, and exercise real agent and helper `SMAppService`
registration, approval, repair, launch, reconnect, and relaunch behavior. It will never
enable fan control or request an SMC write.

## End-to-end coverage

The Debug suite will cover:

- Checking, agent missing, agent approval, helper missing, helper approval, helper repair,
  ready, and each setup mutation failure.
- Healthy, unavailable, degraded, stale, ownership-preempted, and recovered runtime
  states with exact controlled telemetry.
- Curve edits, curve enablement, Boost, background application, manual RPM, fan auto,
  ownership, Settings, About, quit, background continuation, and reset-on-exit.
- Initial-state decode failures, event decode failures, command rejection, malformed
  command replies, duplicate events, interruption, invalidation, reconnect, and
  out-of-order revisions.
- The original stuck state: Background Agent running, helper reported not installed,
  helper service already enabled, and clicking `Install System Helper` performs repair
  and advances the UI.

Stable accessibility identifiers will anchor every user action and assertion. Unit and
integration tests will cover state resolution, adapter contracts, control-file
validation, revision acknowledgment, recorded commands, and fault injection before the
Tart tests exercise the full process graph.

## Shared tooling boundary

ICT, Stickies, and `swift-makefile` currently have no common Tart lifecycle contract.
ICT owns product-specific simulator and Catalyst UI-test commands, while Stickies has no
UI-test target or runtime service.

Tart lifecycle, guest preparation, artifact transfer, and evidence collection will
remain local to Fan Curve for this implementation. The local runner will keep product
configuration separate from lifecycle operations so a later change can move proven
common behavior into `SwiftMkCore`.

Promotion to `swift-makefile` requires a second consumer to use the same clone, guest,
transfer, test, evidence, and cleanup contract. Product fixtures, accessibility
identifiers, service states, XPC faults, and assertions will always remain in their
consumer repositories.

## Verification

- Run test-first unit and integration cycles for every new production interface and
  Debug adapter.
- Run `make test`, `make build`, `make log-audit`, `make launch-agent-audit`,
  `make run-audit`, and `make verify`.
- Run `make run` and confirm the normal Debug app uses production adapters.
- Run the deterministic Tart target and preserve its `.xcresult`, screenshots, logs,
  and command evidence.
- Run the Release Tart smoke target and preserve real `SMAppService`, launchd, signing,
  and reconnect evidence.
