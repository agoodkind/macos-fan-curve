# System Helper Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically replace an outdated System Helper after app upgrades, distinguish lifecycle failures, show the active helper version, and make manual repair return a verified result.

**Architecture:** The upstream helper exposes immutable build identity through its existing privileged XPC service. FanCurveAgent owns one serialized reconciler that classifies identity, validates the bundled executable, resets fans to automatic mode, replaces registration, reconnects, and verifies the active hash before fan control resumes. Fan Curve renders the Agent's typed state and never probes the helper directly.

**Tech Stack:** Swift 6, SwiftUI, NSXPCConnection, ServiceManagement, Sparkle 2, XCTest, XCUITest, Tuist, Make, Tart, launchd, and Apple code signing.

## Global Constraints

- Apply `enforce-rules` to every code, test, review, and verification step.
- Work in an isolated feature worktree under the repository's path-based `~/.worktrees` directory. Do not modify the primary checkout.
- Create the upstream helper worktree under its path-based `~/.worktrees` directory from `origin/main`.
- Fetch before every branch comparison, merge base, log range, tag, or release decision.
- Preserve `Fan Curve.app <-> FanCurveAgent XPC <-> System Helper XPC` ownership.
- Keep `/Applications/Fan Curve.app` as the only installed and launched app.
- Use the repository Makefile for builds, tests, deployment, and release artifacts.
- Use test driven development. Run each named failing test before implementation.
- Test public behavior. Do not add source text tests, call order assertions, or stacks of mocks.
- Use one stateful fake only at the unavailable Service Management boundary.
- Add structured project logging at workflow entry, state transitions, external calls, error paths, recovery paths, and user actions.
- Never log secrets, signing material, private paths from users, or unbounded identifiers.
- Keep fan curve, Boost, damping, marker, and controller demand semantics unchanged.
- Reset every discovered fan to automatic mode before helper mutation.
- Abort before unregister when preflight or fan reset fails.
- Keep control paused when replacement fails after unregister.
- Treat executable hash equality as the currentness proof.
- Treat a reachable helper without the identity method as legacy and outdated.
- Bound every helper identity request and honor task cancellation.
- Never classify an unreachable helper as outdated.
- Keep the manual spinner active until verified success or a terminal failure.
- Preserve a terminal failure until a new attempt replaces it or a verified attempt succeeds.
- Show only the active helper version in About. Show `Unavailable` without active identity.
- Sign every commit with `git commit -S` and include `Co-authored-by: Codex <noreply@openai.com>`.
- Run strongest model adversarial review for the XPC, lifecycle, concurrency, and visible behavior changes.
- Do not call the upgrade path verified until the signed Tart Sparkle acceptance passes.
- Run every build, package, dependency, appcast, and Make command on the host.
- Copy only completed and verified artifacts into the Tart guest.
- Let the Tart guest install, launch, approve, upgrade, inspect, and collect evidence only.
- Do not install Xcode or copy the source worktrees into the Tart guest.
- Do not add Tart runners, guest scripts, Make targets, test fixtures, or artifact formats.
- Run Tart acceptance manually through `Docs/validation.md`.
- Keep Tart artifacts and evidence outside version control.

## File Map

### Upstream `macos-smc-fan`

- Modify `Sources/AppLog/BuildInfo.swift` to include build number.
- Modify `Templates/Swift/Config.generated.swift.template`, `Sources/Common/Config.generated.swift`, and `Scripts/generate-config.sh` to generate version and build values.
- Modify `Config/debug.xcconfig` and `Config/release.xcconfig` to own required version and build settings.
- Modify `Sources/Helper/SMCFanHelperMain.swift` to initialize complete helper identity before logging starts.
- Modify `Sources/Common/SMCFanHelperProtocol.swift` to define identity and its primitive XPC reply.
- Modify `Sources/Helper/SMCFanHelper.swift` to return identity without opening the System Management Controller.
- Modify `Sources/SMCFanXPCClient/SMCFanXPCClient.swift` to request identity without `smcOpen`.
- Create `Tests/SMCFanXPCClientTests/HelperIdentityXPCTests.swift` for a real anonymous XPC boundary.
- Release tag `0.4.0` through `.github/workflows/release.yml`.

### Fan Curve runtime

- Modify `Tuist/Package.swift` and `Tuist/Package.resolved` to pin `macos-smc-fan` `0.4.0`.
- Modify `Templates/Swift/Config.generated.swift.template` and `Scripts/GenerateConfig.swift` to generate helper build metadata.
- Modify `Sources/SMCFanHelper/main.swift` to initialize upstream `BuildInfo`.
- Modify `Sources/Common/BuildFingerprint.swift` to hash the bundled helper.
- Create `Sources/Common/SystemHelperRuntimeState.swift` for the Agent to App wire contract.
- Modify `Sources/Common/RuntimeState.swift` to carry typed System Helper state.
- Modify `Tuist/ProjectDescriptionHelpers/ModelTestSources.swift` as each new Common or Models source gains model coverage.
- Modify `Sources/Agent/FanHardware.swift` and `Sources/Agent/XPCClient.swift` to expose identity, reachability, disconnect, and strict fan reset operations.
- Modify `Sources/Common/ManagedService.swift`, `Sources/Models/ServiceManagementAdapters.swift`, and `Sources/Agent/HelperServiceManagementAdapter.swift` to await unregister and register outcomes.
- Delete `Sources/Models/HelperServiceRegistration.swift` and `Tests/ModelTests/ManagedServiceTests.swift` after the reconciler replaces their behavior.
- Create `Sources/Agent/SystemHelperArtifactValidator.swift` for hash and signature preflight.
- Create `Sources/Agent/SystemHelperLifecycleReconciler.swift` for classification and mutation.
- Create `Sources/Models/SystemHelperFanResetSequencer.swift` for bounded, result preserving fan reset.
- Modify `Sources/Agent/AgentController.swift`, `Sources/Agent/FanCurveAgentXPCService.swift`, and `Sources/Agent/main.swift` to gate ticks and route repair.

### Fan Curve user interface and tests

