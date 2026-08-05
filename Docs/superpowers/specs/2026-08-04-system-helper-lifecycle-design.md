# Heal the System Helper after upgrades

Fan Curve will identify, replace, and verify its active System Helper automatically.

## Define the problem

The current status combines two different conditions.

A reachable helper can run older code than the helper inside the installed app. General Settings calls that state `Reachable, registration needs repair`. Its detail then repeats that Fan Curve can reach the helper.

The current repair command reports acceptance before it verifies the active helper. The app then clears the error and stops the spinner. A failed replacement therefore leaves `repair needed` without a cause.

About shows FanCurve and FanCurveAgent identities. It cannot show the active System Helper version because the helper protocol exposes no identity.

## Set the goals

1. Distinguish an outdated helper from broken registration.
2. Replace an outdated helper automatically after an app upgrade.
3. Show the active System Helper version in About.
4. Make manual reinstall finish only after verified success or a visible failure.
5. Prove an old to new Sparkle upgrade in a Tart virtual machine.

## Limit the scope

The app will not contact the privileged helper directly.

The design will not add a second registration path. The Agent will continue to own helper communication and lifecycle changes.

The About view will not show the bundled helper version. It will show only the active version or `Unavailable`.

The design will not change fan curve, Boost, damping, or marker semantics.

The Tart guest will run no build, package, dependency, or Make command. The host will complete every artifact before copying it to the guest.

The repository will not add Tart runners, guest scripts, Make targets, or test artifact formats. A developer will perform the Tart validation by hand.

## Report active identity

The helper will expose a strongly typed identity through its existing XPC service.

The identity will contain:

- version
- build
- commit
- executable hash
- protocol version

The helper will initialize its build metadata from Fan Curve generated configuration. Its displayed version will therefore identify the active Fan Curve helper build.

The helper will calculate its own executable hash. The Agent will calculate the bundled helper hash from its installed app bundle.

The executable hash will decide whether replacement is required. Version text alone cannot distinguish rebuilt binaries with the same version.

An older helper will not implement the identity request. The Agent will confirm reachability through an existing helper operation before classifying it as outdated.

Every identity request will have a timeout and will honor task cancellation. A helper that never replies cannot block startup or manual repair indefinitely.

An enabled service whose identity and legacy reachability both fail will be `Unavailable`. The Agent will not assume the helper is outdated.

The service status will decide inactive states before identity or artifact checks. `notRegistered` will be `Registration Needs Repair`. `requiresApproval` will be `Approval Required`. `notFound` and unknown statuses will be `Unavailable` with their exact reason.

The upstream `macos-smc-fan` package will own the helper identity protocol and client support. Fan Curve will update its pinned package revision after that change lands.

## Reconcile one lifecycle

The Agent will own one System Helper reconciliation workflow.

The workflow will evaluate state after these triggers:

- Agent startup after an app or Agent upgrade
- Agent reconnect after helper loss
- automatic recovery after Sparkle relaunch
- forced repair from `Reinstall System Helper`

The App will continue to replace an outdated Agent first. The new Agent will then reconcile the helper before it starts fan-control ticks.

A verified Agent hash mismatch will refresh the Agent registration even while the old Agent XPC connection remains open. The App will throttle another refresh until the new Agent publishes its hash or the retry interval expires.

Sparkle will not install the helper itself. Sparkle will install and relaunch Fan Curve. The normal Agent startup path will provide automatic healing for every installation source.

Automatic mutation will require a reachable outdated or legacy helper. An unreachable, denied, or unregistered helper will keep its repair or approval state.

The Agent will publish reconciliation progress before fan control starts. The App can therefore show `Checking` or `Updating` without probing the helper.

## Replace safely

The Agent will validate the bundled helper before changing the active service.

Preflight will verify the helper exists, can be hashed, and satisfies the expected signing requirement. A preflight failure will preserve the current registration.

The Agent will validate the bundled helper again immediately before registration. Registration will stop if its full identity differs from the preflight identity.

Before replacement, the Agent will stop fan-control ticks. It will use the existing bounded reset-to-auto safety boundary for every discovered fan.

A reset failure will stop replacement. The existing helper will remain registered.

After a successful reset, the Agent will close its helper XPC connection. This releases the active launchd reference before registration changes.

The Agent will await confirmed unregistration before registering the bundled helper. Apple requires this sequence because `register()` rejects an existing registration.

The Agent will reconnect with bounded retries. It will report success only when the active executable hash matches the bundled hash.

Fan-control ticks will resume only after verified success. A failure after unregistration will leave fans in automatic mode and keep control paused.

## Model visible state

The Agent will publish a typed System Helper state. The App will derive copy and controls from that state.

The visible states are:

