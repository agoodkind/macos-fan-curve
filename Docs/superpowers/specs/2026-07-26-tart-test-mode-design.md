# Test control mode design

## Summary

Fan Curve adds an opt-in Debug test mode that runs the production app, background agent,
Agent XPC transport, controller, persistence, and SwiftUI code. Test mode replaces only
macOS Service Management results and SMC hardware access. A person validates real
`SMAppService` registration by hand, following the
[manual validation guide](../../validating-on-a-mac.md).

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

## Manual validation

Fan Curve ships a written validation guide at `Docs/validating-on-a-mac.md` instead of a
virtual-machine orchestration layer. A runner covers only the environment it automates,
while the question worth answering is whether a person can install a build on a Mac and
watch it work. The guide covers any Mac and names a virtual machine as one way to get a
clean one.

The person builds signed on the machine holding the signing identity, verifies the
signature, installs to `/Applications/Fan Curve.app`, walks the setup flow through its
approval prompts, verifies fan control against `powermetrics`, and exercises the recovery
paths. Automated tests cannot reach any of that: approval prompts need a person, and a
virtual machine has no fans.

The guest never compiles the product. Entitlements are authorized per machine, the guest
is not a registered device, and a build produced there cannot carry a usable Developer ID
signature. Building on the host also keeps the artifact under test byte-identical to what
a user installs.

A signed Developer ID build runs in a stock guest with code signing fully enforced.
Disabling System Integrity Protection or setting `amfi_get_out_of_my_way=1` turns off the
signature and entitlement checking that this validation exists to exercise. Verified
2026-07-29 on a `macos-tahoe-base` guest running macOS 26.5 with `boot-args` empty.

A bundle moves as an archive over the network, not through a shared folder. A `cp` from a
Tart shared folder fails on large reads with `fcopyfile failed: Input/output error`, and
`rsync` of a signed bundle strips its signature. `ditto -c -k --keepParent` to a zip,
`scp`, and `ditto -x -k` on the far side preserve it, verified with `shasum -a 256` on
both sides and `codesign -v --verbose=2` after extraction.

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

Stable accessibility identifiers anchor every user action and assertion. Unit and
integration tests cover state resolution, adapter contracts, control-file validation,
revision acknowledgment, recorded commands, and fault injection.

## Shared tooling boundary

ICT, Stickies, and `swift-makefile` have no common virtual-machine lifecycle contract.
ICT owns product-specific simulator and Catalyst UI-test commands, while Stickies has no
UI-test target or runtime service.

Fan Curve does not add one. Nothing here orchestrates a virtual machine, so there is no
lifecycle behavior to promote into `SwiftMkCore` and no second consumer to design for.
Product fixtures, accessibility identifiers, service states, and XPC faults stay in this
repository.

## Verification

- Run test-first unit and integration cycles for every new production interface and
  Debug adapter.
- Run `make test`, `make build`, `make log-audit`, `make launch-agent-audit`,
  `make run-audit`, and `make verify`.
- Run `make run` and confirm the normal Debug app uses production adapters.
- Follow the [manual validation guide](../../validating-on-a-mac.md) on a Mac with fans
  before shipping a release.