- Modify `Sources/Models/InstallationState.swift` to consume typed helper state.
- Create `Sources/Models/SystemHelperPresentation.swift` for pure visible copy and actions.
- Modify `Sources/Views/GeneralSettingsView.swift` to render distinct states.
- Modify `Sources/Views/SensorDashboardSidebar+Setup.swift` and `Sources/Views/OnboardingView.swift` to use the same typed helper action.
- Modify `Sources/Views/AboutContentView.swift`, `Sources/Views/BuildHashes.swift`, and `Sources/App/FanCurveApp.swift` to show active helper identity.
- Modify `Sources/Common/AppAccessibilityIdentifier.swift` for stable helper status and About fields.
- Modify `Sources/TestControl/TestControlState.swift`, `Sources/TestControl/ControlledHelperServiceAdapter.swift`, `Sources/TestControl/ControlledFanHardware.swift`, and `Sources/TestControl/AgentTestControlAdapters.swift` to model helper identity and lifecycle results.
- Modify `Tests/ModelTests/SetupStateTests.swift` and add focused model tests.
- Modify `Tests/AgentTests/TestControlXPCIntegrationTests.swift` and `Tests/AgentTests/TestControlXPCIntegrationTests+Commands.swift`.
- Modify `Tests/FanCurveUITests/FanCurveUISetupTests.swift` and `Tests/FanCurveUITests/FanCurveUIControlTests.swift`.

### Tart release acceptance

- Modify `Docs/validation.md` to document the manual host build, guest copy, Sparkle upgrade, evidence, and cleanup procedure.

---

### Task 1: Add and release the upstream helper identity contract

**Files:**

- Modify: `Sources/AppLog/BuildInfo.swift`
- Modify: `Templates/Swift/Config.generated.swift.template`
- Modify: `Sources/Common/Config.generated.swift`
- Modify: `Scripts/generate-config.sh`
- Modify: `Config/debug.xcconfig`
- Modify: `Config/release.xcconfig`
- Modify: `Sources/Helper/SMCFanHelperMain.swift`
- Modify: `Sources/Common/SMCFanHelperProtocol.swift`
- Modify: `Sources/Helper/SMCFanHelper.swift`
- Modify: `Sources/SMCFanXPCClient/SMCFanXPCClient.swift`
- Create: `Tests/SMCFanXPCClientTests/HelperIdentityXPCTests.swift`

- [ ] **Step 1: Create the isolated upstream worktree**

Run:

```bash
git -C /Users/agoodkind/Sites/macos-smc-fan fetch --prune origin
mkdir -p /Users/agoodkind/.worktrees/-Users-agoodkind-Sites-macos-smc-fan
git -C /Users/agoodkind/Sites/macos-smc-fan worktree add \
  -b codex/system-helper-identity \
  /Users/agoodkind/.worktrees/-Users-agoodkind-Sites-macos-smc-fan/system-helper-identity \
  origin/main
```

Verify `git status --short` is empty in the new worktree.

- [ ] **Step 2: Write the failing real XPC serialization test**

Use an anonymous `NSXPCListener` with an exported object implementing the production protocol. Configure the client through an internal connection factory. Do not invoke a private decoder directly.

Add these public declarations to `SMCFanHelperProtocol.swift`:

```swift
public enum SMCFanHelperProtocolVersion {
  public static let identity: UInt = 1
}

public struct SMCFanHelperIdentity: Codable, Equatable, Sendable {
  public let version: String
  public let build: String
  public let commit: String
  public let executableHash: String
  public let protocolVersion: UInt

  public init(
    version: String,
    build: String,
    commit: String,
    executableHash: String,
    protocolVersion: UInt
  ) {
    self.version = version
    self.build = build
    self.commit = commit
    self.executableHash = executableHash
    self.protocolVersion = protocolVersion
  }
}
```

Add an `SMCFanHelperIdentityProtocol` containing this method. Make `SMCFanHelperProtocol` inherit from it. Keep primitive reply values across Objective C XPC:

```swift
@objc public protocol SMCFanHelperIdentityProtocol {
  func smcGetIdentity(
  reply: @escaping @Sendable (
    Bool,
    String,
    String,
    String,
    String,
    UInt,
    String?
    ) -> Void
  )
}

```

Change the existing helper protocol declaration to inherit from `SMCFanHelperIdentityProtocol`. Keep every existing operation in its current protocol body.

The tests must start listeners and connect the real client through XPC. Assert all five returned fields and zero `smcOpen` calls. Add a listener that withholds its reply and a legacy interface without `smcGetIdentity`. Assert timeout and cancellation both terminate the request.

Run:

```bash
make test
```

Expected: FAIL because `getHelperIdentity()` and the identity protocol method do not exist.

- [ ] **Step 3: Implement identity without opening the System Management Controller**

Add to `BuildInfo.swift`:

```swift
nonisolated(unsafe) public static var build = "unknown"
```

Keep the existing short diagnostic hash and add the full identity hash:

```swift
public static func executableHash() -> String {
  guard let executable = Bundle.main.executableURL,
    let bytes = try? Data(contentsOf: executable)
  else {
    return "unknown"
  }
  return SHA256.hash(data: bytes)
    .map { String(format: "%02x", $0) }
    .joined()
}

public static func buildHash() -> String {
  String(executableHash().prefix(12))
}
```

