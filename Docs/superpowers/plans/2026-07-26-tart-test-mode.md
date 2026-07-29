# Fan Curve Production Service Boundary and Tart Test Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Every behavior change follows test-driven development.

**Goal:** Correct production service ownership and add a thin, production-close Tart test mode without changing ICT, Stickies, or swift-makefile.

**Architecture:** The app directly manages only the Background Agent. The agent manages the privileged helper and hardware, and the app reaches both through real Agent XPC. Debug test mode replaces only typed Service Management and fan-hardware adapters when an explicit valid control session is active.

**Tech Stack:** Swift 6, SwiftUI, NSXPCConnection, ServiceManagement, XCTest, Tuist, Make, Tart.

## Global Constraints

- Keep all implementation in Fan Curve.
- Normal Debug and all Release builds use production adapters unless a valid `FANCURVE_TEST_CONTROL_PATH` session is active under `#if DEBUG`.
- A present but invalid `FANCURVE_TEST_CONTROL_PATH` must refuse service and hardware operations.
- Keep the real app, agent, Agent XPC transport, controller, persistence, and SwiftUI paths in deterministic tests.
- The app may call `SMAppService` only for Background Agent lifecycle setup.
- The agent owns all helper status, registration, repair, approval, and hardware operations.
- `/Applications/Fan Curve.app` remains the single canonical runtime path.
- Keep Tart lifecycle local to Fan Curve. Do not change ICT, Stickies, or swift-makefile.
- Use structured project logging at every new boundary and run `make log-audit`.
- Use signed commits with `Co-authored-by: Codex <noreply@openai.com>`.

---

### Task 1: Correct production service ownership

**Files:**
- Modify: `Sources/Common/RuntimeState.swift`
- Create: `Sources/Common/ManagedService.swift`
- Create: `Sources/Models/ServiceManagementAdapters.swift`
- Modify: `Sources/Common/FanCurveAgentXPCProtocol.swift`
- Modify: `Sources/Models/InstallationState.swift`
- Modify: `Sources/Models/InstallationState+AgentLifecycle.swift`
- Modify: `Sources/Agent/FanCurveAgentXPCService.swift`
- Modify: `Sources/Services/FanCurveAgentClient.swift`
- Modify: setup views under `Sources/Views/`
- Test: `Tests/ModelTests/SetupStateTests.swift`
- Test: new focused service-boundary tests under `Tests/ModelTests/`

**Interfaces:**
- Produce `ManagedServiceStatus`, `ManagedServiceMutationResult`, `BackgroundAgentServiceManaging`, and `HelperServiceManaging`.
- Produce `AgentCommand.installOrRepairHelper` and `FanCurveAgentClient.installOrRepairHelper()`.
- Preserve enabled-helper repair as unregister followed by register.

**Requirements:**
- Write failing tests proving both missing services show Background Agent setup first.
- Write failing tests proving enabled helper repair performs unregister then register.
- Inject Background Agent service access into `InstallationState`.
- Inject helper service access into `FanCurveAgentXPCService`.
- Remove all app-side helper `SMAppService` access.
- Route helper install, repair, and helper approval through Agent XPC.
- Keep direct app System Settings access only when Agent approval prevents XPC.
- Run focused failing tests before implementation, then run `make test`.
- Commit the completed slice.

### Task 2: Add the fan-hardware seam and remove bypass scenarios

**Files:**
- Create: `Sources/Agent/FanHardware.swift`
- Modify: `Sources/Agent/XPCClient.swift`
- Modify: `Sources/Agent/AgentController.swift`
- Modify: controller tick types and uses under `Sources/Agent/`
- Modify: `Sources/App/FanCurveApp.swift`
- Modify: `Sources/Services/FanCurveAgentClient.swift`
- Delete: `Sources/Common/DevScenario.swift`
- Delete: `Sources/Common/DevScenarioStore.swift`
- Test: new focused controller and hardware contract tests

**Interfaces:**
- Produce `FanHardware` and `FanHardwareBatchRead`.
- `XPCClient` conforms as the production implementation.
- `AgentController` accepts `any FanHardware` and defaults to the production adapter at its composition root.

**Requirements:**
- Write failing tests proving controller reads and commands use the injected port.
- Preserve fan command mapping, ownership, priority, and reset-to-auto behavior.
- Remove the Debug scenario menu and all paths that replace `FanCurveAgentClient`.
- Keep normal Debug behavior on real XPC.
- Run focused failing tests before implementation, then run `make test`.
- Commit the completed slice.

### Task 3: Add the Debug control contract and signed CLI

**Files:**
- Create focused files under `Sources/TestControl/`
- Modify: `Project.swift`
- Modify: generated configuration inputs only where the agent launch environment requires the session path
- Test: new control-contract tests under `Tests/ModelTests/`

**Interfaces:**
- Produce versioned `TestControlState`, `TestServiceState`, `TestHardwareState`, `TestXPCFault`, `TestControlAcknowledgment`, and `TestControlEvent`.
- Produce `FanCurveTestControl` commands: `initialize`, `apply`, `wait-ack`, `wait-event`, and `export-evidence`.

**Requirements:**
- Write failing tests for schema validation, monotonic revision rejection, atomic replacement, participant acknowledgments, and separate JSON Lines evidence files.
- Use a unique session identifier and revision in every state, acknowledgment, and event.
- Use condition-based waits with explicit timeouts.
- Activate only under `#if DEBUG`.
- Use production adapters when the environment variable is absent.
- Refuse operations when the variable is present but the session is invalid.
- Add the signed command-line target without embedding it in Release artifacts.
- Run focused failing tests before implementation, then run `make test`.
- Commit the completed slice.

