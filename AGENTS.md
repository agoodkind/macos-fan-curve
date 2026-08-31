# Agent Instructions

These instructions are strict project rules for all automated coding agents working in this repository.

## Logging

- Add structured logging at every meaningful logic boundary: entry and exit of workflows, state transitions, external process calls, permission checks, I/O boundaries, error paths, recovery paths, and user-visible actions.
- Use the project logging abstraction only. Do not add `print`, `NSLog`, direct `os_log`, or ad hoc logger instances.
- Log enough context to diagnose behavior without exposing secrets, tokens, private user data, or noisy high-cardinality values.
- Log failures with the operation, reason, and recovery decision. Do not swallow errors silently.
- When adding a new subsystem or service, define its logging category up front and keep messages consistent.
- Run `make log-audit` after touching Swift logging or adding new Swift files.

## Code Quality

- Keep code clean, direct, and local to the responsibility being changed.
- Prefer small, named functions over long inline blocks when a boundary has a distinct purpose.
- Remove duplication when it hides behavior or creates drift, but do not refactor unrelated code opportunistically.
- Keep side effects explicit. Separate pure decisions from I/O, process execution, UI updates, and persistence.
- Use clear names that describe domain behavior. Avoid vague names such as `data`, `item`, `thing`, `manager`, or `helper` when a domain term exists.
- Keep comments rare and useful. Explain non-obvious intent, constraints, or invariants rather than restating code.

## File Headers

- New Swift files get an Xcode-style header. Run `git config user.name` and `git config user.email`, then stamp `Created by <name> <<email>> on YYYY-MM-DD`.
- Do not copy a commit `Co-authored-by` identity into a file header. Do not hardcode a person name.

## Strong Types

- Model domain concepts with strong types instead of strings, dictionaries, tuples, or loosely typed primitives.
- Prefer enums for closed state, dedicated structs for data crossing boundaries, and typed identifiers for IDs.
- Avoid force unwraps, implicit assumptions, and broad optional plumbing. Validate once at the boundary and pass typed values inward.
- Make invalid states unrepresentable where practical.
- Preserve Swift concurrency and isolation correctness. Do not bypass actor isolation or sendability requirements to quiet the compiler.

## Fan Curve Runtime Semantics

- Treat the blue curve as the base temperature curve only. It must not silently include assist, boost, acoustic damping, firmware behavior, or any other controller layer.
- Keep runtime marker truth explicit. `Fan Now` is actual fan state: current live thermal input on X and actual RPM percent on Y. `Thermal Demand` is pre-acoustic-governor demand: the current demand input on X and desired percent on Y.
- Do not pin `Thermal Demand` to the blue curve. Assist, boost, or controller demand may place it off-curve. That off-curve state is meaningful and must be rendered intentionally.
- Draw the demand leash from `Fan Now` to `Thermal Demand`. Do not draw the demand leash from `Thermal Demand` to the blue curve anchor.
- Keep `Fan Now` as the filled orange dot with its crosshair guides. Keep `Thermal Demand` as a hollow orange dot with no crosshair guides; its only guide is the leash to `Fan Now`.
- Do not reintroduce an automatic emergency ramp path, emergency controller mode, or emergency demand source. User-initiated Boost may exist, but it must remain semantically Boost rather than masquerading as emergency.
- Any fast swing in either direction is bad. Upward and downward fan changes must both respect acoustic damping unless the user explicitly changes that product requirement.
- Smooth actual fan commands in the controller, not only in the UI. Visual smoothing is allowed only as presentation; it must never feed back into fan commands or snapshots.
- Visual smoothing must stay close enough to truth that markers do not look detached or nonsensical. Avoid solutions that hide real state by letting display state drift far from actual fan RPM or demand.
- Avoid snapshot-cadence motion artifacts such as jump-pause-jump. Marker motion should look continuous even when agent snapshots arrive discretely.
- Prefer higher-order smoothing for live markers when changing motion behavior: `Thermal Demand` should be smoother than raw demand, and `Fan Now` should be smoother still, while both remain bounded near truth.
- Preserve high-FPS SwiftUI interpolation where it improves perceived smoothness. Do not replace it with low-rate polling-only motion unless the replacement is proven smoother in foreground and background.
- The temperature axis, grid lines, tick labels, control points, curve drawing, hit testing, and fan command application must share the same `TemperatureAxisScale` mapping. Do not create split-brain linear or ad hoc temperature placement.
- The curve control-point dots are fixed, evenly spaced columns on the X axis. Change the temperatures assigned to those columns through `TemperatureAxisScale`; do not move the columns themselves or introduce ad hoc per-view dot spacing.
- The default temperature axis should compress the low-temperature range where fans usually stay at 0% and assign progressively tighter temperature spans to the hot range where fan control needs more precision.

## App, Agent, And Helper Architecture

- The intended runtime architecture is:

  ```text
  Fan Curve.app  <->  FanCurveAgent XPC  <->  Privileged Helper XPC
       |
       | one-time bootstrap only
       v
  SMAppService registration / System Settings approval for FanCurveAgent
  ```