Add generated marketing version and build number values to both the template and the committed Swift Package Manager defaults. Substitute `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `generate-config.sh`.

Add these required values to both `Config/debug.xcconfig` and `Config/release.xcconfig` before the optional local include:

```xcconfig
MARKETING_VERSION = 0.4.0
CURRENT_PROJECT_VERSION = 1
```

Do not add shell defaults for either value.

Initialize `BuildInfo.version`, `BuildInfo.build`, `BuildInfo.commit`, and `BuildInfo.dirty` before `AppLog.bootstrap` in `SMCFanHelperMain.swift`. This keeps the standalone helper identity complete. Fan Curve will initialize the same fields from its generated app configuration in Task 2.

Implement the helper reply:

```swift
public func smcGetIdentity(
  reply: (
    Bool,
    String,
    String,
    String,
    String,
    UInt,
    String?
  ) -> Void
) {
  let identityHash = BuildInfo.executableHash()
  log.info(
    "helper.identity.returned protocol=\(SMCFanHelperProtocolVersion.identity, privacy: .public)"
  )
  reply(
    true,
    BuildInfo.version,
    BuildInfo.build,
    BuildInfo.commit,
    identityHash,
    SMCFanHelperProtocolVersion.identity,
    nil
  )
}
```

Add a client method that calls `ensureConnection()` directly. It must not call `ensureOpened()` or `ensureRegistered()`.

The request must use request-scoped state, a two-second deadline, `withTaskCancellationHandler`, and exactly-once completion. Timeout and cancellation must invalidate only the request-scoped connection.

Keep the normal initializer unchanged. Add an internal connection factory initializer only for the real anonymous XPC tests.

Log request entry, proxy failure, helper rejection, timeout or cancellation, and success through the project logging abstraction. Do not log the full executable hash.

- [ ] **Step 4: Prove the upstream contract**

Run on the host:

```bash
make test
make check
make release-build \
  RELEASE_TAG=0.4.0 \
  MARKETING_VERSION=0.4.0 \
  CURRENT_PROJECT_VERSION=1
```

Expected: PASS. Upstream `make check` owns logging enforcement through `swift-mk`.

- [ ] **Step 5: Commit, publish, and verify `0.4.0`**

Run:

```bash
git add Sources Templates Scripts Tests
git commit -S -m "$(printf '%s\n\n%s' \
  'Add System Helper identity protocol' \
  'Co-authored-by: Codex <noreply@openai.com>')"
git push -u origin codex/system-helper-identity
gh pr create \
  --repo agoodkind/macos-smc-fan \
  --base main \
  --head codex/system-helper-identity \
  --title 'Add System Helper identity protocol' \
  --body 'Adds typed identity through the existing helper XPC service. Verifies identity requests do not open the System Management Controller.'
gh pr checks --watch --fail-fast
gh pr merge --merge --delete-branch
git fetch --prune origin
git tag -s 0.4.0 origin/main -m "Release 0.4.0"
git push origin 0.4.0
release_run_id="$(gh run list \
  --repo agoodkind/macos-smc-fan \
  --workflow release.yml \
  --branch 0.4.0 \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"
test -n "$release_run_id"
gh run watch "$release_run_id" --repo agoodkind/macos-smc-fan --exit-status
git verify-commit HEAD
git verify-commit '0.4.0^{commit}'
git verify-tag 0.4.0
```

Confirm the GitHub release workflow succeeded before updating Fan Curve. Confirm tag `0.4.0` resolves to the reviewed signed merged commit.

---

### Task 2: Consume helper identity and generate downstream build metadata

**Files:**

- Modify: `Tuist/Package.swift`
- Modify: `Tuist/Package.resolved`
- Modify: `Templates/Swift/Config.generated.swift.template`
- Modify: `Templates/Plists/helper-info.plist.template`
- Modify: `Scripts/GenerateConfig.swift`
- Modify: `Makefile`
- Modify: `Sources/SMCFanHelper/main.swift`
- Modify: `Sources/Common/BuildFingerprint.swift`
- Modify: `Tuist/ProjectDescriptionHelpers/ModelTestSources.swift`
- Create: `Tests/ModelTests/BuildFingerprintTests.swift`

- [ ] **Step 1: Pin the released upstream API**

Change the package declaration to:

```swift
.package(
  url: "https://github.com/agoodkind/macos-smc-fan.git",
  exact: "0.4.0"
)
```

Run:

```bash
make install-dependencies
make generate-project
```

Verify `Tuist/Package.resolved` records version `0.4.0` and the signed release revision.

- [ ] **Step 2: Write failing metadata and bundled hash tests**

Add a temporary executable test for `BuildFingerprint.hash(of:)`. Assert the full 64 character SHA-256 value and a missing file error. The downstream helper identity will receive real XPC and Tart coverage in Tasks 5 and 9.

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/BuildFingerprintTests'
```

Expected: FAIL because the generator lacks `generatedBuildNumber` and the fingerprint API does not return a strict full hash.

- [ ] **Step 3: Generate and initialize helper identity**

Add to `Config.generated.swift.template`:

```swift
let generatedMarketingVersion = "@@MARKETING_VERSION@@"
let generatedBuildNumber = "@@BUILD_NUMBER@@"
```

Add this replacement in `GenerateConfig.swift`:

```swift
"@@MARKETING_VERSION@@": try requiredEnv("MARKETING_VERSION"),
"@@BUILD_NUMBER@@": try requiredEnv("CURRENT_PROJECT_VERSION"),
```

Define local development values in `Makefile` and pass both values through `GENERATE_CONFIG_ENV` and `XCODE_BUILD_SETTINGS`:

```make
MARKETING_VERSION ?= 0.0.0
CURRENT_PROJECT_VERSION ?= 0
```

Release jobs and the developer performing manual Tart validation must override both values explicitly. Replace the helper plist hardcoded version and build with `@@MARKETING_VERSION@@` and `@@BUILD_NUMBER@@`.

Initialize upstream metadata before logging in `Sources/SMCFanHelper/main.swift`:

```swift
BuildInfo.version = generatedMarketingVersion
BuildInfo.build = generatedBuildNumber
BuildInfo.commit = generatedGitCommit
BuildInfo.dirty = generatedGitDirty
AppLog.bootstrap(subsystem: "io.goodkind.fan")
SMCFanHelper(machServiceName: generatedHelperBundleID).start()
```

Refactor `BuildFingerprint` to expose strict full hashes for lifecycle comparison and short hashes only for presentation:

```swift
enum BuildFingerprintError: LocalizedError {
  case executableUnreadable(String)
}

static func hash(of url: URL) throws -> String {
  let bytes: Data
  do {
    bytes = try Data(contentsOf: url)
  } catch {
    throw BuildFingerprintError.executableUnreadable(error.localizedDescription)
  }
  return SHA256.hash(data: bytes)
    .map { String(format: "%02x", $0) }
    .joined()
}

static var bundledHelperURL: URL {
  Bundle.main.bundleURL
    .appendingPathComponent("Contents/MacOS/\(generatedHelperBundleID)")
}
```

