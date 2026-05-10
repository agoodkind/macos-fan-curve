# Agent-Centric Runtime Architecture

Status: Planned only. Not executed yet.

## Context

This plan was written while the repository was in a split state:

- The main worktree was kept clean as the stable reference point.
- Active remediation work lived in a separate rescue worktree.
- The current implementation had already accumulated behavior drift around
  setup state, helper reachability, runtime freshness, and chart rendering.

At the time this plan was written, the key architectural problems were:

- the app talked directly to the privileged helper over XPC
- the app and agent used shared defaults plus Darwin notifications as the live
  runtime control/status bus
- setup state, control state, and telemetry freshness were visually conflated
- the UI could show active-state visuals in setup-required states and preview
  visuals in active states

This document is intended to describe the target architecture before execution,
so an implementer can use it as the source of truth while reconciling the WIP
worktree back into `main`.

## Worktree Layout

At plan-authoring time, the repository layout was:

- Main worktree: `/Users/agoodkind/Sites/macos-fan-curve`
  Branch: `main`
  Base commit: `6a35d8f`
  Role: clean reference checkout and destination for final documentation
- Rescue worktree: `/Users/agoodkind/Sites/macos-fan-curve-wip-rescue-20260509-165114`
  Branch: `wip/rescue-20260509-165114`
  Base commit: `6a35d8f`
  Role: active WIP checkout containing runtime, setup, chart, and build-system
  remediation changes
- Semantic-demand worktree: `/Users/agoodkind/Sites/macos-fan-curve-semantic-demand`
  Branch: `semantic-demand-split`
  Base commit: `94ff893`
  Role: older focused worktree for semantic-demand/chart behavior exploration

## Summary

This document describes the target runtime architecture for Fan Curve. It is
an implementation plan, not a record of shipped behavior.

The target model is:

```text
Fan Curve.app  <->  Agent XPC  <->  Privileged Helper XPC
```

The app becomes UI-only. The background agent becomes the single runtime owner
for telemetry, curve evaluation, control state, and user-facing status. The
privileged helper becomes a narrow root boundary for fan-control writes and
ownership or arbitration semantics.

## Current Problems

- The app currently talks directly to the privileged helper over XPC.
- The app and agent currently use shared defaults plus Darwin notifications as
  the live config and snapshot bus.
- Setup, control, telemetry freshness, and degraded runtime states are
  collapsed into overly simple booleans such as `fanControlReady`.
- UI states bleed into one another, which causes active visuals to show during
  setup-required states and preview visuals to leak into active states.
- The app currently treats helper reachability as a proxy for too many
  product-level states.

## Target Responsibilities

### Fan Curve.app

- Owns only windows, settings, editing UX, and setup affordances.
- Talks only to the background agent over app-facing XPC.
- Does not call helper XPC directly.
- Does not read AppleSMC directly.
- Does not infer runtime state from scattered helper probes, defaults, or
  launch status.

### FanCurveAgent

- Owns telemetry reads.
- Owns curve evaluation, damping, and command selection.
- Owns the setup, off, on, boost, and degraded state machine.
- Exposes app-facing XPC for commands and live state.
- Calls the helper only for privileged write-side operations and
  ownership-sensitive status.
- Translates helper and runtime failures into product-level states before the
  app sees them.

### Privileged Helper

- Owns only root-required operations.
- Applies fan mode and RPM writes.
- Owns write-side ownership or arbitration semantics.
- Exposes a narrow agent-facing XPC API.

## IPC Model

### App <-> Agent

Replace shared-defaults-plus-Darwin as the primary live control and status path
with XPC.

The app sends commands such as:

- `setCurve(points, interpolationMode)`
- `setFanControlEnabled(Bool)`
- `setBoostEnabled(Bool)`
- `setApplyInBackground(Bool)`
- `installAgent()`
- `installHelper()`
- `openApprovalSettings()`

The agent publishes:

- a single `RuntimeState`
- setup state
- control state
- telemetry state
- runtime health

Shared defaults may remain for persistence of user preferences, but not as the
primary runtime bus.

### Agent <-> Helper

Keep XPC. The helper interface should stay narrow and write-oriented:

- `applyFanActions(...)`
- `resetFansToAuto(...)`
- `getOwnershipStatus(...)`
- optional helper health/status reads only if the agent truly needs them

Telemetry reads should stay in the agent by default. The helper should not
proxy ordinary reads unless a concrete hardware limitation requires it.

## State Model

Replace collapsed booleans with explicit state types.

### Setup State

- `checking`
- `agent_required`
- `agent_needs_approval`
- `helper_required`
- `helper_needs_approval`
- `ready`

### Control State

- `off`
- `on`
- `boost`

### Telemetry State

- `unavailable`
- `stale`
- `live`

### Runtime Health

- `ok`
- `agent_not_responding`
- `helper_unreachable`
- `ownership_preempted`
- `snapshot_pending`

The app should render from the full runtime state, not from ad hoc combinations
of helper probes, snapshot timestamps, and defaults.

## UI Rules

### Global Rules

