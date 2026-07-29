# Agent XPC Session Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an in-flight XPC request impossible to abandon, by giving one connection-scoped session ownership of every request on it and a single idempotent teardown that always resumes them.

**Architecture:** `AgentXPCSession` owns one `NSXPCConnection` plus every request in flight on it. `end(_:)` is the only teardown path: it resumes every outstanding request, invalidates the connection, then notifies its owner exactly once. `FanCurveAgentClient` holds at most one session, replacing its `connection` field, `connectionGeneration` counter, and `ObjectIdentifier` comparison.

**Tech Stack:** Swift 6 strict concurrency, `@MainActor` isolation, `NSXPCConnection`, XCTest with Nimble, Tuist project generation.

## Global Constraints

- Design spec: `Docs/superpowers/specs/2026-07-29-agent-xpc-session-ownership-design.md`. Read it before starting.
- Worktree: `~/.worktrees/-Users-agoodkind-Sites-macos-fan-curve/fan-xpc-session-ownership`, branch `fix/xpc-session-ownership`, based on `main` at `916c5d7`.
- Use the repository Makefile as the automation entry point. Do not run partial `tuist`, `xcodebuild`, or Swift compiler commands when a Make target exists. Exception: the repeat-run verification in Task 2 needs `xcodebuild test-without-building` directly, and the exact command is given.
- Do NOT run `make run`. It deploys to `/Applications` and restarts live fan control on the user's machine.
- Log through the project's `AppLog` abstraction only. No `print`, `NSLog`, or direct `os_log`.
- Run `make log-audit` after touching Swift logging or adding Swift files.
- Commit with `git commit -S`. Imperative subject, no trailing period, trailer after a blank line: `Co-authored-by: Claude <noreply@anthropic.com>`
- Do not push. The controller handles pushing and the pull request.
- The docs root is `Docs` with a capital D. The filesystem is case-insensitive, so `git add docs/...` silently no-ops.

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/Services/AgentXPCSession.swift` (create) | `AgentXPCSessionEndReason` and `AgentXPCSession`. Owns one connection and its in-flight requests. |
| `Tests/AgentTests/AgentXPCSessionTests.swift` (create) | Unit tests for the drain invariant, with no XPC. |
| `Sources/Services/FanCurveAgentClient.swift` (modify) | Holds a session instead of a raw connection. Loses the generation counter and the three guarded cleanup callers. |

`FanCurveAgentTests` already globs `Sources/Services/Agent*.swift`, and the app target globs `Sources/Services/**`, so the new file joins both targets with no `Project.swift` change.

---

### Task 1: AgentXPCSession with a guaranteed drain

Self-contained. Nothing uses the session yet, so it is testable on its own.

**Files:**
- Create: `Sources/Services/AgentXPCSession.swift`
- Test: `Tests/AgentTests/AgentXPCSessionTests.swift`

**Interfaces:**
- Consumes: `AgentXPCReplyResumer` and `FanCurveAgentClientError` from `Sources/Services/AgentXPCRequest.swift`, both unchanged.
- Produces, relied on by Task 2:
  - `enum AgentXPCSessionEndReason: Sendable` with cases `clientStopped`, `interrupted`, `invalidated`, `proxyFailure(any Error)`
  - `AgentXPCSession.init(connection: NSXPCConnection, onEnd: @escaping @MainActor (AgentXPCSessionEndReason) -> Void)`
  - `let id: UUID`
  - `let connection: NSXPCConnection`
  - `var hasEnded: Bool`
  - `var pendingRequestCount: Int`
  - `func register(_ resumer: AgentXPCReplyResumer) -> UUID?`
  - `func release(_ requestID: UUID)`
  - `func end(_ reason: AgentXPCSessionEndReason)`
  - `AgentXPCSessionEndReason.logName: String` and `.allowsReconnect: Bool`, both read by the client

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentTests/AgentXPCSessionTests.swift`:

```swift
//
//  AgentXPCSessionTests.swift
//  FanCurveAgentTests
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-29.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
final class AgentXPCSessionTests: XCTestCase {
  /// An anonymous listener gives a real NSXPCConnection to own without
  /// standing up a service. The session only invalidates it.
  private func makeConnection() -> NSXPCConnection {
    let listener = NSXPCListener.anonymous()
    listener.resume()
    return NSXPCConnection(listenerEndpoint: listener.endpoint)
  }

  /// The invariant the whole design exists to guarantee: a request registered
  /// on a session that then ends is resumed, never abandoned. An abandoned
  /// continuation holds a task allocation and aborts the task allocator when
  /// its task unwinds.
  func testEndResumesRegisteredRequestRatherThanAbandoningIt() async throws {
    let session = AgentXPCSession(connection: makeConnection()) { _ in }
    let resumer = AgentXPCReplyResumer(operation: "current-state")
    let requestID = try XCTUnwrap(session.register(resumer))

    async let reply: Data? = withCheckedThrowingContinuation { continuation in
      resumer.install(continuation)
    }

    session.end(.invalidated)
    session.release(requestID)

    await expecta(try await reply).to(
      throwError(FanCurveAgentClientError.connectionUnavailable)
    )
  }

  func testEndIsIdempotentAndNotifiesItsOwnerOnce() {
    var endCount = 0
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      endCount += 1
    }

    session.end(.interrupted)
    session.end(.invalidated)

    expect(endCount) == 1
    expect(session.hasEnded) == true
  }

  func testRegisterRefusesOnAnEndedSessionSoTheCallerFailsFast() {
    let session = AgentXPCSession(connection: makeConnection()) { _ in }
    session.end(.clientStopped)

    let resumer = AgentXPCReplyResumer(operation: "current-state")

    expect(session.register(resumer)).to(beNil())
    expect(session.pendingRequestCount) == 0
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
make test 2>&1 | tee /tmp/task1-red.log
```

Expected: compilation fails with `cannot find 'AgentXPCSession' in scope`. That is the correct red state for a type that does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/Services/AgentXPCSession.swift`:

```swift
//
//  AgentXPCSession.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

let agentXPCSessionLog = AppLog.make(category: "AgentXPCSession")

// MARK: - AgentXPCSessionEndReason

/// Why a session ended, carrying the terminal error its in-flight requests
/// receive. A caller can tell a dropped connection from a deliberate stop.
enum AgentXPCSessionEndReason: Sendable {
  case clientStopped
  case interrupted
  case invalidated
  case proxyFailure(any Error)

  var terminalError: any Error {
    switch self {
    case .clientStopped:
      return CancellationError()
    case .interrupted, .invalidated:
      return FanCurveAgentClientError.connectionUnavailable
    case .proxyFailure(let error):
      return error
    }
  }

  /// Only a deliberate client stop suppresses reconnection.
  var allowsReconnect: Bool {
    switch self {
    case .clientStopped:
      return false
    case .interrupted, .invalidated, .proxyFailure:
      return true
    }
  }

  /// A stop cancels its requests, so `claimDispatch` can report a request that
  /// was cancelled before it ever dispatched. Every other reason is a failure.
  var cancelsRequests: Bool {
    switch self {
    case .clientStopped:
      return true
    case .interrupted, .invalidated, .proxyFailure:
      return false
    }
  }

  var logName: String {
    switch self {
    case .clientStopped:
      return "client-stopped"
    case .interrupted:
      return "interrupted"
    case .invalidated:
      return "invalidated"
    case .proxyFailure:
      return "proxy-failure"
    }
  }
}

// MARK: - AgentXPCSession

/// Owns one `NSXPCConnection` and every request in flight on it.
///
/// A request cannot outlive its connection. `end` is the single teardown path
/// and always resumes outstanding requests, so no continuation is abandoned.
/// An unresumed continuation holds a task allocation for the lifetime of its
/// task, which aborts the task allocator when that task unwinds.
@MainActor
final class AgentXPCSession {
  /// Identity for XPC handlers, which are `@Sendable` and cannot capture the
  /// session itself. A handler carries this value and the client compares it
  /// against its current session.
  let id = UUID()
  let connection: NSXPCConnection

  private var pendingRequests: [UUID: AgentXPCReplyResumer] = [:]
  private var endReason: AgentXPCSessionEndReason?
  private let onEnd: @MainActor (AgentXPCSessionEndReason) -> Void

  var hasEnded: Bool {
    endReason != nil
  }

  var pendingRequestCount: Int {
    pendingRequests.count
  }

  init(
    connection: NSXPCConnection,
    onEnd: @escaping @MainActor (AgentXPCSessionEndReason) -> Void
  ) {
    self.connection = connection
    self.onEnd = onEnd
    agentXPCSessionLog.notice(
      "agent_session.started session=\(self.id.uuidString, privacy: .public)"
    )
  }

  /// Registers a request against this session, or returns nil when the session
  /// has already ended so the caller fails fast rather than creating a
  /// continuation with no owner.
  func register(_ resumer: AgentXPCReplyResumer) -> UUID? {
    guard !hasEnded else {
      agentXPCSessionLog.notice(
        "agent_session.register_refused session=\(self.id.uuidString, privacy: .public) recovery=fail-request"
      )
      return nil
    }
    let requestID = UUID()
    pendingRequests[requestID] = resumer
    return requestID
  }

  func release(_ requestID: UUID) {
    pendingRequests.removeValue(forKey: requestID)
  }

  /// Ends the session exactly once: resumes every outstanding request, then
  /// invalidates the connection, then notifies its owner.
  func end(_ reason: AgentXPCSessionEndReason) {
    guard !hasEnded else {
      agentXPCSessionLog.debug(
        "agent_session.end_ignored session=\(self.id.uuidString, privacy: .public) reason=\(reason.logName, privacy: .public) recovery=already-ended"
      )
      return
    }
    endReason = reason

    // Remove each resumer before resuming it, so a re-entrant resume cannot
    // observe a stale entry. Resume before invalidating, so a resumed caller
    // never observes a half-torn-down session.
    let drained = pendingRequests
    pendingRequests.removeAll()
    for resumer in drained.values {
      if reason.cancelsRequests {
        resumer.cancel()
      } else {
        resumer.resume(throwing: reason.terminalError)
      }
    }

    let recovery: String
    if reason.allowsReconnect {
      recovery = "schedule-reconnect"
    } else {
      recovery = "stay-stopped"
    }
    agentXPCSessionLog.notice(
      "agent_session.ended session=\(self.id.uuidString, privacy: .public) reason=\(reason.logName, privacy: .public) drained=\(drained.count, privacy: .public) recovery=\(recovery, privacy: .public)"
    )

    connection.interruptionHandler = nil
    connection.invalidationHandler = nil
    connection.invalidate()

    onEnd(reason)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
make test 2>&1 | tee /tmp/task1-green.log
```

Expected: all three `AgentXPCSessionTests` pass and no existing test regresses. Confirm by checking that the log contains no `with [1-9]` failure counts.

- [ ] **Step 5: Run the build gates and the log audit**

Run:

```bash
make build 2>&1 | tee /tmp/task1-build.log
make log-audit 2>&1 | tee /tmp/task1-logaudit.log
```

Expected: `BUILD SUCCEEDED`, all five gates `ok` (`lint-complexity`, `lint-deadcode`, `lint-format`, `lint-swiftlint`, `swiftcheck-extra`), and `make log-audit` exits 0.

If `lint-deadcode` reports `AgentXPCSession` members as unused, that is expected at this point because nothing consumes them yet. Do not add a baseline entry and do not delete the members. Note it and proceed; Task 2 wires them up and the warning goes away.

- [ ] **Step 6: Commit**

```bash
git add Sources/Services/AgentXPCSession.swift Tests/AgentTests/AgentXPCSessionTests.swift
git commit -S -m "Add a connection-scoped XPC session that owns its in-flight requests

AgentXPCSession owns one NSXPCConnection and every request in flight on
it. end(_:) is the single teardown path: it resumes every outstanding
request, invalidates the connection, then notifies its owner exactly
once.

An unresumed continuation holds a task allocation for the lifetime of its
task, so abandoning one aborts the task allocator when that task unwinds.

Nothing consumes the session yet.

Co-authored-by: Claude <noreply@anthropic.com>"
```

---

### Task 2: Route the client through the session

Atomic. The client cannot hold both a raw connection and a session without two sources of truth, so the migration and the deletions land together.

**Files:**
- Modify: `Sources/Services/FanCurveAgentClient.swift`

**Interfaces:**
- Consumes: every symbol listed in Task 1's Produces block.
- Produces: no new public surface. `pendingRequestCount` stays on the client, forwarding to the session, because `TestControlXPCIntegrationTests` asserts on it.

- [ ] **Step 1: Record the pre-fix baseline**

The defect is intermittent, so a single passing run proves nothing. Capture the starting rate before changing code.

```bash
cd ~/.worktrees/-Users-agoodkind-Sites-macos-fan-curve/fan-xpc-session-ownership
make build
fails=0
for run in $(seq 1 15); do
  xcodebuild test-without-building \
    -workspace FanCurveApp.xcworkspace -scheme FanCurve -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath build \
    -only-testing:FanCurveAgentTests/TestControlXPCIntegrationTests/testInterruptionFaultIsOneShotAcrossAgentTermination \
    > /tmp/baseline-$run.log 2>&1
  rc=$?; [ "$rc" != "0" ] && fails=$((fails+1))
done
echo "baseline: $fails failures of 15"
```

Expected: roughly 9 failures of 15. The recorded measurement on `main` at `916c5d7` was exactly 9 of 15. Anything in the 5-to-13 range confirms you are reproducing the same defect. Zero failures means something is wrong with the setup; stop and report rather than proceeding, because you would have no signal to verify against.

Each failing run contains `freed pointer was not the last allocation`. Confirm with `grep -l "freed pointer" /tmp/baseline-*.log`.

- [ ] **Step 2: Replace the client's connection state with a session**

In `Sources/Services/FanCurveAgentClient.swift`, replace these three stored properties:

```swift
  private var connection: NSXPCConnection?
  private var pendingRequests: [UUID: AgentXPCReplyResumer] = [:]
  private var connectionGeneration: UInt64 = 0
```

with:

```swift
  private var session: AgentXPCSession?
```

Replace the computed `pendingRequestCount`:

```swift
  var pendingRequestCount: Int {
    pendingRequests.count
  }
```

with:

```swift
  var pendingRequestCount: Int {
    session?.pendingRequestCount ?? 0
  }
```

- [ ] **Step 3: Build the session in connect() and configure handlers against its id**

Replace the body of `connect()` from `let nextConnection = connectionFactory()` through the end of the function with:

```swift
    let nextConnection = connectionFactory()
    let nextSession = AgentXPCSession(connection: nextConnection) {
      [weak self] reason in
      self?.sessionDidEnd(reason)
    }
    configure(nextConnection, sessionID: nextSession.id)
    session = nextSession
    nextConnection.resume()
    fanCurveAgentClientLog.notice(
      "agent_client.connection.started service=\(serviceName, privacy: .public)")
    if control.consumeReconnectFault() {
      fanCurveAgentClientLog.notice(
        "agent_client.connection.fault_injected kind=reconnect recovery=invalidate-connection"
      )
      nextSession.end(.invalidated)
      return
    }
    startConnectionTask(session: nextSession)
```

Replace `configure(_:generation:)` with:

```swift
  private func configure(
    _ nextConnection: NSXPCConnection,
    sessionID: UUID
  ) {
    nextConnection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
    nextConnection.exportedInterface = NSXPCInterface(with: FanCurveAgentXPCEventProtocol.self)
    nextConnection.exportedObject = self
    // These handlers are @Sendable and cannot capture the main-actor session,
    // so they carry its id and the client resolves it after hopping to main.
    nextConnection.interruptionHandler = { @Sendable [weak self] in
      DispatchQueue.main.async {
        self?.endSession(sessionID, reason: .interrupted)
      }
    }
    nextConnection.invalidationHandler = { @Sendable [weak self] in
      DispatchQueue.main.async {
        self?.endSession(sessionID, reason: .invalidated)
      }
    }
  }
```

- [ ] **Step 4: Replace the three guarded teardown paths with one**

Delete `handleDisconnect(_:reason:)`, `handleRemoteProxyFailure(_:connectionID:generation:)`, and `cancelPendingRequests(reason:error:)` in their entirety. Add:

```swift
  /// Ends the named session if it is still the current one. A handler from a
  /// replaced session names a session the client no longer holds, so it is
  /// ignored here rather than by comparing counters.
  private func endSession(
    _ sessionID: UUID,
    reason: AgentXPCSessionEndReason
  ) {
    guard let session, session.id == sessionID else {
      fanCurveAgentClientLog.notice(
        "agent_client.session.stale_end_suppressed reason=\(reason.logName, privacy: .public) recovery=preserve-current-session"
      )
      return
    }
    session.end(reason)
  }

  /// Called once by the session after it drains, so reconnect policy and the
  /// published state stay here rather than in the session.
  ///
  /// This is the only writer of `connectionState` on a teardown. A caller that
  /// knows why the session died reports it through the reason, so a failure
  /// keeps its message instead of being flattened to `.disconnected`.
  private func sessionDidEnd(_ reason: AgentXPCSessionEndReason) {
    session = nil
    control.recordEvent(.disconnected)

    switch reason {
    case .proxyFailure(let error):
      lastError = error.localizedDescription
      connectionState = .failed(error.localizedDescription)
    case .interrupted, .invalidated, .clientStopped:
      connectionState = .disconnected
    }

    guard reason.allowsReconnect else {
      fanCurveAgentClientLog.info("agent_client.connection.stopped")
      return
    }
    fanCurveAgentClientLog.notice(
      "agent_client.connection.disconnected reason=\(reason.logName, privacy: .public) recovery=schedule-reconnect"
    )
    scheduleReconnect()
  }
```

- [ ] **Step 5: Route stop(), performRequest, and remoteProxy through the session**

Replace `stop()` with:

```swift
  func stop() {
    stopped = true
    connectionTask?.cancel()
    connectionTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    guard let session else {
      // No session to drain, so publish the stopped state directly.
      connectionState = .disconnected
      fanCurveAgentClientLog.info("agent_client.connection.stopped")
      return
    }
    // sessionDidEnd publishes the state and suppresses reconnect for this
    // reason, so stop() does not set connectionState itself.
    session.end(.clientStopped)
  }
```

Replace the opening of `performRequest(_:)` down to the `defer`:

```swift
  func performRequest(_ request: AgentXPCRequest) async throws -> Data? {
    guard let session, !session.hasEnded else {
      throw FanCurveAgentClientError.connectionUnavailable
    }
    let resumer = AgentXPCReplyResumer(operation: request.operation)
    guard let requestID = session.register(resumer) else {
      throw FanCurveAgentClientError.connectionUnavailable
    }
    defer {
      session.release(requestID)
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        resumer.install(continuation)
        requestDispatcher.dispatch { [self] in
          guard resumer.claimDispatch() else {
            return
          }
          guard let proxy = remoteProxy(for: session, resumer: resumer) else {
            return
          }
          start(request, using: proxy, resumer: resumer)
        }
      }
    } onCancel: {
      resumer.cancel()
    }
  }
```

Replace `remoteProxy(resumer:)` with:

```swift
  private func remoteProxy(
    for session: AgentXPCSession,
    resumer: AgentXPCReplyResumer
  ) -> FanCurveAgentXPCProtocol? {
    let sessionID = session.id
    let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
      // Resume this request here so its caller is not waiting on the main hop.
      // The session drains any others when it ends.
      resumer.resume(throwing: error)
      DispatchQueue.main.async {
        self?.endSession(sessionID, reason: .proxyFailure(error))
      }
    }
    guard
      let proxy = remoteProxyProvider.remoteProxy(
        for: session.connection,
        errorHandler: errorHandler
      )
    else {
      resumer.resume(throwing: FanCurveAgentClientError.missingRemoteProxy)
      return nil
    }
    return proxy
  }
```

- [ ] **Step 6: Update startConnectionTask to take the session**

Replace `startConnectionTask(nextConnection:generation:)` with:

```swift
  private func startConnectionTask(session: AgentXPCSession) {
    connectionTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      do {
        try await registerForEvents()
        try await refreshCurrentState()
        guard
          !Task.isCancelled,
          !stopped,
          self.session === session
        else {
          return
        }
        connectionTask = nil
        connectionState = .connected
        control.recordEvent(.connected)
        lastError = nil
        fanCurveAgentClientLog.notice("agent_client.connection.ready")
      } catch {
        guard !stopped, self.session === session else {
          return
        }
        connectionTask = nil
        fanCurveAgentClientLog.notice(
          "agent_client.connection.failed error=\(error.localizedDescription, privacy: .public) recovery=schedule-reconnect"
        )
        // The session owns teardown, the published state, and reconnect
        // scheduling. Report the error through the reason so sessionDidEnd
        // publishes .failed with its message rather than a bare .disconnected.
        session.end(.proxyFailure(error))
      }
    }
  }
```

Also update `start()`, which guards on the old field:

```swift
  func start() {
    guard session == nil else { return }
    stopped = false
    connect()
  }
```

And `scheduleReconnect()`, whose guard reads the old field:

```swift
      guard !stopped, session == nil else { return }
```

- [ ] **Step 7: Build and fix compilation**

Run:

```bash
make build 2>&1 | tee /tmp/task2-build.log
```

Expected: `BUILD SUCCEEDED` with all five gates `ok`.

Likely errors and their fixes:
- `cannot find 'connection' in scope`: a remaining reader of the deleted field. Route it through `session?.connection`.
- `cannot find 'connectionGeneration' in scope`: a remaining generation comparison. Replace with `self.session === session` or an id comparison.
- Sendable diagnostics on a closure capturing `session`: capture `session.id` instead, which is a `UUID`.

- [ ] **Step 8: Verify against the recorded baseline**

Run the identical loop from Step 1:

```bash
fails=0
for run in $(seq 1 15); do
  xcodebuild test-without-building \
    -workspace FanCurveApp.xcworkspace -scheme FanCurve -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath build \
    -only-testing:FanCurveAgentTests/TestControlXPCIntegrationTests/testInterruptionFaultIsOneShotAcrossAgentTermination \
    > /tmp/fixed-$run.log 2>&1
  rc=$?; [ "$rc" != "0" ] && fails=$((fails+1))
done
echo "after fix: $fails failures of 15"
grep -l "freed pointer" /tmp/fixed-*.log || echo "no allocator aborts"
```

Expected: 0 failures of 15, and no log containing `freed pointer was not the last allocation`.

If any run still fails, stop and report the count and the failing log path. Do not proceed and do not adjust the test.

- [ ] **Step 9: Verify the full suite did not regress**

The fix must not trade an isolated failure for an in-suite one.

```bash
make test 2>&1 | tee /tmp/task2-test.log
make log-audit 2>&1 | tee /tmp/task2-logaudit.log
```

Expected: `make test` exits 0 with no failing suites, and `make log-audit` exits 0.

- [ ] **Step 10: Commit**

```bash
git add Sources/Services/FanCurveAgentClient.swift
git commit -S -m "Give the XPC session ownership of the client's in-flight requests

The client could abandon an in-flight request. Five optional paths across
14 call sites could resolve one, and handleDisconnect, the only path
guaranteed to run when a connection dies, returned at its dedup guard
before cancelling pending requests. The continuation was never resumed,
so performRequest stayed suspended holding a task allocation, and the
task allocator aborted when the task unwound.

The client now holds an AgentXPCSession instead of a raw connection. Every
disconnect signal routes to session.end(_:), which always drains. That
removes the generation counter, the ObjectIdentifier comparison, and the
three separately guarded cleanup callers.

Measured on the interruption test run alone: 9 failures of 15 before, 0 of
15 after.

Co-authored-by: Claude <noreply@anthropic.com>"
```

---

## Verification Summary

Report each command and whether it passed, failed, or was skipped:

- `make build` with all five gates
- `make test`
- `make log-audit`
- The 15-run isolated loop, before and after, with both counts
- `make run` is deliberately skipped because it restarts live fan control on the user's machine

Do not claim the fix works on a single passing run. The baseline exists so the claim rests on a rate.