`Project.swift` names the target `SMCFanHelper`, sets its product name to `generatedHelperBundleID`, and embeds that executable in `Contents/MacOS`.

- [ ] **Step 4: Prove and commit downstream identity wiring**

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/BuildFingerprintTests'
make build
make log-audit
```

Inspect the built helper with `codesign -dvvv` and its generated plist with `plutil -p`. Confirm its version and build match generated configuration.

Commit:

```bash
git add Tuist Templates Scripts Sources Tests
git commit -S -m "$(printf '%s\n\n%s' \
  'Consume System Helper identity' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 3: Add the typed System Helper state and pure classification

**Files:**

- Create: `Sources/Common/SystemHelperRuntimeState.swift`
- Modify: `Sources/Common/RuntimeState.swift`
- Create: `Sources/Models/SystemHelperClassifier.swift`
- Test: `Tests/ModelTests/SystemHelperClassifierTests.swift`
- Modify: `Tests/ModelTests/SetupStateTests.swift`
- Modify: `Tuist/ProjectDescriptionHelpers/ModelTestSources.swift`

- [ ] **Step 1: Write the failing classification matrix**

Cover these observable outcomes through `RuntimeState.resolve`:

| Service status | Identity result | Legacy probe | Bundled hash match | Expected state |
| --- | --- | --- | --- | --- |
| enabled | identity | not used | yes | `running` |
| enabled | identity | not used | no | `outdated` |
| enabled | identity failure | succeeds | no identity | `outdated` |
| enabled | failure | fails | unknown | `unavailable` |
| not registered | not attempted | not attempted | unknown | `registrationNeedsRepair` |
| approval required | not attempted | not attempted | unknown | `approvalRequired` |
| not found | not attempted | not attempted | unknown | `unavailable` |
| unknown | not attempted | not attempted | unknown | `unavailable` |

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperClassifierTests'
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SetupStateTests'
```

Expected: FAIL because runtime state has only the generic helper requirement.

- [ ] **Step 2: Add the wire contract**

Create these strong types:

```swift
struct SystemHelperIdentity: Codable, Equatable, Sendable {
  let version: String
  let build: String
  let commit: String
  let executableHash: String
  let protocolVersion: UInt
}

enum SystemHelperOperation: String, Codable, Equatable, Sendable {
  case automaticUpdate
  case forcedRepair
}

enum SystemHelperFailureStage: String, Codable, Equatable, Sendable {
  case preflight
  case fanReset
  case disconnect
  case unregister
  case register
  case reconnect
  case identityVerification
}

struct SystemHelperFailure: Codable, Equatable, Sendable {
  let operation: SystemHelperOperation
  let stage: SystemHelperFailureStage
  let reason: String
  let recovery: String
}

enum SystemHelperRuntimeState: Codable, Equatable, Sendable {
  case checking
  case running(active: SystemHelperIdentity)
  case updating(active: SystemHelperIdentity?, bundled: SystemHelperIdentity)
  case outdated(active: SystemHelperIdentity?, bundled: SystemHelperIdentity)
  case registrationNeedsRepair(reason: String)
  case approvalRequired
  case repairFailed(
    active: SystemHelperIdentity?,
    bundled: SystemHelperIdentity?,
    failure: SystemHelperFailure
  )
  case unavailable(reason: String)
}
```

Add computed properties `activeIdentity`, `setupRequirement`, and `permitsFanControl`. Keep their mapping in this type so setup, health, UI, and reconciliation cannot drift.

Add `systemHelper: SystemHelperRuntimeState` to `RuntimeStateInputs` and `RuntimeState`. Remove `helper` from `RuntimeSetupInputs`. Pass `systemHelper.setupRequirement` into `SetupState.resolve` so one typed value owns helper lifecycle truth.

- [ ] **Step 3: Implement classification as a pure decision**

Use a closed observation type:

```swift
enum SystemHelperIdentityObservation: Equatable, Sendable {
  case identity(SystemHelperIdentity)
  case legacyReachable
  case unreachable(reason: String)
}

struct SystemHelperClassifier {
  static func classify(
    serviceStatus: ManagedServiceStatus,
    observation: SystemHelperIdentityObservation,
    bundled: SystemHelperIdentity
  ) -> SystemHelperRuntimeState
}
```

The classifier must compare the full executable hashes. It must ignore version text when hashes match. It must never infer legacy reachability from an identity error alone.

- [ ] **Step 4: Prove and commit the state contract**

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperClassifierTests'
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SetupStateTests'
make test
```

Commit:

