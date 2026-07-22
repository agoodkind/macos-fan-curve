# Gated Make Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route `make run` through the required Debug build gate before installing and launching Fan Curve.

**Architecture:** The project-owned `run` target will invoke a recursive `CONFIGURATION=Debug build`, which runs `swift-mk` gates and reaches the existing `app-local` staging flow under a live Make ancestor. The run audit will enforce that gated route while preserving the canonical deployment checks.

**Tech Stack:** GNU Make, Swift audit script, `swift-mk`, Tuist, Xcode.

## Global Constraints

- Keep `/Applications/Fan Curve.app` as the only install and launch path.
- Keep `SMAppService` ownership of login-item registration.
- Do not change `swift-makefile`, gate-proof semantics, or app source.
- Preserve the existing copy, termination, and launch commands.
- Let the recursive build validate shared `swift-makefile` files normally.
- Leave the untracked Boost button plan unchanged.

---

### Task 1: Enforce and use the gated Debug build

**Files:**

- Modify: `Scripts/AuditMakeRun.swift:54-56`
- Modify: `Makefile:146-151`

**Interfaces:**

- Consumes: the shared `build` target supplied by `swift-build.mk` and the existing `SWIFT_BUILD_CMD` that reaches `app-local`.
- Produces: a `run` recipe containing `CONFIGURATION=Debug build`, plus an audit that rejects direct `CONFIGURATION=Debug app-local` compilation.

- [ ] **Step 1: Tighten the audit before changing the Makefile**

Replace the current build-route guard with:

```swift
guard body.contains("CONFIGURATION=Debug build") else {
    try fail("run-audit failed: make run must build the Debug configuration through the gated build target")
}

guard !body.contains("CONFIGURATION=Debug app-local") else {
    try fail("run-audit failed: make run must not compile through app-local directly")
}
```

- [ ] **Step 2: Prove the updated audit rejects the current recipe**

Run `make run-audit`.

Expected: FAIL with `make run must build the Debug configuration through the gated build target`.

- [ ] **Step 3: Route the Debug compile through the gate**

Change the first `run` recipe command to:

```make
	$(MAKE) CONFIGURATION=Debug build
```

Keep the following `rm`, `cp`, `TerminateAppInstances.swift`, and `open` commands unchanged.

- [ ] **Step 4: Prove the run audit passes**

Run `make run-audit`.

Expected: PASS with `run-audit: ok`.

- [ ] **Step 5: Build, deploy, and launch through the repaired target**

Run `make run`.

Expected: the gates pass, the Debug app builds, `/Applications/Fan Curve.app` is replaced, and the app launches.

- [ ] **Step 6: Confirm the canonical process is running**

Run:

```bash
pgrep -fl '^/Applications/Fan Curve.app/Contents/MacOS/FanCurve$'
```

Expected: one running Fan Curve application process at the canonical path.

- [ ] **Step 7: Run full project verification**

Run `make verify`.

Expected: launch-agent audit, run audit, settings layout audit, log audit, and tests all pass.

- [ ] **Step 8: Commit the repair**

Stage `Makefile` and `Scripts/AuditMakeRun.swift`, then commit with subject `Route make run through gated Debug build` and the Codex co-author trailer.
