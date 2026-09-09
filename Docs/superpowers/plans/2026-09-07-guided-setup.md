# Complete guided setup implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to execute the tasks with behavioral verification.

**Goal:** Complete fresh background-control setup through one resumable action.

**Architecture:** Share the app's installation model across scenes. Keep Agent-owned Helper mutation and add explicit persisted setup intent, separate from live observations and active operations.

**Tech Stack:** Swift, SwiftUI, Combine, ServiceManagement, Agent XPC, Tuist, Make.

**Spec:** [Approved guided setup design](../specs/2026-09-07-guided-setup-design.md).

## Global constraints

- Preserve app-to-Agent-to-Helper ownership.
- Use `/Applications/Fan Curve.app` as the installed runtime path.
- Do not add shell tests or static text assertions.
- Do not override deliberate disable or approval requirements.
- Keep existing helper replacement and identity verification behavior.
- Use canonical Make targets and preserve VM evidence.

## Admit explicit first installation

Modify the existing Agent reconciler and its behavioral tests.

- [ ] Add failing cases for explicit `notFound`, invalid bundled artifact, approval, and identity mismatch.
- [ ] Run `make test-agent` and capture the expected failures.
- [ ] Admit `notFound` only for explicit forced repair; retain existing `notRegistered` journal recovery.
- [ ] Replace the unsupported missing-definition diagnosis with an observation-based message.
- [ ] Run `make test-agent` and confirm existing replacement and cancellation cases still pass.

## Own one resumable setup flow

Extend the installation model with these view-facing interfaces:

```swift
var setupActionTitle: String? { get }
var setupActionIsBusy: Bool { get }
func performSetupAction(agentClient: FanCurveAgentClient)
func beginSetup(agentClient: FanCurveAgentClient)
```

- [ ] Add Swift behavior cases for fresh Agent registration, approval, Helper continuation, relaunch, failure, and explicit disable.
- [ ] Persist unfinished setup intent and derive each next operation from current observations.
- [ ] Serialize user operations and stop automatic progression on failure.
- [ ] Make monitoring app-lifetime and idempotent.
- [ ] Run the focused tests through `make test`.

## Connect setup surfaces

- [ ] Create one installation model in the app and inject it into main and Settings scenes.
- [ ] Remove per-view model construction and timer shutdown.
- [ ] Replace onboarding and sidebar action branching with the shared action contract.
- [ ] Route Settings Enable through guided setup; preserve separate helper repair and approval controls.
- [ ] Extend the controlled service status with `notFound` and test its runtime mapping.
- [ ] Run `make test` and `make build`.

## Validate installed behavior

- [ ] Run `make verify` and `make run`; record exact outcomes.
- [ ] Run the logging gate provided by the current build engine; do not restore removed static audit dependencies.
- [ ] Build signed Release artifacts through `make release-assets`.
- [ ] Enable SIP in preserved fresh macOS 15 and 26 clones using Recovery, then verify `csrutil status` after normal boot.
- [ ] Repeat fresh-install and upgrade acceptance in those guests and preserve the original failing guests.
- [ ] Obtain adversarial review of lifecycle, approval, persistence, concurrency, and UI transitions.
- [ ] Commit only the scoped, verified changes with signed commits.

## Review

| Date | Branch | Class | Reviewer | Verdict | Catches B/SF/N | Escapes | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-09-07 | fan56-guided-setup | Lifecycle, concurrency, visible setup | Codex adversarial review | Corrected findings; 126 Agent tests passed | 4/2/0 | Approval observation gap found during installed acceptance | Reviewed corrections for stale command observations, Settings repair bypass, test isolation, passive approval observation, and pending-upgrade suppression. The final connection guard waits for a replacement XPC connection, not the paused heartbeat hash. A real NSXPC reconnect test reaches complete with no heartbeat identity injected. Restoring the prior hash guard failed both no-heartbeat cases; restoring the connection guard passed all 126 tests. Final lint and installed-candidate gates remain parent-owned. |
| 2026-09-07 | fan56-guided-setup | Installed acceptance | Codex adversarial review | NOT-READY | 0/0/0 | Existing macOS 15 GPU telemetry crash | Both SIP-enabled guests reached verified Helper identity and persisted complete setup on the preceding candidate. macOS 26 reached the dashboard; macOS 15 then crashed in existing GPU telemetry. Release packaging and forced make run passed before the connection-guard follow-up. Four make verify settings assertions also fail on unchanged main. The final connection-guard candidate still needs installed acceptance. |