```bash
git add Sources/Common Sources/Models Tests/ModelTests
git commit -S -m "$(printf '%s\n\n%s' \
  'Model System Helper lifecycle state' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 4: Implement safe, serialized helper reconciliation

**Files:**

- Modify: `Sources/Agent/FanHardware.swift`
- Modify: `Sources/Agent/XPCClient.swift`
- Modify: `Sources/Agent/HelperServiceManagementAdapter.swift`
- Modify: `Sources/Common/ManagedService.swift`
- Delete: `Sources/Models/HelperServiceRegistration.swift`
- Modify: `Sources/Models/ServiceManagementAdapters.swift`
- Delete: `Tests/ModelTests/ManagedServiceTests.swift`
- Create: `Sources/Models/SystemHelperFanResetSequencer.swift`
- Create: `Sources/Agent/SystemHelperArtifactValidator.swift`
- Create: `Sources/Agent/SystemHelperLifecycleReconciler.swift`
- Test: `Tests/AgentTests/SystemHelperLifecycleReconcilerTests.swift`
- Test: `Tests/ModelTests/SystemHelperFanResetSequencerTests.swift`
- Modify: `Tuist/ProjectDescriptionHelpers/ModelTestSources.swift`

- [ ] **Step 1: Write failing public workflow tests**

Drive the reconciler through `reconcile(trigger:)`. Use a stateful helper service boundary and a real temporary bundled executable. Assert final state and safety outcomes, not internal call counters.

Cover:

1. Matching active hash returns `running` without service mutation.
2. Legacy reachable helper replaces automatically.
3. Outdated identity replaces automatically.
4. Missing registration remains `registrationNeedsRepair` on startup.
5. Approval remains `approvalRequired` without mutation.
6. Invalid bundled signature preserves old registration.
7. Fan reset failure preserves old registration.
8. Unregister failure leaves old registration and fans automatic.
9. Register failure leaves control paused and reports `register` stage.
10. Registration that requires macOS approval publishes `approvalRequired` without reconnect timeout.
11. Reconnect timeout reports `reconnect` stage.
12. Hash mismatch after reconnect reports `identityVerification` stage.
13. Concurrent startup and manual triggers produce one serialized mutation.

Run:

```bash
make test-agent SWIFT_MK_XCODEBUILD_ARGS='-only-testing:FanCurveAgentTests/SystemHelperLifecycleReconcilerTests'
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperFanResetSequencerTests'
```

Expected: FAIL because no reconciler exists.

- [ ] **Step 2: Strengthen the hardware and service boundaries**

Add these operations to `FanHardware`:

```swift
func getHelperIdentity() async throws -> SystemHelperIdentity
func probeLegacyHelperReachability() async throws
func resetAllDiscoveredFansToAuto() async throws
```

Keep `shutdown()` as the explicit helper connection disconnect. Implement identity by converting upstream `SMCFanHelperIdentity` once in `XPCClient`.

Implement legacy reachability with the existing bounded fan count request. Use it after any identity failure because the local typed XPC proxy cannot identify a missing remote selector reliably. Do not use sensor or fan writes for the probe.

Implement strict reset by discovering the current fan count and awaiting `setFanAuto` for each index. Throw the first failure after logging its fan index and recovery decision.

Change helper service mutation to async outcomes:

```swift
protocol HelperServiceManaging: Sendable {
  var status: ManagedServiceStatus { get }
  func register() async throws
  func unregister() async throws
  func openSystemSettings() throws
}
```

Wrap `SMAppService.unregister(completionHandler:)` with a checked continuation. After completion, poll status with a bounded clock until it is no longer enabled. Register only after confirmed unregistration.

Delete `HelperServiceRegistration`, `ManagedService.installOrRepair`, `ManagedServiceMutationResult`, and their call order tests. The reconciler tests now own real lifecycle outcomes. Keep `ManagedServiceStatus` and both service protocols in `ManagedService.swift`.

- [ ] **Step 3: Add bounded fan reset and artifact preflight**

Use these outcomes:

```swift
enum SystemHelperFanResetOutcome: Equatable, Sendable {
  case completed
  case failed(reason: String)
  case timedOut
}
```

Set the reset deadline to the existing Agent shutdown reset deadline. Preserve failure separately from timeout.

`SystemHelperArtifactValidator` must:

- Require the bundled helper file to exist.
- Compute its full SHA-256 hash.
- Read its embedded Info plist from `kSecCodeInfoPList` in `SecCodeCopySigningInformation`.
- Validate its code signature with `SecStaticCodeCheckValidity`.
- Require the generated helper bundle identifier and development team.
- Require embedded version and build to match generated marketing version and build number.
- Return a complete `SystemHelperIdentity` only after all checks pass.

Use `SecRequirementCreateWithString` with this requirement shape:

```text
anchor apple generic and identifier "io.goodkind.smcfanhelper" and certificate leaf[subject.OU] = "H3BMXM4W7H"
```

Build the identifier and team from generated configuration. Do not hardcode them in production code.

- [ ] **Step 4: Implement the actor reconciler**

Use these triggers and timings:

```swift
enum SystemHelperReconcileTrigger: Sendable {
  case startup
  case reconnect
  case forcedRepair
}

private enum SystemHelperReconcileTiming {
  static let verificationTimeout: Duration = .seconds(10)
  static let verificationPollInterval: Duration = .milliseconds(250)
}
```

Implement one `actor SystemHelperLifecycleReconciler`. Keep an `inFlightTask` so actor reentrancy cannot overlap mutations after an `await`. Publish state through one `@Sendable` callback after every state transition.

The workflow order must be:

1. Publish `checking`.
2. Read service status.
3. Return `registrationNeedsRepair`, `approvalRequired`, or status-specific `unavailable` without identity or artifact checks during automatic reconciliation.
4. Continue forced repair for `notRegistered` only.
5. Validate the bundled helper before identity or mutation.
6. Request identity for an enabled service.
7. If identity fails, run the bounded legacy reachability probe.
8. Classify the observation.
9. Publish `running` and resume controller scheduling when the active identity is current.
10. Publish `outdated`, then `updating`, for reachable automatic replacement.
11. Publish `updating` directly for forced repair.
12. Stop controller ticks through the injected lifecycle gate.
13. Run the bounded strict fan reset.
14. Abort before unregister on reset failure.
15. Call `fanHardware.shutdown()` to invalidate helper XPC.
16. Await unregister when status is enabled.
17. Validate the bundled helper again and require its complete identity to match preflight.
18. Await register only after revalidation succeeds.
19. Read service status and publish `approvalRequired` when macOS approval is required.
20. Retry identity until timeout only after registration is enabled.
21. Require active full hash to equal bundled full hash.
22. Publish `running` and resume ticks.
23. Publish `repairFailed` with operation, stage, reason, and recovery on failure.
24. Resume ticks only when the final state permits fan control.

Log the operation and stage. Do not log the full executable hash. A 12 character presentation hash is sufficient for diagnostics.

- [ ] **Step 5: Prove failure preservation and serialization**

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperFanResetSequencerTests'
make test-agent SWIFT_MK_XCODEBUILD_ARGS='-only-testing:FanCurveAgentTests/SystemHelperLifecycleReconcilerTests'
make log-audit
```

Expected: PASS with no mutation after failed preflight or fan reset.

- [ ] **Step 6: Commit the reconciler**