- Bottom-right status is the only overall health/status surface.
- The chart must not have its own status light or top-left status sentence.
- `0 °C` must never be used as a placeholder for unavailable temperature.
- Control-point dots remain visible in every state.
- `System Default` is visible only in preview or off states.
- The user curve is gray in setup-required, approval-required, off, and
  degraded preview states.
- The user curve is blue only in active on or boost states.
- Runtime orange markers show only when telemetry is live and semantically
  meaningful.

### Setup Required: Background Agent Not Installed

Use when the app cannot talk to the runtime owner at all. This is a full-window
setup design with no dashboard sidebar because there is no agent-owned runtime
state to monitor.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Fan Curve                                                                   │
│                                                                             │
│                         Background Agent Not Installed                      │
│                                                                             │
│  Fan Curve needs its Background Agent before it can monitor temperatures,    │
│  evaluate the curve, or apply fan commands while the app is closed.          │
│                                                                             │
│  The dashboard is hidden until the Background Agent is installed because     │
│  temperature, fan, helper, and control status would otherwise be guesses.    │
│                                                                             │
│                         [ Set Up Background Agent ]                         │
│                                                                             │
│  ● Background Agent Required                                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Setup Required: Background Agent Needs Approval

Use when the Background Agent is installed but macOS still requires user
approval before it can run. This is also a full-window setup design with no
dashboard sidebar because the app still cannot rely on agent-owned state.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Fan Curve                                                                   │
│                                                                             │
│                         Background Agent Needs Approval                     │
│                                                                             │
│  macOS is waiting for approval before Fan Curve can start its Background     │
│  Agent. Open System Settings, approve the login item, and return here.       │
│                                                                             │
│  The setup button follows the HIG interaction rule: after a click, the       │
│  button is disabled and shows a persistent spinner until the operation       │
│  completes or fails.                                                        │
│                                                                             │
│                         [ Open System Settings ]                            │
│                                                                             │
│  ● Approval Required                                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Setup Required: Helper Missing

Use when the agent is alive and telemetry is available, but privileged writes
are unavailable.

This is a monitor-only dashboard state. The agent is installed, so telemetry
can be shown when live, but fan-control writes remain disabled until the helper
is installed.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Fan Speed (% / RPM)                                  │ CPU Temperature          │
│                                                      │ 58 °C                    │
│  100% ┤                         ○────○────○          │                          │
│   80% ┤                    ○                         │ CPU              18%     │
│   60% ┤                                              │ GPU               4%     │
│   40% ┤              ○           ··· system          │                          │
│   20% ┤        ○              ···     default        │ Fan 0          2,317 RPM │
│    0% ┼○····················                         │ Fan 1          2,329 RPM │
│       35°   78° 84° 90° 96° 101° 106° 110°          │                          │
│                                                      │ Fan Control              │
│  user curve: gray                                    │ Monitor Only             │
│  system default: visible                             │ [ Set Up System Helper ] │
│  runtime markers: visible if telemetry live          │ ● System Helper Required │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

### Setup Required: Helper Needs Approval

Use when the Background Agent is running but macOS still requires approval for
the privileged helper. The dashboard remains monitor-only, fan-control writes
remain disabled, and the setup button uses the same HIG interaction rule:
clicking disables the button and shows a persistent spinner until the action
completes or fails.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Fan Speed (% / RPM)                                  │ CPU Temperature          │
│                                                      │ 58 °C                    │
│  100% ┤                         ○────○────○          │                          │
│   80% ┤                    ○                         │ CPU              18%     │
│   60% ┤                                              │ GPU               4%     │
│   40% ┤              ○           ··· system          │                          │
│   20% ┤        ○              ···     default        │ Fan 0          2,317 RPM │
│    0% ┼○····················                         │ Fan 1          2,329 RPM │
│       35°   78° 84° 90° 96° 101° 106° 110°          │                          │
│                                                      │ Fan Control              │
│  user curve: gray                                    │ Monitor Only             │
│  system default: visible                             │ [ Open System Settings ] │
│  runtime markers: visible if telemetry live          │ ● Approval Required      │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

### Off / Preview

Use when both components are ready and telemetry is live, but fan control is
off.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Fan Speed (% / RPM)                       Fan Now    │ CPU Temperature          │
│                                   Thermal Demand     │ 58 °C                    │
│  100% ┤                         ○────○────○          │                          │
│   80% ┤                    ○                         │ CPU              18%     │
│   60% ┤                                              │ GPU               4%     │
│   40% ┤              ○           ··· system          │                          │
│   20% ┤        ○              ···     default        │ Fan 0          2,317 RPM │
│    0% ┼○····················                         │ Fan 1          2,329 RPM │
│       35°   78° 84° 90° 96° 101° 106° 110°          │                          │
│                                                      │ Fan Control        [off] │
│  user curve: gray                                    │ Off                      │
│  system default: visible faint dashed comparison     │                          │
│  Fan Now marker: inactive gray if telemetry is fresh │ ● All systems go         │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

### On / Active

Use when both components are ready and the agent is actively applying the
curve.

