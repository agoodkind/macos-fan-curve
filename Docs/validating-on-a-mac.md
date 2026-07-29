# Validate Fan Curve on a Mac

This guide confirms that a Fan Curve build works on real hardware. It covers what
automated tests cannot reach: Service Management registration, launchd, approval prompts
in System Settings, and the fans themselves.

Run it before shipping a release. Run it again after changing setup, the background
agent, the privileged helper, or the connections between them.

## Gather what you need

**A Mac with fans.** Apple silicon laptops and desktops have them. Confirm with
`powermetrics --samplers smc`, which prints a fan speed in revolutions per minute (RPM).

**A signing identity.** Run `security find-identity -v -p codesigning`. The output must
list a `Developer ID Application` certificate. Without one, the app cannot register a
login item or a privileged helper. Every setup step below then fails for that reason
rather than a real one.

**A Mac that has never run Fan Curve**, ideally. First-run setup, approval prompts, and
Service Management registration happen once per machine. A machine that already approved
them skips the steps most worth testing. See [Get a clean machine](#get-a-clean-machine).

## Build the app

Build on the Mac that holds the signing identity. Entitlements are authorized per
machine, so a build produced elsewhere cannot be signed correctly.

```sh
make app
```

This produces `Products/Fan Curve.app`, signed and staged. Verify the signature before
continuing:

```sh
codesign -dv --verbose=2 "Products/Fan Curve.app"
codesign -v --verbose=2 --strict "Products/Fan Curve.app"
```

The output must contain four things:

- `Authority=Developer ID Application: <your name> (<TEAM>)`
- `flags=0x10000(runtime)`, the hardened runtime
- a `Timestamp=` line
- `satisfies its Designated Requirement`

A missing team identifier means the build did not sign. Stop and fix that first.

`spctl -a -t exec` reports `rejected: Unnotarized Developer ID` for a local build. That is
expected. Notarization matters for distribution, not for this guide.

## Install the app

Install to `/Applications/Fan Curve.app`. The login item and the privileged helper both
register from that exact path. A copy run from anywhere else registers a path that will
not exist later.

On the build machine:

```sh
make install-app
```

On a different machine, move the bundle as an archive. A plain `cp` from a network or
shared volume can truncate a large bundle without reporting an error, and `rsync` strips
the signature.

```sh
# on the build machine
ditto -c -k --keepParent "Products/Fan Curve.app" /tmp/fan-curve.zip
shasum -a 256 /tmp/fan-curve.zip
scp /tmp/fan-curve.zip <user>@<test-machine>:~/

# on the test machine
shasum -a 256 ~/fan-curve.zip
ditto -x -k ~/fan-curve.zip /Applications/
codesign -v --verbose=2 --strict "/Applications/Fan Curve.app"
```

Compare the two checksums before extracting. A mismatch means the transfer corrupted the
bundle. The signature check afterward proves it survived intact.

## Complete setup

Setup involves approval prompts that a person has to click, which is why no automated
test covers it.

Launch the app from `/Applications`. On a machine that has never run it, expect the
Background Agent setup screen rather than the dashboard.

**Enable the Background Agent.** The app registers a login item. macOS either shows an
approval prompt or places the item in System Settings under General, Login Items and
Extensions. Approve it there.

```sh
launchctl print gui/$(id -u)/io.goodkind.fancurveagent
```

Expect `state = running` and a `program` path inside `/Applications/Fan Curve.app`. A
path pointing elsewhere means the app was launched from a copy, and the registration is
wrong.

**Install the System Helper.** The app asks the agent to register a privileged daemon, so
macOS prompts for an administrator password. Approve it.

```sh
sudo launchctl print system/io.goodkind.smcfanhelper
```

Expect `state = running`. Exit status 113 means the service was not found, so
registration did not happen.

**Confirm the app advances.** The setup screen gives way to the dashboard, showing live
temperature and fan speed. Stale or absent telemetry means the app is not reaching the
agent, even though both services registered.

## Verify fan control

Set a curve that demands a fan speed well above idle, enable fan control, then load the
processor:

```sh
yes > /dev/null & yes > /dev/null &
```

Watch the dashboard. Fan Now climbs toward Thermal Demand within a few seconds, and the
fans become audible. Stop the load with `kill %1 %2` and confirm the fans settle.

Cross-check the app's reading against the hardware:

```sh
sudo powermetrics --samplers smc -n 1 -i 1000 | grep -i fan
```

Quit the app. The fans must return to automatic control rather than staying pinned where
you left them.

## Verify recovery

These paths fail quietly, and a person catches them faster than a test does.

**Kill the agent.**

```sh
pkill -f FanCurveAgent
```

The dashboard reports telemetry as unavailable, then recovers once launchd restarts the
agent. It must not keep showing stale values as current, and it must not need a relaunch.

**Kill the helper.**

```sh
sudo pkill -f io.goodkind.smcfanhelper
```

The agent reconnects on its own.

**Sleep and wake the machine.** Fan control resumes without intervention.

**Quit and relaunch the app.** It opens straight to the dashboard, with no setup screen
and no second approval.

## Diagnose a failure

Read the app's logs first. Every component logs under one subsystem:

```sh
log show --last 10m --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Follow it live while reproducing a failure:

```sh
log stream --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Each line names what the code decided to do. For example,
`agent_client.connection.disconnected reason=invalidated recovery=schedule-reconnect`
says the connection dropped and a reconnect is scheduled. The `recovery=` value is
usually the fastest way to find where behavior diverged.

When a service will not register, check whether macOS is holding it for approval:

```sh
sfltool dumpbtm | grep -A5 -i fancurve
```

Items awaiting approval appear with a disposition showing they are disabled. Approving in
System Settings fixes it. Deleting and re-registering usually does not, because the
Background Task Management database keeps the old record until overnight maintenance runs.

## Get a clean machine

Setup happens once per machine. A machine that already approved Fan Curve cannot test the
approval flow again without a reset.

**A new user account** costs the least and covers the login item. The privileged helper
is system-wide and stays registered, so that half goes untested.

**A virtual machine** gives a genuinely clean system. [Tart](https://tart.run) works:

```sh
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest fan-curve-check
tart run fan-curve-check
```

Transfer the signed app as described above. Use `tart ip fan-curve-check` for the
address. Guests log in as `admin` with password `admin`.

A signed Developer ID build runs in a stock guest with code signing fully enforced. Do not
disable System Integrity Protection, and do not set `amfi_get_out_of_my_way=1`. Disabling
Apple Mobile File Integrity turns off the signature and entitlement checking that this
guide exists to exercise. Verified 2026-07-29 on a `macos-tahoe-base` guest running macOS
26.5, with `boot-args` empty.

Enable developer tools before driving the interface in a guest, or macOS refuses the
automation:

```sh
sudo DevToolsSecurity -enable
sudo dseditgroup -o edit -a "$USER" -t user _developer
```

**A spare Mac** is the highest-fidelity option and the only one with real fans. A virtual
machine covers setup, approval, and reconnect behavior. It cannot verify that a curve
moves a fan.

## Restore the machine

Undo the install if you tested on a machine you use. Quit the app, confirm the fans
returned to automatic, and remove the login item under General, Login Items and
Extensions. Then remove the privileged helper:

```sh
sudo launchctl bootout system/io.goodkind.smcfanhelper
```

Delete a disposable virtual machine rather than keeping it. The next validation then
starts from a base image instead of whatever the last run left behind.

```sh
tart delete fan-curve-check
```
