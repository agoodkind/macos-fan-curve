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
- The temperature axis should compress tails and expand common operating temperatures around the chosen center. Minor ticks/grid lines should reveal the non-linear scale density on both compressed sides.

## Tuist, Build, And Verification

- This is a Tuist project. `Project.swift`, `Workspace.swift`, `Tuist.swift`, and `Tuist/Package.swift` are the source of truth for Xcode structure and dependencies.
- Agents must use the repository Makefile as the canonical automation entry point. Do not manually run partial `tuist`, `xcodebuild`, Swift compiler, app launch, or packaging commands when a Make target exists.
- Use `make install-dependencies` to resolve Tuist dependencies.
- Use `make generate-project` to regenerate `FanCurveApp.xcworkspace`.
- Use `make build` for normal compilation. This runs icon generation, regenerates the Tuist workspace, and builds with the repository's configured `xcodebuild` path.
- Use `make app` for the standard local app artifact. It builds and stages `Products/FanCurve.app`.
- Use `make run` to launch the local app artifact. Do not launch from derived data manually.
- Use `make install-user` to copy the app into `~/Applications`.
- Use `make install-app` only when an explicit `/Applications` install is required.
- Use `make run-installed` only when testing the user-installed app path.
- Do not make `make run` copy into `/Applications` or manually restart the login agent. The app owns `SMAppService` registration and refresh.
- Use `make launch-agent-audit` for launch agent, login item, bundle, or install path changes.
- Use `make run-audit` after touching `Makefile` run, install, launch, login item, or agent behavior.
- Use `make verify` before handing off launch agent, login item, bundle, install path, or run path changes. It runs the required project-specific guard checks plus tests.
- Use `make test` for tests.
- Use `make dmg` or `make release-assets` for distributable artifacts.
- Keep derived data and products on the configured Makefile paths: `build/` and `Products/`.
- Do not hand-edit generated Xcode project or workspace files as source of truth.
- Before handing off a code change, run the narrowest Make target that proves the change. Use `make test` when behavior changed, `make build` when compilation is the proof, and `make log-audit` when logging changed.
- After making a code change, also run `make run` before handing off so the local app artifact is built, staged, and launched from the canonical path. Report the `make run` result to the user.
- If a required verification cannot be run, state the exact command that was skipped and why.

## Completion Evidence

- Final responses must list the exact verification commands run and whether each passed, failed, or was skipped.
- Final responses after code changes must include the `make run` result, or explicitly state that `make run` was skipped and why.
- Do not say a task is fixed, complete, working, or verified unless the relevant Make target passed in the current worktree.
- If a command fails, report the first concrete failure and the next required fix. Do not bury failing verification under a general success summary.

## Launch Agent And Install Path Guardrails

- `SMAppService.agent(plistName:)` owns login item registration. Do not manually bootstrap, bootout, kickstart, or copy launch agent plists as part of the normal `make run` path.
- `make run` must build/stage `Products/FanCurve.app` and open that app. It must not install into `/Applications`, copy into `~/Library/LaunchAgents`, or call `launchctl`.
- The app-bundled launch agent plist is generated from `Templates/Plists/agent-launchd.plist.template` by `Scripts/generate-config.sh`; do not duplicate plist generation logic in the Makefile.
- The bundled launch agent plist must use `BundleProgram` with the exact executable casing `Contents/MacOS/FanCurveAgent`.
- If an installed app or login item is stale, fix the app bundle generation and registration flow. Do not patch a stale user-level plist as the source of truth.
- Before changing launch agent behavior, inspect `Project.swift`, `Scripts/generate-config.sh`, `Templates/Plists/agent-launchd.plist.template`, and `Sources/Models/InstallationState.swift`.

## Common LLM Failure Paths

- Do not bypass canonical Make targets with direct `tuist`, `xcodebuild`, Swift compiler, app launch, or packaging commands when a Make target exists.
- Do not "fix" app execution by launching from DerivedData or by opening a manually discovered `.app` path.
- Do not "fix" login item issues by lowercasing executable names, hardcoding app paths, or copying generated plists into user LaunchAgents.
- Do not weaken analyzer, formatter, logging, or audit rules to make a handoff pass unless the rule is demonstrably wrong for the project and the change is explicitly called out.
- Do not mark a speculative root cause as fact. State what was inspected, what failed, and what command proves the fix.
