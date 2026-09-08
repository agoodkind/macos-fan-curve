# Final installed runtime evidence

The final Release candidate was installed at `/Applications/Fan Curve.app` on macOS 15.7.7 and macOS 26.6.2. System Integrity Protection was enabled on both guests.

## Fresh setup

One Enable Background Control action reached Background Agent approval. After approval, both guests persisted `guidedSetupProgress=complete` and showed the Background Agent and Privileged Helper as Running.

The Background Agent remained at PID 705 on macOS 15 and PID 782 on macOS 26 before and after the app quit and relaunch.

After explicit disablement in Login Items, the Agent process exited on both guests. Relaunching the app did not register or start it. The app displayed Allow Fan Curve in Background and required a new user action.

The Reinstall System Helper action reached the Agent-owned forced repair path on both guests. Artifact validation completed with Helper hash `8454d3a7b01f`. The virtual machines have no AppleSMC device, so the required fan reset returned Failed to open AppleSMC. The flow preserved the existing Helper registration and displayed Repair Failed with a retry action.

## Upgrade

The installed candidate started with these executable hashes:

| Component | Before | Final |
| --- | --- | --- |
| Background Agent | `10869efeb8e2` | `b97b93eaf63d` |
| Privileged Helper | `b11271ab8a93` | `8454d3a7b01f` |

After the canonical app was replaced, the final app observed the old Agent hash and completed registration refresh on both guests. macOS 15 moved to Agent PID 880, started at 05:53:44. macOS 26 moved from PID 549 to PID 942, started at 05:53:20.

The final Agent then validated the final Helper artifact and started automatic Helper replacement on both guests. The virtual machines again failed the required fan reset because AppleSMC is absent. The flow preserved the registered candidate Helper and returned a specific retryable failure. The successful physical fan reset and Helper binary swap cannot be observed in Tart.

Candidate Agent crash reports on macOS 15 ended at 05:53:08. The final Agent started at 05:53:44 and remained PID 880 through the final observation after 05:56. macOS 26 remained PID 942 through the same observation. No final Agent crash report appeared on either guest.

## Artifact

`FanCurve-fan56-final.dmg` SHA-256: `4729942b16338bb4b5b4bdb3e185ac1ac23a6bdfee822988ad9cff74955d58fe`