- `Fan Curve.app` may directly bootstrap the Background Agent because the agent XPC endpoint does not exist until the agent is registered, approved, and running.
- This bootstrap exception is limited to Background Agent lifecycle setup: checking `SMAppService` status, registering or unregistering the agent, opening System Settings approval, and showing the Background Agent setup UI.
- The app must not use this exception for runtime behavior after the agent is available.
- Runtime telemetry, helper status, curve control, boost, apply-in-background, and fan-control commands should flow through app-facing Agent XPC.
- The app must not directly probe or command the privileged helper for normal product flows. The agent owns helper communication and translates helper state into product-level runtime state.
- Shared defaults may persist user preferences, but they should not be treated as the primary live app-agent runtime bus once the XPC path exists.

## Tuist, Build, And Verification

- This is a Tuist project. `Project.swift`, `Workspace.swift`, `Tuist.swift`, and `Tuist/Package.swift` are the source of truth for Xcode structure and dependencies.
- Agents must use the repository Makefile as the canonical automation entry point. Do not manually run partial `tuist`, `xcodebuild`, Swift compiler, app launch, or packaging commands when a Make target exists.
- Use `make install-dependencies` to resolve Tuist dependencies.
- Use `make generate-project` to regenerate `FanCurveApp.xcworkspace`.
- Use `make build` for normal compilation. This runs icon generation, regenerates the Tuist workspace, and builds with the repository's configured `xcodebuild` path.
- `/Applications/Fan Curve.app` is the single canonical run, debug, and install location. The `SMAppService` daemon and login-item agent register from that one path, so the app runs from there and nowhere else. Do not introduce a second run or install location.
- Use `make app` for the Release app artifact. It builds Release into `build/` and stages `Products/Fan Curve.app` for `make dmg` and packaging.
- Use `make run` for local development. It builds the Debug configuration, copies the build to `/Applications/Fan Curve.app`, and launches that copy.
- Use `make install-app` to install the Release build to `/Applications/Fan Curve.app`.
- Xcode builds to DerivedData and the Play button runs that copy for debugging. To debug the running app, run `make run` and attach Xcode (lldb) to the `/Applications/Fan Curve.app` process; the Debug build carries `com.apple.security.get-task-allow`, so the attach succeeds. The background agent is a separate process you attach to the same way. The privileged helper is a hardened-runtime root `LaunchDaemon` and is not a normal Xcode attach target. A Debug build launched from DerivedData does not register login items, so it cannot create a second registration path.
- Use `make launch-agent-audit` for launch agent, login item, bundle, or install path changes.
- Use `make run-audit` after touching `Makefile` run, install, launch, login item, or agent behavior.
- Use `make verify` before handing off launch agent, login item, bundle, install path, or run path changes. It runs the required project-specific guard checks plus tests.
- Use `make test` for tests.
- Use `make dmg` or `make release-assets` for distributable artifacts.
- Keep derived data in `build/` and the Release staging artifact in `Products/`. `make run` deploys the Debug build to `/Applications/Fan Curve.app`.
- Do not hand-edit generated Xcode project or workspace files as source of truth.
- Before handing off a code change, run the narrowest Make target that proves the change. Use `make test` when behavior changed, `make build` when compilation is the proof, and `make log-audit` when logging changed.
- After making a code change, also run `make run` before handing off so the Debug app is built, deployed to `/Applications/Fan Curve.app`, and launched. Report the `make run` result to the user.
- If a required verification cannot be run, state the exact command that was skipped and why.

## Completion Evidence

- Final responses must list the exact verification commands run and whether each passed, failed, or was skipped.
- Final responses after code changes must include the `make run` result, or explicitly state that `make run` was skipped and why.
- Do not say a task is fixed, complete, working, or verified unless the relevant Make target passed in the current worktree.
- If a command fails, report the first concrete failure and the next required fix. Do not bury failing verification under a general success summary.

## Launch Agent And Install Path Guardrails

- `SMAppService.agent(plistName:)` owns login item registration. Do not manually bootstrap, bootout, kickstart, or copy launch agent plists as part of the normal `make run` path.
- `make run` builds the Debug configuration, copies it to `/Applications/Fan Curve.app`, and opens that app. It must not copy into `~/Library/LaunchAgents` or call `launchctl`; `SMAppService` owns login-item registration.
- The app-bundled launch agent plist is generated from `Templates/Plists/agent-launchd.plist.template` by `Scripts/generate-config.sh`; do not duplicate plist generation logic in the Makefile.
- The bundled launch agent plist must use `BundleProgram` with the exact executable casing `Contents/MacOS/FanCurveAgent`.
- If an installed app or login item is stale, fix the app bundle generation and registration flow. Do not patch a stale user-level plist as the source of truth.
- Before changing launch agent behavior, inspect `Project.swift`, `Scripts/generate-config.sh`, `Templates/Plists/agent-launchd.plist.template`, and `Sources/Models/InstallationState.swift`.

## Common LLM Failure Paths

- Do not bypass canonical Make targets with direct `tuist`, `xcodebuild`, Swift compiler, app launch, or packaging commands when a Make target exists.
- Do not "fix" app execution by opening a manually discovered `.app` path. The one canonical runtime path is `/Applications/Fan Curve.app`, produced by `make run`; Xcode's Play button runs the DerivedData copy only for debugging.
- Do not "fix" login item issues by lowercasing executable names or by copying generated plists into user LaunchAgents.
- Do not weaken analyzer, formatter, logging, or audit rules to make a handoff pass unless the rule is demonstrably wrong for the project and the change is explicitly called out.
- Do not mark a speculative root cause as fact. State what was inspected, what failed, and what command proves the fix.
