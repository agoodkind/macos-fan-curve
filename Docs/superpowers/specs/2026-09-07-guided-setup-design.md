# Complete background control setup

Fan Curve uses one user-authorized setup flow to install its Background Agent and System Helper.

## Preserve service ownership

The app registers the Agent. The Agent registers and verifies the Helper. No app-to-Helper connection or second helper registration path is added.

One app-lifetime installation model serves onboarding, Settings, and the dashboard sidebar. Closing a window does not discard setup progress or stop reconciliation.

## Continue from observed state

Enable Background Control authorizes the complete setup sequence. Setup registers the Agent, waits for approval and an Agent connection, requests Helper installation through the Agent, then waits for approval and verified Helper identity.

Persist unfinished user intent so relaunch continues from the observed unfinished stage. Do not repeat registration for a component already installed. An explicit disable cancels unfinished intent. Approval-required state never authorizes repeated registration.

Unknown status, active work, and available user action are separate concepts. Unknown Helper status cannot disable Agent installation. All setup surfaces derive their action and busy state from the shared model.

## Report failures

A failed operation stops automatic progress and preserves its cause. Retry requires user action. Returning from System Settings reobserves state without repeating a failed mutation on each poll.

An explicit Helper install may begin from `notFound`. Existing artifact validation decides whether the bundle is usable before registration. That status alone does not prove a missing registration definition.

Existing upgrade replacement, interrupted-replacement recovery, cancellation handling, fan reset, and identity verification remain authoritative. Settings retains individual repair actions through the same owners.

## Establish acceptance

Behavioral Swift tests cover fresh setup, approval return, relaunch, explicit disable, failed registration, and verified completion. Controlled service scenarios must represent `notFound`.

Fresh signed Release installation must complete on macOS 15 and macOS 26 with guest SIP verified enabled. Preserve screenshots, service state, identity, and logs. Repeat old-to-new upgrade and healthy repair acceptance without changing physical host services for VM testing.

No shell tests, static source assertions, new retry loops, or security-policy bypasses are part of this change.