`System Default` must be hidden in both active and boost states. Active and
boost states show only the blue user curve, live runtime markers, and the
boost affordance when boost is not already active.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Fan Speed (% / RPM)                       Fan Now    │ CPU Temperature          │
│                                   Thermal Demand     │ 78 °C                    │
│  100% ┤                         ●────●────●          │                          │
│   80% ┤                    ●                         │ CPU              31%     │
│   60% ┤                                              │ GPU              26%     │
│   40% ┤              ●                               │                          │
│   20% ┤        ●       ○ demand                      │ Fan 0        2,623 RPM   │
│    0% ┼●       ● now                                 │ Fan 1        2,818 RPM   │
│       35°   78° 84° 90° 96° 101° 106° 110°          │                          │
│                                                      │ Fan Control         [on] │
│  user curve: blue                                    │ Curve active             │
│  system default: hidden                              │ Stepping up toward 43%   │
│  runtime markers: visible if fresh                   │ [ Boost Fans ]           │
│                                                      │ ● All systems go         │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

### Boost / Active

Use when the user has explicitly enabled Boost. Boost is still an active
agent-owned control state, so `System Default` remains hidden and the user
curve remains blue.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Fan Speed (% / RPM)                       Fan Now    │ CPU Temperature          │
│                                   Thermal Demand     │ 86 °C                    │
│  100% ┤                         ●────●────●          │                          │
│   80% ┤                    ●       ○ demand          │ CPU              45%     │
│   60% ┤                                              │ GPU              37%     │
│   40% ┤              ●                               │                          │
│   20% ┤        ●                                     │ Fan 0        4,812 RPM   │
│    0% ┼●             ● now                           │ Fan 1        4,955 RPM   │
│       35°   78° 84° 90° 96° 101° 106° 110°          │                          │
│                                                      │ Fan Control      [boost] │
│  user curve: blue                                    │ Boost active             │
│  system default: hidden                              │ [ Stop Boost ]           │
│  runtime markers: visible if fresh                   │ ● All systems go         │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

### Degraded / Stale

Use when setup is complete but runtime data is stale or a component is
unhealthy. This state replaces the graph with a diagnostic panel; it is not a
normal graph with stale or guessed chart values.

```text
┌──────────────────────────────────────────────────────┬──────────────────────────┐
│ Runtime data is stale                                │ CPU Temperature          │
│                                                      │ -- °C                    │
│ Fan Curve cannot show the live graph because the     │ Telemetry unavailable    │
│ Background Agent has not published a fresh snapshot. │                          │
│                                                      │ CPU              --      │
│ Last state: waiting for agent snapshot               │ GPU              --      │
│ Recovery: retry the agent connection                 │ Fans             --      │
│                                                      │                          │
│                     [ Retry ]                        │ Fan Control              │
│                                                      │ Snapshot Pending         │
│  graph: replaced by diagnostic panel                 │                          │
│  system default: hidden                              │ ● Agent Not Responding   │
│  runtime markers: hidden                             │                          │
└──────────────────────────────────────────────────────┴──────────────────────────┘
```

## Migration Path

1. Introduce the explicit runtime state model in the agent.
2. Add app-facing agent XPC for commands plus state subscription.
3. Move the app off direct helper XPC for setup, probe, preview, learn, and
   product flows.
4. Keep helper XPC only behind the agent.
5. Remove app-side readiness inference and replace it with agent-owned
   product states.
6. Only after the agent path is stable, retire shared-defaults-plus-Darwin as
   the live control and status bus.

## Public Interfaces / Types

Introduce or replace with explicit types such as:

- `RuntimeState`
- `SetupState`
- `ControlState`
- `TelemetryState`
- `RuntimeHealth`
- `AgentCommand`

App-facing XPC should expose:

- `getCurrentState() -> RuntimeState`
- `subscribeStateUpdates(...)`
- `setCurve(...)`
- `setFanControlEnabled(...)`
- `setBoostEnabled(...)`
- `setApplyInBackground(...)`
- `requestSetupAction(...)`

Helper-facing XPC should remain narrow and write-oriented:

- `applyFanActions(...)`
- `resetFansToAuto(...)`
- `getOwnershipStatus(...)`
- optional `getHelperHealth(...)`

## Test Plan

- `make build`
- `make test`
- `make log-audit`
- `make run`

State rendering checks:

- Agent missing -> setup-required UI, no fake telemetry
- Helper missing with agent alive -> telemetry visible, control disabled,
  helper CTA visible
- Both ready + off -> gray user curve, system default visible
- Both ready + on -> blue user curve, system default hidden
- Degraded or stale -> no fake `0 °C`, no fake fan rows, bottom-right degraded
  status only

IPC behavior checks:

- App command updates reach the agent without helper direct calls
- Agent state updates reach the app without app polling the helper
- Helper outages degrade agent state cleanly without crashing the app

Regression checks:

- No top-left chart status
- `System Default` never visible in active mode
- Control-point dots remain visible in every state
- No duplicate “not set up” concepts in copy

## Assumptions

- The agent reads telemetry directly and uses helper XPC only for writes and
  ownership-sensitive status.
- App <-> agent communication moves to XPC.
- The helper continues to own write-side ownership/arbitration semantics.
- The app should see only product-level states, not helper/runtime internals.