```bash
git add Sources Tests/AgentTests Tests/ModelTests
git commit -S -m "$(printf '%s\n\n%s' \
  'Add System Helper lifecycle reconciliation' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 5: Gate Agent startup and manual repair on reconciliation

**Files:**

- Modify: `Sources/Agent/AgentController.swift`
- Modify: `Sources/Agent/FanCurveAgentXPCService.swift`
- Modify: `Sources/Agent/main.swift`
- Modify: `Sources/Common/FanCurveAgentXPCProtocol.swift`
- Modify: `Sources/Models/InstallationState.swift`
- Modify: `Sources/Models/InstallationState+AgentLifecycle.swift`
- Modify: `Sources/Services/FanCurveAgentClient.swift`
- Test: `Tests/AgentTests/AgentUpgradeRefreshTests.swift`
- Test: `Tests/AgentTests/TestControlXPCIntegrationTests.swift`
- Test: `Tests/AgentTests/TestControlXPCIntegrationTests+Commands.swift`

- [ ] **Step 1: Write failing Agent XPC acceptance tests**

Use the real in-process app to Agent `NSXPCConnection` harness.

Add tests that prove:

- Startup publishes `checking`, then `updating`, then `running` before the first fan control tick.
- A connected outdated Agent refreshes its registration once and waits for a new hash before retrying.
- Manual reinstall does not reply while the helper remains old.
- Manual reinstall replies accepted only after the active hash matches.
- Registration failure replies rejected with the exact durable failure.
- A failure after unregister publishes control paused state.
- A helper reconnect triggers reconciliation without a second mutation when the hash is current.

Run:

```bash
make test-agent SWIFT_MK_XCODEBUILD_ARGS='-only-testing:FanCurveAgentTests/TestControlXPCIntegrationTests'
```

Expected: FAIL because the Agent command still returns after registration.

- [ ] **Step 2: Make controller lifecycle control explicit**

Add a narrow controller API:

```swift
func pauseForSystemHelperMutation() {
  stopTickTimer()
}

func resumeAfterSystemHelperVerification() {
  startTickTimerIfNeeded()
  requestTick()
}
```

Keep timer ownership inside `AgentController`. Do not expose timer objects to the reconciler.

Make `start()` and `stopTickTimer()` idempotent. `resumeAfterSystemHelperVerification()` must start the heartbeat, observer, timer, and immediate tick exactly once.

Track helper availability transitions in `AgentController`. Notify the reconciler after a reachable snapshot becomes unreachable and after reachability returns. Coalesce these reconnect triggers through the reconciler's `inFlightTask`.

Make `currentRuntimeStateForXPC()` use the latest published `SystemHelperRuntimeState`. Continue pushing every change through `runtimeStateDidChange`.

- [ ] **Step 3: Gate startup**

Start the app facing listener first so the App can observe progress. Then reconcile. The reconciler owns the only resume decision:

```swift
appXPCService.start()
Task {
  await systemHelperReconciler.reconcile(trigger: .startup)
}
RunLoop.main.run()
```

Composition must inject the same `fanHardware`, `helperService`, and reconciler into the Agent service. Debug and Release must differ only at the established test control boundaries.

- [ ] **Step 4: Route manual repair through the same workflow**

Replace direct `HelperServiceRegistration.installOrRepair` with:

```swift
let finalState = await systemHelperReconciler.reconcile(trigger: .forcedRepair)
switch finalState {
case .running:
  return AgentCommandResponse(accepted: true, message: nil)
case .repairFailed(_, _, let failure):
  return AgentCommandResponse(accepted: false, message: failure.reason)
default:
  return AgentCommandResponse(
    accepted: false,
    message: "System Helper repair did not reach a verified running state."
  )
}
```

Do not clear the Agent failure during a generic refresh. Clear it only when a later reconcile begins or reaches verified `running`.

- [ ] **Step 5: Prove and commit Agent integration**

Run:

```bash
make test-agent SWIFT_MK_XCODEBUILD_ARGS='-only-testing:FanCurveAgentTests/TestControlXPCIntegrationTests'
make test
make log-audit
make launch-agent-audit
make run-audit
```

Commit:

```bash
git add Sources Tests/AgentTests
git commit -S -m "$(printf '%s\n\n%s' \
  'Gate Agent control on System Helper verification' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 6: Show distinct helper state and active version

**Files:**

- Modify: `Sources/Models/InstallationState.swift`
- Create: `Sources/Models/SystemHelperPresentation.swift`
- Modify: `Sources/Views/GeneralSettingsView.swift`
- Modify: `Sources/Views/SensorDashboardSidebar+Setup.swift`
- Modify: `Sources/Views/OnboardingView.swift`
- Modify: `Sources/Views/AboutContentView.swift`
- Modify: `Sources/Views/BuildHashes.swift`
- Modify: `Sources/App/FanCurveApp.swift`
- Modify: `Sources/Common/AppAccessibilityIdentifier.swift`
- Test: `Tests/ModelTests/SystemHelperPresentationTests.swift`
- Modify: `Tuist/ProjectDescriptionHelpers/ModelTestSources.swift`
- Test: `Tests/FanCurveUITests/FanCurveUISetupTests.swift`
- Test: `Tests/FanCurveUITests/FanCurveUIControlTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Assert this exact primary copy:

| Runtime state | Status |
| --- | --- |
| checking | `Checking` |
| running | `Running` |
| updating | `Updating` |
| outdated | `Outdated` |
| registration needs repair | `Registration Needs Repair` |
| approval required | `Approval Required` |
| repair failed | `Repair Failed` |
| unavailable | `Unavailable` |

Assert these behavior rules:

- Outdated detail includes active and bundled versions.
- Registration repair detail does not repeat reachability.
- Repair failure detail includes stage reason and recovery.
- Only approval opens System Settings.
- Manual repair title is `Reinstall System Helper` when an active identity exists.
- Busy title is `Reinstalling System Helper` and remains busy through verification.
- About shows `version (build buildNumber)` for active identity.
- About shows `Unavailable` without active identity.

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperPresentationTests'
```

Expected: FAIL because presentation derives from generic registration and reachability flags.

- [ ] **Step 2: Make presentation a pure mapping**

Create:

