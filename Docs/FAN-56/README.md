# FAN-56 installation investigation

Published Fan Curve releases reproduce the first-install failure on macOS 15.7.7 and macOS 26.6.2. The final candidate completes guided setup on both systems.

Source report: [GitHub issue 91](https://github.com/agoodkind/macos-fan-curve/issues/91). Investigation date: 2026-09-07. Follow-up validation: 2026-09-09.

## Current acceptance

Fresh setup reaches verified Helper identity after one Enable Background Control action and macOS approval on both tested systems. The final macOS 15 Agent remains running after the GPU telemetry fix.

| Test | Result | Evidence |
| --- | --- | --- |
| Enable SIP through Recovery, then boot normally | Enabled on macOS 15.7.7 and 26.6.2 | [15 status](evidence/macos15-sip-enabled.txt), [26 status](evidence/macos26-sip-enabled.txt) |
| Published 26.9.7-r1 on SIP-enabled macOS 26 | Original disabled onboarding and rejected helper install reproduce | [Helper log](evidence/macos26-sip-original-helper.log) |
| First candidate on both systems | Registration reaches approval; approval starts Helper but cached Agent state never advances | [15 log](evidence/macos15-sip-candidate1-approval-stall.log), [26 log](evidence/macos26-sip-candidate1-approval-stall.log) |
| Second candidate on macOS 26 | Passive observation verifies Helper and persists complete | [Setup log](evidence/macos26-sip-candidate2-setup.log) |
| Second candidate on macOS 15 | Helper verifies and setup completes; Agent then crashes repeatedly | [Setup log](evidence/macos15-sip-candidate2-setup.log) |
| Final candidate on macOS 15 | Fresh setup completes; Agent and Helper show Running; Agent remains stable after relaunch | [Setup log](evidence/macos15-final-fresh-setup.log), [runtime evidence](evidence/final-runtime-summary.md) |
| Final candidate on macOS 26 | Fresh setup completes; Agent and Helper show Running; Agent remains stable after relaunch | [Setup log](evidence/macos26-final-fresh-setup.log); see runtime evidence above |
| Explicit disablement on both systems | The Agent exits; relaunch does not override the disabled state | See runtime evidence above |
| Settings repair on both systems | The action reaches Agent-owned repair; missing AppleSMC stops fan reset and preserves registration | [15 log](evidence/macos15-final-repair.log), [26 log](evidence/macos26-final-repair.log) |
| Candidate-to-final upgrade on both systems | Agent refresh completes; Helper replacement stops safely at the unavailable AppleSMC reset | [Runtime evidence](evidence/final-runtime-summary.md), [15 log](evidence/macos15-final-upgrade.log), [26 log](evidence/macos26-final-upgrade.log) |

The first candidate omitted an observation edge: the app's timer copied cached Agent state, while approval paused the Agent's normal observers. The second candidate uses the existing timer and Agent current-state request to recheck ServiceManagement and run existing passive identity verification. It adds no timer or forced registration.

The macOS 15 crash occurs in `readIOAcceleratorDeviceUtilizationPercent`, through `CFDictionaryGetValueIfPresent` and an Objective-C `hash` message. The reader converted a temporary bridged string into an unretained pointer and used it in a later statement. The final candidate retains the lookup key through the dictionary call. A real GPU statistic test performs 1,000 public reader calls inside autorelease pools. The installed final Agent remained stable beyond the earlier ten-second crash interval.

On September 9, `make verify` passed all 291 tests and the launch, run, and Settings audits. The Settings audit now checks the current extended-range access controls instead of controls removed in August. `make lint-swiftlint lint-format lint-complexity swiftcheck-extra`, `make log-audit`, and `make -B release-assets FORCE=1 ARTIFACT_VERSION=fan56-review` also passed.

Registration-error and schema-mismatch regression tests failed before their fixes and passed afterward. A forced dead-code scan exposed a separate build fault: unsigned analysis products replaced the deployable Debug app. Isolating analysis output preserved the Debug executable and signed resource manifest byte-for-byte across `make -B lint-deadcode FORCE=1`. Deep signature verification and normal `make run` then passed, including installation and launch at the canonical path.

| Candidate artifact | SHA-256 |
| --- | --- |
| FanCurve-fan56-guided-setup.dmg | `e0b8337c743e59c681ab36d1cbfb7219dbc18ae30404ea37bcce826b9d37674d` |
| FanCurve-fan56-candidate2.dmg | `b1dbe57df531b009e079f09e778297bef17886ec704224ab463ba5b6412d86ec` |
| FanCurve-fan56-final.dmg | `4729942b16338bb4b5b4bdb3e185ac1ac23a6bdfee822988ad9cff74955d58fe` |
| FanCurve-fan56-review.dmg | `9a76aed5fbe07b0b5c2fa58495172550b1767f32e7f077b0b67e1209d127e504` |

The candidates are local Developer ID-signed Release builds, not notarized published updates. Their display version is 0.0.0. Sparkle's offer to replace them with the published release was skipped during testing. These tests do not prove a new Sparkle deployment, a packaged Sparkle upgrade, or physical fan control. Tart has no AppleSMC device, so it cannot complete the mandatory fan reset that precedes Helper replacement.

## Reproduction matrix

Each row used a separate fresh clone with no existing Fan Curve app. Installation copied the unmodified published app into the guest's `/Applications/Fan Curve.app`; strict deep signature verification passed. No Fan Curve source or released binary was modified.

| Guest OS | Fan Curve release | First-launch action | Helper installation from Settings | Evidence |
| --- | --- | --- | --- | --- |
| 15.7.7, build 24G720 | 26.8.30-r1, reported release | Disabled Enabling Background Control spinner before registration | Agent registers and connects; helper reports missing registration definition; Install returns the same failure | [Installation](evidence/macos15-reported-install.log) |
| 15.7.7, build 24G720 | 26.9.7-r1, latest release at test start | Same disabled spinner | Same helper failure | [Installation](evidence/macos15-latest-install.log) |
| 26.6.2, build 25G83 | 26.8.30-r1, reported release | Same disabled spinner | Same helper failure | [Installation](evidence/macos26-reported-install.log) |
| 26.6.2, build 25G83 | 26.9.7-r1, latest release at test start | Same disabled spinner | Same helper failure | [Installation](evidence/macos26-latest-install.log) |

An additional preliminary run on cached macOS 26.6.1, build 25G76, showed the same behavior. The four-row comparison above uses the newly fetched latest image tags.

The macOS 15 image is 15.7.7, not the reporter's exact 15.7.9. The downloaded images have System Integrity Protection disabled by default: [macOS 15 status](evidence/macos15-security.txt), [macOS 26 status](evidence/macos26-security.txt). These results prove reproduction in those guests, not full physical-Mac acceptance with standard security settings. No privacy-database or security-setting changes were made during the four comparison cases. VM fan hardware was not used to infer real fan-control correctness.

## Observed sequence

1. Launch the published app in a fresh guest. The main window displays Enable Background Control, but its button is disabled and says Enabling Background Control. Clicking does not initiate registration.
2. Open Settings using the app's gear button. General has a separate enabled Enable Background Control action.
3. Click that action. The Background Agent registers and establishes XPC. The row becomes Running.
4. The helper row becomes Unavailable with `System Helper registration definition was not found`.
5. Click Install System Helper. The request reaches the Agent's forced-repair operation, which returns the same error. No helper registration request occurs and no helper approval entry is created.

The tool channel is verified by positive events: the real Settings click logs `agent.service.register.started`, then `agent_client.connection.ready`; the later helper click logs `system_helper.reconcile.started operation=forced_repair` and `agent.xpc.command.helper_install.failed`. Across all four product logs, there are zero `helper.service.register.started` events. Source tracing confirms the return occurs before that boundary.

| Case | Helper command failure time, UTC |
| --- | --- |
| macOS 15, reported release | 21:39:06.654 |
| macOS 15, latest release | 21:42:15.578 |
| macOS 26, reported release | 21:58:07.995 |
| macOS 26, latest release | 21:59:09.888 |

## Why setup fails

Two independent product decisions explain the observed failures at source commit `8bea1bc2878ab8a73dc98af1f21180cb73756672`.

The onboarding action derives its busy state from both Agent registration and Helper busy state. The Helper initially reports checking, which is busy. Its state cannot resolve before the missing Agent connects, but that same busy state disables the action needed to register the Agent. Settings uses a separate Agent action and escapes this cycle. See [the button and busy-state implementation](https://github.com/agoodkind/macos-fan-curve/blob/8bea1bc2878ab8a73dc98af1f21180cb73756672/Sources/Views/OnboardingView.swift#L250).

The helper reconciler treats `.notFound` as a terminal missing-definition condition. It permits explicit registration only from `.notRegistered`, so forced repair returns before validating the artifact or calling ServiceManagement. See [the registration gate](https://github.com/agoodkind/macos-fan-curve/blob/8bea1bc2878ab8a73dc98af1f21180cb73756672/Sources/Agent/SystemHelperLifecycleReconciler.swift#L154) and [status classification](https://github.com/agoodkind/macos-fan-curve/blob/8bea1bc2878ab8a73dc98af1f21180cb73756672/Sources/Models/SystemHelperClassifier.swift#L31).

## Counterexample to the earlier diagnosis

The earlier claim that a secondary command-line executable cannot resolve its containing app bundle is withdrawn.

A separate inert probe app contains a main executable, a secondary executable, a valid daemon plist, and a daemon that performs no fan operations. Both executables resolve `Bundle.main` to the same containing app. Before first registration, both observe status 3 (`notFound`). Calling `register()` from the secondary executable changes status to 2 (`requiresApproval`), although it throws `SMAppServiceErrorDomain` code 1, Operation not permitted.

The probe produced the same result on [macOS 15](evidence/macos15-latest-service-probe.log) and [macOS 26](evidence/macos26-latest-service-probe.log). This proves that `.notFound` alone is insufficient to diagnose a missing plist in these environments. It does not prove that every secondary-executable arrangement is supported on every OS.

## Implemented scope

The approved guided flow shares one app-lifetime installation owner across onboarding, Settings, and the sidebar. It persists unfinished user intent, pauses for approval, resumes from actual observations, and retains failures for explicit retry. Individual Settings repair actions use the same workflow.

The app still registers only the Agent. The Agent owns Helper validation, registration, approval observation, replacement, and active identity verification. Explicit first installation admits `notFound`; passive startup does not gain permission to install. Existing interrupted-replacement policy remains unchanged.

Pending setup no longer suppresses a confirmed outdated-Agent replacement. Approval reads wait for the replacement Agent's observed identity instead of querying the retiring connection. Active mutations and intentional disable remain protected from automatic replacement.

Approval polling reconciles only a real ServiceManagement transition. An unchanged denied registration remains approval-required without repeating registration every two seconds, while later approval or removal still triggers one fresh read.

## Validation results

- The real onboarding action remains available while Helper state is unresolved and reaches Agent registration.
- Explicit first installation from `.notFound` validates the Helper artifact and reaches registration.
- Approval return reaches verified Agent and Helper identity without a second Helper registration path.
- Relaunch preserves completed setup on both systems.
- Explicit disablement stops the Agent and remains disabled after relaunch.
- Settings repair reaches the Agent-owned forced repair path and preserves registration when fan reset fails.
- Candidate-to-final upgrade replaces the Agent on both systems. Tart cannot complete Helper replacement because it has no AppleSMC device.
- The candidate and final checks use installed Release apps with System Integrity Protection enabled. No shell test suite or static source-text assertion was added.

## Artifact identity and retained state

| Artifact | SHA-256 |
| --- | --- |
| FanCurve-26.8.30-r1.dmg | `beabd2b95b47de714353f6324e4d694a972e9874fa29b01322db865d6e251ca9` |
| FanCurve-26.9.7-r1.dmg | `9d11273ea4a314453ad52df2f13d39b3c0250f10c85fcaca7b0ec98c60453014` |
| macOS 15 image manifest | `4947ac5ab1b2fdc46ab856132d2ba958f8e45b5f85192c66370dafc028c514dd` |
| macOS 26 image manifest | `1b093499716409d29e8b5336844528e1cae375db97d2ad8e5aeff78cf0da201e` |

Both image manifests were fetched from the vendor's latest tags on 2026-09-07 and carry upload dates of 2026-09-05. Blobs were downloaded with the volume's documented aria2 helper and imported from local HTTP registries. No default Tart internet image download was used.

The preserved guests are `fan56-macos15-reported`, `fan56-macos15-latest`, `fan56-macos26-reported`, and `fan56-macos26-latest`, under the volume's Tart home. The preliminary guest is `fan-56-first-install-repro`. All are stopped. Existing guests and caches were preserved.

The retained logs and install transcripts are under [evidence](evidence/). The original four release comparisons changed no product source. Subsequent candidate implementation and verification are described above.