### Task 4: Add controlled adapters and real-XPC fault injection

**Files:**
- Create Debug controlled service and hardware adapters under `Sources/TestControl/`
- Modify: app and agent composition roots
- Modify: `Sources/Agent/FanCurveAgentXPCService.swift`
- Modify: `Sources/Services/FanCurveAgentClient.swift`
- Test: new adapter and protocol tests

**Interfaces:**
- Controlled adapters consume `TestControlState` and write `TestControlEvent`.
- The app and agent write separate acknowledgments after applying a revision.
- XPC faults are one-shot and recorded before execution.

**Requirements:**
- Write failing tests for controlled service status, mutation failures, sensor and fan values, ownership, RPM writes, auto resets, and lower-revision rejection.
- Keep the real `NSXPCConnection`.
- Cover malformed initial state, malformed event, rejected command, malformed reply, duplicate event, connection invalidation, agent process exit, and reconnect.
- Gate connection attempts for controlled missing-agent states.
- Do not create an alternate transport, view model, controller, or persistence path.
- Run focused failing tests before implementation, then run `make test`.
- Commit the completed slice.

### Task 5: Add stable UI identifiers and deterministic macOS UI tests

**Files:**
- Modify relevant setup, dashboard, settings, curve, ownership, and window views
- Add macOS UI tests under `Tests/FanCurveUITests/`
- Modify: `Project.swift`

**Requirements:**
- Add stable identifiers for setup actions, service rows, settings tabs, curve controls, Boost, background control, manual fan controls, ownership, Settings, About, and quit behavior.
- Drive the signed canonical app at `/Applications/Fan Curve.app`.
- Cover every setup state and mutation failure.
- Reproduce the original stuck state and verify repair evidence plus UI advancement.
- Cover healthy, unavailable, degraded, stale, preempted, and recovered telemetry.
- Cover curve editing, enablement, Boost, background mode, manual RPM, auto reset, ownership, Settings, About, quit, and relaunch.
- Cover every planned protocol fault and out-of-order revision.
- Save screenshots as XCTest attachments at each failure boundary.
- Run focused failing tests before implementation, then run `make test`.
- Commit the completed slice.

### Task 6: Add the local Tart runner, Release smoke, and Make targets

**Files:**
- Create: `Scripts/TartE2E.swift`
- Create: `Scripts/tart-e2e-guest.sh`
- Modify: `Makefile`
- Modify: `Project.swift` for Release smoke tests
- Add Release smoke tests under `Tests/FanCurveServiceSmokeTests/`

**Requirements:**
- Add `make tart-e2e-debug` and `make tart-e2e-release-smoke`.
- Build the signed app on the host. The guest must never compile the product: entitlements are authorized per machine, the guest is not a registered device, and a guest build cannot carry a usable signature.
- Clone the provisioned base virtual machine to a validated unique name. The base is named by `TART_E2E_BASE_VM`, defaulting to the current provisioned base rather than the retired `fan-curve-e2e-20260725`.
- Set `TART_HOME` explicitly. The base images live on external storage, and the default `~/.tart` does not see them.
- Run headlessly with only the artifact directory mounted read-write. Do not mount the source.
- Transfer the built app with `ditto -c -k --keepParent`, `scp` to the guest IP, then `ditto -x -k` in the guest. Do not use the shared folder for the bundle: large reads fail with `fcopyfile failed: Input/output error`. Do not use `rsync`: a signed bundle arrives ad-hoc.
- Verify the transfer with `shasum -a 256` on both sides and `codesign -v --verbose=2` after extraction. Fail the run on a mismatch rather than testing an unsigned or truncated bundle.
- Ensure the guest has `amfi_get_out_of_my_way=1` in `nvram boot-args` and has rebooted, or a signed binary is killed with `OS_REASON_CODESIGNING`. Disabled SIP alone does not satisfy this.
- Install to `/Applications/Fan Curve.app` in the guest, the single canonical runtime path.
- Wait for IP, SSH, the guest agent, and a logged-in desktop.
- Trap INT and TERM, track child processes, stop safely, and exit 130 after interruption.
- Delete only the validated disposable clone unless `TART_KEEP_VM=1`.
- Preserve `.xcresult`, screenshots, unified logs, signing evidence, launchd state, Service Management state, and test-control evidence under `build/tart-e2e/<run-id>/`.
- Keep fan control disabled during Release smoke and assert no SMC writes.
- Use real `SMAppService`, launchd, Agent XPC, helper repair, reconnect, and relaunch in Release smoke.
- Run `make tart-e2e-debug` and `make tart-e2e-release-smoke`.
- Commit the completed slice.

### Task 7: Rebase, verify, review, and submit the stack

This task originally called for one pull request covering every slice. That produced a
single change of roughly 11,300 insertions across 96 files, which is not reviewable. The
work ships as a Graphite stack instead, one pull request per task boundary, because each
task was already built and reviewed as a unit and therefore compiles on its own.

**Requirements:**
- Fetch and restack onto `origin/main` with `rebase.gpgSign=true`.
- Run `make test`, `make build`, `make format-check`, `make log-audit`, `make launch-agent-audit`, `make run-audit`, `make verify`, and `make run`.
- Re-run the end-to-end targets after the restack.
- Verify each commit in `origin/main..HEAD` with `git verify-commit` and confirm its raw `gpgsig` header.
- Run a whole-branch code review and fix all load-bearing findings.
- Give each pull request in the stack its own description covering only that slice. The
  bottom slice carries the narrative: the original stuck UI and the production ownership
  defect it fixes.
