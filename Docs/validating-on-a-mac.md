# Validating Fan Curve on a Mac

How to confirm a build of Fan Curve actually works, on any Mac, by installing it and
using it. This covers what automated tests cannot: real `SMAppService` registration, real
launchd, real approval prompts in System Settings, and real fan hardware.

Run this before shipping a release, and after any change to setup, the background agent,
the privileged helper, or the XPC paths between them.

## What you need

A Mac with fans. Apple silicon laptops and desktops have them; confirm with
`Fan Curve.app` reporting a nonzero fan count, or `powermetrics --samplers smc` showing a
fan RPM.

A signing identity. `security find-identity -v -p codesigning` must list a
`Developer ID Application` certificate. Without one the app cannot register a login item
or a privileged helper, and every setup step below fails for that reason rather than a
real one.

Ideally a Mac that has never run Fan Curve. First-run setup, approval prompts, and
`SMAppService` registration only happen once per machine, and a machine that has already
approved them will skip exactly the steps most worth testing. Options, in order of
fidelity: a spare Mac, a fresh macOS virtual machine, or a new user account on your own
Mac. See [Getting a clean machine](#getting-a-clean-machine).

## Build the app you will test

Build on the Mac that holds the signing identity. Do not build on the machine under test
if that machine is a VM or a borrowed Mac: entitlements are authorized per machine, and a
build produced somewhere without your certificate cannot be signed correctly.

```sh
make app
```

That produces `Products/Fan Curve.app`, signed and staged. Confirm before going further:

```sh
codesign -dv --verbose=2 "Products/Fan Curve.app"
codesign -v --verbose=2 --strict "Products/Fan Curve.app"
```

The output must show `Authority=Developer ID Application: <your name> (<TEAM>)`,
`flags=0x10000(runtime)` for the hardened runtime, a `Timestamp=`, and
`satisfies its Designated Requirement`. A missing team identifier means the build did not
sign, and everything after this point will fail in confusing ways.

`spctl -a -t exec` will report `rejected: Unnotarized Developer ID` for a local build.
That is expected and does not block any step here. It only matters for distribution.

## Install it

`/Applications/Fan Curve.app` is the only supported location. The login item and the
privileged helper both register from that exact path, so a copy run from anywhere else
registers a path that will not exist later.

On the build machine:

```sh
make install-app
```

On a different machine, move the signed bundle across as an archive. A plain `cp` from a
network or shared volume can silently truncate a large bundle, and `rsync` strips the
signature:

```sh
# on the build machine
ditto -c -k --keepParent "Products/Fan Curve.app" /tmp/fan-curve.zip
shasum -a 256 /tmp/fan-curve.zip
scp /tmp/fan-curve.zip <user>@<test-machine>:~/

# on the test machine
shasum -a 256 ~/fan-curve.zip        # must match the line above
ditto -x -k ~/fan-curve.zip /Applications/
codesign -v --verbose=2 --strict "/Applications/Fan Curve.app"
```

Compare the two checksums before extracting. A mismatch means the transfer corrupted the
bundle, and the signature check afterward is what proves it survived intact.

## Walk the setup flow

This is the part that automated tests cannot reach, because it involves approval prompts
a person has to click.

Launch the app from `/Applications`. On a machine that has never run it, expect the
Background Agent setup screen rather than the dashboard.

**Enable the Background Agent.** The app registers a login item through `SMAppService`.
macOS may show an approval prompt, or place the item in System Settings under
General, Login Items and Extensions, awaiting approval. Approve it there.

Confirm it took:

```sh
launchctl print gui/$(id -u)/io.goodkind.fancurveagent
```

Expect `state = running` and a `program` path under `/Applications/Fan Curve.app`. If the
path points anywhere else, the app was launched from a copy and the registration is
wrong.

**Install the System Helper.** The app asks the agent to register a privileged
`LaunchDaemon`, so macOS prompts for an administrator password. Approve it.

Confirm:

```sh
sudo launchctl print system/io.goodkind.smcfanhelper
```

Expect `state = running`. Exit status 113 means not found, so the registration did not
happen.

**Confirm the app advances.** The setup screen should give way to the dashboard, showing
live temperature and fan RPM. Stale or absent telemetry here means the app is not talking
to the agent, even though both services registered.

## Verify it controls fans

Set a curve that demands a fan speed clearly above idle, enable fan control, and load the
CPU:

```sh
yes > /dev/null & yes > /dev/null &
```

Watch the dashboard. Fan Now should climb toward Thermal Demand within a few seconds, and
the physical fans should become audible. Stop the load with `kill %1 %2` and confirm the
fans settle back down.

Cross-check the RPM the app reports against the hardware, so you are not just reading the
app's own claim back to itself:

```sh
sudo powermetrics --samplers smc -n 1 -i 1000 | grep -i fan
```

Then quit the app and confirm the fans return to automatic control rather than staying
pinned where you left them.

## Verify recovery

These are the paths that break quietly and that a person is far better at catching than a
test.

**The agent dies.** Kill it and confirm the app notices and recovers:

```sh
pkill -f FanCurveAgent
```

The dashboard should report telemetry as unavailable, then recover on its own once
launchd restarts the agent. It must not sit reporting stale values as though they were
current, and it must not require a relaunch.

**The helper dies.** Kill it and confirm the agent reconnects:

```sh
sudo pkill -f io.goodkind.smcfanhelper
```

**The machine sleeps.** Sleep it, wake it, and confirm fan control resumes without
intervention.

**The app is already set up.** Quit and relaunch. It should go straight to the dashboard,
with no setup screen and no re-approval.

## When something looks wrong

Read the app's own logs first. Everything it does is logged under one subsystem:

```sh
log show --last 10m --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Follow it live while reproducing:

```sh
log stream --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Log lines are dotted and name their recovery, for example
`agent_client.connection.disconnected reason=invalidated recovery=schedule-reconnect`.
The `recovery=` value tells you what the code decided to do, which is usually the fastest
way to see where behavior diverged from what you expected.

If a service will not register, check whether macOS is holding it for approval:

```sh
sfltool dumpbtm | grep -A5 -i fancurve
```

Items awaiting approval appear there with a disposition showing they are disabled.
Approving in System Settings is the fix; deleting and re-registering usually is not,
because the Background Task Management database keeps the old record until overnight
maintenance runs.

## Getting a clean machine

Setup is once per machine, so a machine that has already approved Fan Curve cannot test
the approval flow again without being reset.

**A new user account** is the cheapest option and is enough for the login-item half of
setup. The privileged helper is system-wide, so it will already be registered.

**A virtual machine** gives a genuinely clean system. [Tart](https://tart.run) works:

```sh
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest fan-curve-check
tart run fan-curve-check
```

Then transfer the signed app as described above, using `tart ip fan-curve-check` for the
address. Guests log in as `admin` with password `admin`.

Two things about VMs are worth knowing before you spend time on one.

A signed Developer ID build runs in a stock guest with code signing fully enforced. You do
not need to disable System Integrity Protection or set `amfi_get_out_of_my_way=1`, and you
should not: disabling Apple Mobile File Integrity turns off the signature and entitlement
checking that this validation exists to exercise. Verified 2026-07-29 on a
`macos-tahoe-base` guest running macOS 26.5, with `boot-args` empty.

To drive the UI in a guest, enable developer tools for the account first, or UI automation
is refused:

```sh
sudo DevToolsSecurity -enable
sudo dseditgroup -o edit -a "$USER" -t user _developer
```

**A spare Mac** is the highest-fidelity option and the only one with real fans, so it is
the only place the fan-control checks above mean anything. A VM has no fan hardware, which
makes it useful for setup, approval, and reconnect behavior, and useless for verifying
that the curve actually moves a fan.

## Leave the machine as you found it

If you tested on a machine you use, undo it: quit the app, confirm the fans returned to
automatic, and remove the login item under General, Login Items and Extensions. To remove
the privileged helper:

```sh
sudo launchctl bootout system/io.goodkind.smcfanhelper
```

Delete a disposable VM rather than keeping it, so the next validation starts from a base
image rather than from whatever the last run left behind:

```sh
tart delete fan-curve-check
```
