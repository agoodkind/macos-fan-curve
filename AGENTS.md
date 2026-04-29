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
- Use `make test` for tests.
- Use `make dmg` or `make release-assets` for distributable artifacts.
- Keep derived data and products on the configured Makefile paths: `build/` and `Products/`.
- Do not hand-edit generated Xcode project or workspace files as source of truth.
- Before handing off a code change, run the narrowest Make target that proves the change. Use `make test` when behavior changed, `make build` when compilation is the proof, and `make log-audit` when logging changed.
- If a required verification cannot be run, state the exact command that was skipped and why.