```swift
struct SystemHelperPresentation: Equatable {
  let tone: Tone
  let status: String
  let detail: String?
  let actionTitle: String?
  let action: Action?
  let isBusy: Bool

  enum Action: Equatable {
    case openSystemSettings
    case repair
  }

  enum Tone: Equatable {
    case healthy
    case degraded
    case inactive
  }

  static func resolve(
    state: SystemHelperRuntimeState,
    repairInFlight: Bool
  ) -> SystemHelperPresentation
}
```

Map `SystemHelperPresentation.Tone` to `ServiceRowState` in `GeneralSettingsView`. Keep SwiftUI types out of `SystemHelperPresentation`.

`InstallationState` must store the Agent supplied `systemHelperState`. Remove `helperNeedsRepair` and the reconstruction from `helperStatus` plus `helperReachable`.

Preserve `lastError` on refresh. A new repair attempt may replace it. Verified `running` clears it.

- [ ] **Step 3: Update General Settings and About**

Render `SystemHelperPresentation` in `GeneralSettingsView`. Remove `Reachable, registration needs repair` and `helperRepairDescription`.

Render `presentation.detail` with `SettingsDescription` inside the helper section whenever it exists. `Repair Failed` must therefore show its stage, reason, and recovery without opening another view.

Use the same presentation action and busy title in onboarding and the dashboard setup sidebar. Do not retain a second helper label mapping.

Add stable accessibility identifiers for:

- System Helper status.
- System Helper detail.
- System Helper action.
- About System Helper version.
- About System Helper full hash.

Inject `agentClient` into the standalone About window:

```swift
AboutContentView()
  .environmentObject(agentClient)
  .environmentObject(appUpdater)
```

About must use active identity from runtime state:

```swift
private var systemHelperVersion: String {
  guard let identity = agentClient.runtimeState?.systemHelper.activeIdentity else {
    return "Unavailable"
  }
  return "\(identity.version) (build \(identity.build))"
}
```

Add a separate `System Helper Hash` Build Details row. Show the full Agent reported executable hash when identity exists and `Unavailable` otherwise. Make its text selectable and give it a stable accessibility identifier. Keep the existing short app and Agent diagnostics unchanged.

- [ ] **Step 4: Add real UI coverage**

Extend the Debug control state with active and bundled helper identities. Drive the signed canonical Debug app through XCUITest.

Prove:

1. Outdated and registration repair have different visible copy.
2. The spinner remains during delayed identity verification.
3. A failed register shows `Repair Failed` and exact recovery after the spinner stops.
4. A later refresh does not erase that error.
5. A later successful reinstall clears the error and shows `Running`.
6. About shows the active version and build.
7. About shows the full active helper hash.
8. About shows `Unavailable` without identity.

Run:

```bash
make test-ui
```

Expected: PASS only after the UI consumes typed state.

- [ ] **Step 5: Prove and commit visible behavior**

Run:

```bash
make test
make log-audit
```

Commit:

```bash
git add Sources Tests
git commit -S -m "$(printf '%s\n\n%s' \
  'Show System Helper lifecycle and version' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 7: Complete deterministic lifecycle acceptance coverage

**Files:**

- Modify: `Sources/TestControl/TestControlState.swift`
- Modify: `Sources/TestControl/ControlledHelperServiceAdapter.swift`
- Modify: `Sources/TestControl/ControlledFanHardware.swift`
- Modify: `Sources/TestControl/AgentTestControlAdapters.swift`
- Modify: `Tests/AgentTests/TestControlXPCIntegrationTests.swift`
- Modify: `Tests/AgentTests/TestControlXPCIntegrationTests+Commands.swift`
- Modify: `Tests/FanCurveUITests/FanCurveUISetupTests.swift`
- Modify: `Tests/FanCurveUITests/FanCurveUIControlTests.swift`
- Modify: `Project.swift` when new test files require target membership

- [ ] **Step 1: Model identity and lifecycle delay in test control**

Add these deterministic fields:

```swift
struct TestSystemHelperIdentity: Codable, Equatable, Sendable {
  let version: String
  let build: String
  let commit: String
  let executableHash: String
  let protocolVersion: UInt
}

enum TestHelperIdentityResult: Codable, Equatable, Sendable {
  case identity(TestSystemHelperIdentity)
  case legacyReachable
  case unavailable(message: String)
}

struct TestHelperLifecycleState: Codable, Equatable, Sendable {
  let active: TestHelperIdentityResult
  let bundled: TestSystemHelperIdentity
  let verificationBlocked: Bool
}
```

Add lifecycle evidence events for classification, reset result, and verified identity. Do not assert internal function names.

- [ ] **Step 2: Make controlled adapters stateful**

After successful register, keep the old active identity until the test applies a new revision. This lets the XPC test prove the command remains pending.

After a failure directive, preserve the registered state that corresponds to the failed stage. Record user observable state before replying.

- [ ] **Step 3: Run the entire deterministic acceptance suite**

Run:

```bash
make test SWIFT_MK_XCODEBUILD_ARGS='-only-testing:ModelTests/SystemHelperClassifierTests -only-testing:ModelTests/SystemHelperPresentationTests -only-testing:ModelTests/SystemHelperFanResetSequencerTests'
make test-agent SWIFT_MK_XCODEBUILD_ARGS='-only-testing:FanCurveAgentTests/SystemHelperLifecycleReconcilerTests -only-testing:FanCurveAgentTests/TestControlXPCIntegrationTests'
make test-ui
make test
```

Expected: PASS. Each test must fail if automatic update, durable error, busy state, or About identity is removed.

- [ ] **Step 4: Commit the acceptance surface**

```bash
git add Sources/TestControl Tests Project.swift
git commit -S -m "$(printf '%s\n\n%s' \
  'Add System Helper lifecycle acceptance coverage' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 8: Document manual signed Tart Sparkle upgrade validation

**Files:**

- Modify: `Docs/validation.md`

- [ ] **Step 1: Add the manual validation boundary**

Add a section named `Validate a Sparkle helper upgrade in Tart`.

State these constraints first:

- A developer performs every step by hand.
- The repository provides no Tart runner, guest script, test target, or artifact manifest.
- The host runs every Make, build, package, signing, and appcast command.
- The guest receives completed artifacts only.
- The guest has no Xcode or repository source.
- Generated artifacts and evidence stay outside version control.