- `Checking`: The Agent is verifying the active helper.
- `Running`: Registration, connection, and identity match.
- `Updating`: Automatic replacement is active.
- `Outdated`: The active and bundled identities differ.
- `Registration Needs Repair`: Registration is broken.
- `Approval Required`: macOS requires user approval.
- `Repair Failed`: A repair stage failed.
- `Unavailable`: No active helper identity exists.

Each detail will explain only the unmet condition. Reachability text will not repeat the status.

An outdated detail may show both versions because the mismatch explains the required action. About will still show only the active version.

## Preserve failures

Each failure will identify its operation, stage, reason, and recovery action.

Stages will include preflight, fan reset, disconnect, unregister, register, reconnect, and identity verification.

`Reinstall System Helper` will remain busy until the reconciliation reaches a terminal state. It will return a verified result instead of an accepted command.

The App will retain the exact failure until a later attempt succeeds or a new attempt replaces it. Refresh will not clear an unresolved error.

The Agent and App will log workflow entry, state changes, external calls, failures, and recovery decisions. Logs will use the project logging abstraction and exclude private data.

## Show the active version

About will add a `System Helper` row.

The row will show the active helper version reported through Agent runtime state. It will show `Unavailable` when the Agent cannot read an active identity.

The binary diagnostics will include the active helper executable hash when available.

## Verify public behavior

Tests will enter through public product boundaries and assert visible outcomes.

Focused tests will cover:

1. The helper client reads identity through a real XPC serialization boundary and terminates on timeout, cancellation, or a legacy interface.
2. The Agent classifies current, outdated, legacy, unregistered, missing, unknown, and approval states.
3. The Agent command returns only after final identity verification.
4. A registration failure remains visible after clicking `Reinstall System Helper`.
5. The spinner remains visible during work and stops at a terminal result.
6. About shows the active version or `Unavailable`.

Tests may replace the unavailable Service Management boundary with one stateful fake. They will keep real state transitions, Agent XPC transport, decoding, and UI behavior.

Tests will not assert source text, implementation call order, or collaborator counters. These checks would not prove user-visible behavior.

## Prove the Sparkle upgrade

Manual release acceptance will use a disposable Tart virtual machine.

The developer will set `TART_HOME` to the external-volume directory specified by the
[validation procedure](../../validation.md). That procedure owns the host-specific path.

The developer will clone the cached non-Xcode `macos-tahoe-base` image. The guest will not receive Xcode or repository source.

The developer will build, package, and sign the old and new Release artifacts on the host through existing Make targets. The developer will also prepare the signed Sparkle appcast and update archive on the host.

The developer will copy only completed artifacts into the guest. The guest will not invoke a Make target, compiler, package tool, dependency resolver, or appcast generator.

The developer will serve the temporary signed Sparkle feed from the host and connect the old app to it for this manual run.

The developer will install the old app at `/Applications/Fan Curve.app` using the [validation procedure](../../validation.md). The developer will verify the app signature before launch.

The acceptance flow will:

1. Copy the completed host artifacts into the guest.
2. Install and approve the old Agent and System Helper.
3. Record the active helper version, hash, signature, process, and launchd state.
4. Start the upgrade through Sparkle.
5. Let Sparkle relaunch Fan Curve.
6. Verify automatic Agent replacement.
7. Verify automatic System Helper replacement.
8. Verify About shows the new active helper version.
9. Verify General Settings shows `Running`.
10. Preserve logs, launchd output, signatures, and screenshots.

The developer will keep generated apps, update archives, certificates, logs, and screenshots outside version control.

The automatic acceptance flow will not click `Reinstall System Helper`.

A separate acceptance step will click `Reinstall System Helper` on a healthy install. It will verify a completed replacement and a final `Running` state.

## Apply repository rules

The implementation plan, code, and tests will apply `enforce-rules`.

Every finding will state whether evidence is verified, inferred, or assumed. Code will not proceed when current evidence disproves its premise.

Lifecycle, concurrency, and visible behavior changes require strongest-model adversarial review before merge.

Swift logging changes require `make log-audit`.

Agent and registration changes require `make launch-agent-audit`, `make run-audit`, and `make verify`.

Behavior changes require `make test`. Final handoff requires `make run` and its deployment result.

The manual Tart acceptance checklist must pass before the upgrade path is called verified.

## Accept the result

The change is complete when all of these statements are proven:

- A reachable old helper is `Outdated`, not a registration failure.
- A broken registration has different copy and recovery.
- Sparkle relaunch replaces the helper without manual action.
- About shows the new active helper version.
- Manual reinstall shows verified success or a durable error.
- Fan control never resumes through an unverified helper.
- Required Make targets pass.
- The Tart old to new upgrade passes with preserved evidence.
