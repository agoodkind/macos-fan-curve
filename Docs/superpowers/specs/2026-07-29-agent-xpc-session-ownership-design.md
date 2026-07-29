# Agent XPC session owns its in-flight requests

## Problem

`FanCurveAgentClient` can abandon an in-flight XPC request forever. When that
happens the awaiting caller never resumes, the app never reconnects, and the
process later aborts.

Measured on `main` at `916c5d7`, running
`FanCurveAgentTests/TestControlXPCIntegrationTests/testInterruptionFaultIsOneShotAcrossAgentTermination`
alone: **9 failures of 15**. The same test in full-suite order passes 12 of 12,
which is why the defect stayed hidden.

Every failure is the same abort:

```
freed pointer was not the last allocation
```

That message comes from Swift's task-local allocator, not from malloc. The crash
report shows `swift_task_dealloc_specific` aborting on the main thread inside
`XCTSwiftErrorObservation._observeErrors(in:)`.

### Cause

`XCTSwiftErrorObservation` stores a task-local value, allocated on the task's
stack-discipline allocator. The abort means that when its scope exited, an
allocation made later was still outstanding. That later allocation is the
`withCheckedThrowingContinuation` inside `performRequest`.

The chain:

1. `refreshCurrentState()` calls `performRequest(.currentState)`, which creates a
   continuation and sends `getCurrentState` over XPC.
2. The agent injects an interruption fault. It returns without calling the reply
   block and invalidates its connections.
3. Nothing on the client resumes that continuation. In passing runs the remote
   proxy's error handler happens to fire and resume it. In failing runs it does
   not.
4. `performRequest` stays suspended forever, holding a task allocation.
5. The test's wait expires and throws.
6. XCTest unwinds the test task while that allocation is outstanding, and the
   task allocator aborts.

The hang and the crash are one defect, not two.

### Why nothing resumed it

Five separate paths can resolve a request, across 14 call sites in three files:
the XPC reply block, the remote proxy error handler, `handleDisconnect`,
`handleRemoteProxyFailure`, and task cancellation. Each is optional and each
carries its own guard. Correctness depends on at least one of them choosing to
fire.

`handleDisconnect` is the only path guaranteed to run when a connection dies, and
its guard returns before the cleanup:

```swift
guard connectionGeneration == disconnectedGeneration, connection != nil else {
  return
}
cancelPendingRequests(reason: reason, error: .connectionUnavailable)
```

Deduplicating the state transition is correct, because a sibling path may have
already handled the drop. Deduplicating the continuation cleanup abandons the
requests.

`AgentXPCReplyResumer` is not at fault. Its lock and `isCompleted` flag prevent a
double resume correctly. The failure mode is zero resumes.

## Design

`AgentXPCSession`, main-actor isolated, owns exactly one `NSXPCConnection` and
every request in flight on it. The client holds at most one session, replacing
the current `connection` field, `connectionGeneration` counter, and
`ObjectIdentifier` comparison.

A request cannot outlive its connection, because the connection owns it.

### Single teardown path

```swift
func end(_ reason: AgentXPCSessionEndReason)
```

`end` is idempotent. It marks the session ended, removes and resumes every
outstanding request with the terminal error for that reason, then invalidates the
connection. It is the only teardown path, and every disconnect signal routes to
it, so no continuation can be abandoned.

Two ordering rules:

- Resume requests **before** invalidating the connection, so a resumed caller
  never observes a half-torn-down session.
- Remove each resumer from the registry **before** resuming it, so a resume that
  re-enters cannot see a stale entry.

### Replacing the generation counter

Each connection handler captures its own session reference. A stale handler calls
`end` on a session that has already ended, which is a no-op. Staleness is handled
by identity rather than by comparing counters.

The three separately guarded `cancelPendingRequests` callers collapse into one
call to `end` each.

### End reasons

`AgentXPCSessionEndReason` is a strong enum, replacing today's `reason: String`.

| Reason | Terminal error | Reconnect |
| --- | --- | --- |
| `interrupted` | `connectionUnavailable` | yes |
| `invalidated` | `connectionUnavailable` | yes |
| `proxyFailure(Error)` | the underlying XPC error | yes |
| `clientStopped` | `CancellationError` | no |

`clientStopped` is the only reason that suppresses reconnect, preserving today's
`stop()` behavior.

### Requests on a dead session

`performRequest` registers with the session it is issued on. If that session has
already ended, it fails immediately rather than creating a continuation with no
owner.

### Reconnect policy

Stays in the client. The session is a lifetime and ownership unit and does not
know the app wants to reconnect.

The session takes a completion closure at construction, which it calls once from
`end`, after draining, with the reason. The client supplies that closure. On
being called it clears its session reference, publishes the new connection state,
and schedules a reconnect unless the reason is `clientStopped`.

The closure fires exactly once per session, because `end` is idempotent. That
replaces today's arrangement, where three handlers each decide independently
whether to schedule a reconnect and each can suppress itself.

### Late replies

`AgentXPCReplyResumer` keeps its lock and `isCompleted` flag. An XPC reply that
arrives after `end` is a no-op.

## Logging

Session creation and `end` are state-transition boundaries. Both log through the
project's logging abstraction with the reason and the number of requests drained.

A drained count above zero on a healthy disconnect is the signal that would have
made this defect visible from logs alone.

## Testing

### Regression test

`testInterruptionFaultIsOneShotAcrossAgentTermination`, run alone, against the
recorded baseline of 9 failures of 15 on `main` at `916c5d7`. The fix must show 0
of 15 in the same isolated configuration.

One passing run is not evidence for a fix to an intermittent defect.

Also re-run the full suite to confirm the 0-of-12 full-suite result holds, so the
fix does not trade an isolated failure for an in-suite one.

### Unit tests

On the session directly, with no XPC and no mocks. Each enters through the public
boundary and asserts an observable outcome.

- A session with a registered request, then `end(.invalidated)`: the awaiting
  caller receives `connectionUnavailable` rather than hanging. This is the
  invariant the design exists to guarantee.
- `end` called twice: the second is a no-op and does not resume anything again.
- A request issued on an already-ended session fails immediately rather than
  suspending.

## Scope

Not in scope: GPU temperature as a curve input, and the tick deadline with
abandon-and-restart. Both stay deferred.

This change touches `Sources/Services/FanCurveAgentClient.swift` and its
extensions. Open PRs #44, #45, and #46 touch none of those files, so it does not
conflict with the stack.

## Product impact

`FanCurveAgentClient` is the app's client, not test-only code. A client that can
abandon a request and never reconnect produces exactly the "Runtime telemetry is
unavailable" symptom that opened this workstream. The plan attributes that
symptom entirely to slow ticks. This is a second, independent cause of it.
