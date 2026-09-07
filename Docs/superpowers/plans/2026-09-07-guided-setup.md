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
| 2026-09-07 | fan56-guided-setup | Approval observation and pending upgrade | Codex adversarial review | NOT-READY: pending setup blocks Agent upgrade | 1/0/0 | Approval observation gap found during root's installed acceptance | Reviewed passive approval reconciliation and bounded app observation. Read combined xcresult: all four real-XPC approval cases passed; 122 of 123 tests passed. Added pending-upgrade regression and mutation/cancellation control. Confirmed outdated Agent replacement returned zero attempts during restored pending setup; its expected-failure report then crashed XCTest. The mutation/cancellation control passed. Both model refresh guards still suppress upgrade solely because setup owns lifecycle. No product edits or concurrent Make from this pass. |
| 2026-09-07 | fan56-guided-setup | Lifecycle, concurrency, visible setup | Codex adversarial review | NOT-READY: final gates and installed acceptance pending | 2/2/0 | None established | Corrected stale command observations, Settings repair bypass, and host-default test dependency. Removing notFound admission produced 19 failed assertions across five cases including real XPC approval readback. Removing the fresh-state read produced seven failed assertions across three setup cases; unchanged cases passed. Restored both changes, deleted the exact test executable, rebuilt, and ran make test-agent: 115 tests passed. Later source review confirmed injected legacy repair isolates guided tests while preserving the production default. Converted the XPC case to synchronous Nimble assertions without suppressions. These later edits await root's final gates. Fetched merge-tree and diff whitespace checks passed. Root owns SIP-enabled guest acceptance. |