- [ ] **Step 2: Document manual host preparation**

Document this ordered procedure:

1. Set `TART_HOME` to the external-volume directory specified by `Docs/validation.md`.
2. Clone `macos-tahoe-base` to a disposable virtual machine by hand.
3. Start the guest and read its address and default gateway by hand.
4. Create separate host worktrees for `26.8.4-r1` and the candidate commit.
5. Verify `26.8.4-r1` resolves to `525b5d1885a7b836e384a179845dec361df4681b`.
6. Delete stale `build/` and `Products/` directories in both host worktrees.
7. Generate temporary feed certificates on the host for the discovered host address.
8. Build the old signed app on the host with version `26.8.4`, build `202608040448000001`, and the temporary feed URL.
9. Run `make release-assets` in the candidate host worktree with version `26.8.5` and build `202608040448000002`.
10. Run the existing Sparkle preparation target on the host with `SPARKLE_PRIVATE_KEY_FILE` supplied by the release environment.
11. Verify both app signatures, helper signatures, versions, builds, hashes, appcast enclosure, and EdDSA signature.
12. Start the temporary signed feed server on the host.

Do not add a Make target for this procedure. Document the existing Make commands directly.

- [ ] **Step 3: Document the manual guest sequence**

Document these hand-run actions:

1. Install the temporary root certificate in the disposable guest.
2. Archive the old app with `ditto` on the host.
3. Compare the host and guest SHA-256 archive hashes.
4. Extract the old app to `/Applications/Fan Curve.app`.
5. Verify the installed signature before launch.
6. Launch only `/Applications/Fan Curve.app`.
7. Approve the Background Agent and System Helper in System Settings.
8. Wait until General Settings shows `Running`.
9. Record the old app, Agent, and helper versions, hashes, signatures, process identifiers, and launchd state.
10. Start the update through Fan Curve's Sparkle interface.
11. Let Sparkle install and relaunch Fan Curve without clicking `Reinstall System Helper`.
12. Verify About shows the candidate helper version.
13. Verify General Settings shows `Running`.
14. Verify the running Agent belongs to `/Applications/Fan Curve.app`.
15. Verify the active helper hash matches the candidate bundled helper.
16. Click `Reinstall System Helper` once on the healthy candidate install.
17. Verify the busy state ends at `Running` and the active hash still matches.

- [ ] **Step 4: Document evidence and cleanup**

Require the developer to preserve command output, unified logs, launchd state, signatures, and screenshots in a local evidence directory.

Require the developer to record each check as passed or failed. Do not define a repository artifact schema.

Require the developer to stop and delete only the disposable virtual machine. Remove temporary certificates, private keys, feed files, and host worktrees after preserving evidence.

- [ ] **Step 5: Verify and commit the manual procedure**

Read `Docs/validation.md` from start to finish. Confirm every command runs on the stated machine and every linked section exists.

Run:

```bash
git diff --check
```

Commit:

```bash
git add Docs/validation.md
git commit -S -m "$(printf '%s\n\n%s' \
  'Document manual Tart Sparkle helper validation' \
  'Co-authored-by: Codex <noreply@openai.com>')"
```

---

### Task 9: Run complete verification and adversarial review

**Files:**

- Modify only files required by verified review findings.
- Do not commit generated Tart evidence or build products.

- [ ] **Step 1: Refresh the branch comparison**

Run:

```bash
git fetch --prune origin
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Confirm every changed file belongs to the approved design.

- [ ] **Step 2: Run local repository gates**

Run in order:

```bash
make test
make build
make log-audit
make launch-agent-audit
make run-audit
make verify
make run
```

For `make run`, verify exit status, fresh `/Applications/Fan Curve.app` modification time, running app path, running Agent path, and current helper identity. Do not use timestamps alone as correctness proof.

- [ ] **Step 3: Run strongest model adversarial review**

Apply the `adversarial-review` skill to:

- Objective C XPC compatibility with legacy helpers.
- Actor isolation and duplicate trigger serialization.
- Fan reset timeout and failure handling.
- Service Management unregister completion.
- Signature validation and time of check to time of use boundaries.
- Failure persistence through App refresh.
- Sparkle relaunch and Agent replacement ordering.
- Manual Tart cleanup and evidence validation.

Reproduce every finding before changing code. Add a failing public behavior test for every accepted defect.

- [ ] **Step 4: Re-run affected and complete gates**

After review fixes, rerun the narrow failing test, then:

```bash
make test
make log-audit
make launch-agent-audit
make run-audit
make verify
make run
```

- [ ] **Step 5: Run the signed old to new Tart acceptance**

Use signed Fan Curve release `26.8.4-r1` as `OLD_TAG`. Verify it resolves to commit `525b5d1885a7b836e384a179845dec361df4681b` before running.

Follow `Validate a Sparkle helper upgrade in Tart` in `Docs/validation.md` by hand.

Run every Make, build, package, signing, and appcast command on the host. Copy only completed artifacts into the guest. Do not add or invoke a repository Tart runner.

Pass criteria:

- Old helper identity differs from the candidate helper identity.
- Sparkle installs and relaunches the candidate app.
- The new Agent replaces the old Agent.
- The helper updates without clicking manual repair.
- Active helper hash equals the candidate bundled helper hash.
- About shows the candidate active helper version.
- General Settings shows `Running`.
- Healthy manual reinstall ends at verified `Running`.
- The local evidence directory contains signatures, launchd output, unified logs, command results, and screenshots.
- The guest evidence contains no build, package, dependency, appcast, or Make execution.

- [ ] **Step 6: Verify commit signatures**

Run:

```bash
git fetch --prune origin
for commit in $(git rev-list --reverse origin/main..HEAD); do
  git verify-commit "$commit"
  git show -s --format='%H %G?' "$commit"
  git cat-file commit "$commit" | grep '^gpgsig '
done
```

Every commit must verify and contain a raw `gpgsig` header.

- [ ] **Step 7: Record final evidence without claiming more than proved**

Report each command as passed, failed, or skipped. Separate local tests, installed host validation, signed release validation, and manual Tart acceptance. Do not call the automatic path verified if manual Tart acceptance did not pass.
