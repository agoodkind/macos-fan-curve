# FAN-56 live reproduction

## macOS 26.6.1 (25G76)

Guest: fan-56-first-install-repro, cloned from the cached external-volume base image.
Product: unmodified published FanCurve-26.8.30-r1.dmg.

Before launch, /Applications/Fan Curve.app was absent and sfltool dumpbtm listed no Fan Curve records.

First launch displays Enable Background Control with a disabled Enabling Background Control spinner. Clicking it produces no registration. Opening Settings through the gear and clicking its separate Enable Background Control succeeds.

Logs: 21:22:48.977 agent.register.started; 21:22:50.429 agent.register.done status=enabled; 21:22:50.711 presence becomes running with evidence=connection.

The helper becomes Unavailable with System Helper registration definition was not found. Clicking Install System Helper at 21:23:18.849 sends forced_repair. At 21:23:18.866 it returns unavailable. No helper.service.register.started appears.

Screenshots captured in conversation show the disabled onboarding action and the matching reporter helper error. Logs and service records are saved alongside this report.

## Bundle-ownership counterexample

A throwaway Fan56Probe.app contains ProbeMain and ProbeAgent executables plus a real daemon plist and inert ProbeDaemon executable. Both binaries report Bundle.main=/Applications/Fan56Probe.app and identifier io.goodkind.fan56.probe.

Before registration both report status 3. ProbeAgent register returns SMAppServiceErrorDomain code 1 (Operation not permitted), while the resulting status becomes 2 (requiresApproval).

This disproves the blanket claim that a secondary command-line executable cannot resolve the containing app bundle. It also demonstrates that notFound is not sufficient evidence of a missing daemon plist before registration. The original product flow never reaches register() from that state.

No Fan Curve source was changed. The guest was stopped with its state preserved.
