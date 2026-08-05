# Validate Fan Curve on a Mac

Confirm a build works by installing it on a Mac and using it. This covers what automated
tests cannot reach: Service Management registration, launchd, approval prompts in System
Settings, and the fans themselves.

Follow this guide before shipping a release. Follow it again after changing setup, the
background agent, the privileged helper, or the connections between them.

## Gather what you need

**A Mac with fans.** Apple silicon laptops and desktops have them. Confirm with
`powermetrics --samplers smc`, which prints a fan speed.

**A signing identity.** Run `security find-identity -v -p codesigning`. The output must
list a `Developer ID Application` certificate. Without one, the app cannot register a
login item or a privileged helper. Every setup step below then fails for that reason
rather than a real one.

**A Mac that has never run Fan Curve.** Setup, approval prompts, and Service Management
registration happen once per machine. A machine that already approved them skips the steps
most worth testing.

## Get a clean machine

Choose one of three, in increasing fidelity.

**A new user account** costs the least time and covers the login item. The privileged
helper is system-wide and stays registered, so that half goes untested.

**A virtual machine** gives a clean system. [Tart](https://tart.run) works:

```sh
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest fan-curve-check
tart run fan-curve-check
```

Guests log in as `admin` with password `admin`. Run `tart ip fan-curve-check` for the
address, then transfer the signed app as described under Install the app.

A signed Developer ID build runs in a stock guest with code signing fully enforced. Do not
disable System Integrity Protection, and do not set `amfi_get_out_of_my_way=1`. Disabling
Apple Mobile File Integrity turns off the signature and entitlement checking this guide
exercises. Verified 2026-07-29 on a `macos-tahoe-base` guest running macOS 26.5, with
`boot-args` empty.

Driving the interface in a guest needs developer tools enabled first, or macOS refuses the
automation:

```sh
sudo DevToolsSecurity -enable
sudo dseditgroup -o edit -a "$USER" -t user _developer
```

**A spare Mac** is the only option with real fans. A virtual machine covers setup,
approval, and reconnect behavior. It cannot verify that a curve moves a fan.

## Build the app

Build on the Mac that holds the signing identity. Entitlements are authorized per machine,
so a build produced elsewhere cannot be signed correctly.

```sh
make app
```

This produces `Products/Fan Curve.app`, signed and staged. Verify the signature before
continuing:

```sh
codesign -dv --verbose=2 "Products/Fan Curve.app"
codesign -v --verbose=2 --strict "Products/Fan Curve.app"
```

The output must contain:

- `Authority=Developer ID Application: <your name> (<TEAM>)`
- `flags=0x10000(runtime)`, the hardened runtime
- a `Timestamp=` line
- `satisfies its Designated Requirement`

A missing team identifier means the build did not sign. Stop and fix that first.

Run `spctl -a -t exec` and expect `rejected: Unnotarized Developer ID` for a local build.
Notarization matters for distribution, not for this guide.

## Install the app

Install to `/Applications/Fan Curve.app`. The login item and the privileged helper both
register from that exact path. Running the app from anywhere else registers a path macOS
cannot find later.

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

Launch the app from `/Applications`. On a machine that has never run it, expect the
Background Agent setup screen rather than the dashboard.

**Enable the Background Agent.** The app registers a login item. macOS either shows an
approval prompt or places the item in System Settings under General, Login Items and
Extensions. Approve it there.

```sh
launchctl print gui/$(id -u)/io.goodkind.fancurveagent
```

Expect `state = running` and a `program` path inside `/Applications/Fan Curve.app`. A path
pointing elsewhere means the app was launched from a copy. That registration is wrong.

**Install the System Helper.** The app asks the agent to register a privileged daemon, so
macOS prompts for an administrator password. Approve it.

```sh
sudo launchctl print system/io.goodkind.smcfanhelper
```

Expect `state = running`. Exit status 113 means the service was not found, so registration
did not happen.

**Confirm the app advances.** The setup screen gives way to the dashboard, showing live
temperature and fan speed. Stale or absent telemetry means the app is not reaching the
agent, even though both services registered.

## Verify fan control

1. Set a curve that demands a fan speed well above idle.
2. Enable fan control.
3. Load the processor:

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

These paths fail quietly.

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

**Quit and relaunch the app.** It opens straight to the dashboard, with no setup screen and
no second approval.

## Validate a Sparkle helper upgrade in Tart

Perform every step in this section by hand. The repository provides no Tart
runner, guest script, test target, or artifact manifest for this procedure.

Run every Make, build, package, signing, and appcast command on the host. The
Tart guest receives completed artifacts only. Do not install Xcode or copy
repository source into the guest. Do not run Make, a compiler, a package tool,
or an appcast tool in the guest.

Keep apps, archives, certificates, logs, screenshots, and other evidence
outside version control.

### Prepare the host and guest

Run these commands on the host. Replace `<candidate-commit>` with the full
candidate commit. Set `SPARKLE_PRIVATE_KEY_FILE` to the release key file without
printing its contents.

```sh
export TART_HOME="/Volumes/Chaos Storage/ict-vm-tmp-68974"
SOURCE_REPOSITORY="/Users/agoodkind/Sites/macos-fan-curve"
CANDIDATE_COMMIT="<candidate-commit>"
SPARKLE_PRIVATE_KEY_FILE="<release-environment-key-file>"
VM_NAME="fan-curve-helper-upgrade-$(date +%Y%m%d%H%M%S)"
VALIDATION_ROOT="$(mktemp -d \
  "${TMPDIR%/}/fancurve-sparkle.XXXXXX")"
OLD_WORKTREE="$VALIDATION_ROOT/old"
CANDIDATE_WORKTREE="$VALIDATION_ROOT/candidate"
CERTIFICATE_DIRECTORY="$VALIDATION_ROOT/certificates"
FEED_DIRECTORY="$VALIDATION_ROOT/feed"
TRANSFER_DIRECTORY="$VALIDATION_ROOT/transfer"
EVIDENCE_DIRECTORY="/Volumes/Chaos Storage/fan-curve-validation/\
$VM_NAME"
mkdir -p \
  "$CERTIFICATE_DIRECTORY" \
  "$FEED_DIRECTORY" \
  "$TRANSFER_DIRECTORY" \
  "$EVIDENCE_DIRECTORY"
```

Fetch the tags before resolving the old release. The old release must resolve
to the recorded signed commit.

```sh
git -C "$SOURCE_REPOSITORY" fetch --prune --tags origin
OLD_COMMIT="$(git -C "$SOURCE_REPOSITORY" \
  rev-parse '26.8.4-r1^{commit}')"
test "$OLD_COMMIT" = \
  "525b5d1885a7b836e384a179845dec361df4681b" || exit 1
git -C "$SOURCE_REPOSITORY" cat-file -e "$CANDIDATE_COMMIT^{commit}"
git -C "$SOURCE_REPOSITORY" worktree add --detach "$OLD_WORKTREE" 26.8.4-r1
git -C "$SOURCE_REPOSITORY" worktree add --detach \
  "$CANDIDATE_WORKTREE" "$CANDIDATE_COMMIT"
```

Clone the cached non-Xcode image. Run `tart run` in its own host terminal. Leave
that terminal open.

```sh
tart clone macos-tahoe-base "$VM_NAME"
tart run "$VM_NAME"
```

Read the guest address on the host. In the guest Terminal, run the route command.
Copy the displayed gateway into `HOST_ADDRESS` on the host.

```sh
GUEST_ADDRESS="$(tart ip "$VM_NAME")"
printf 'Guest address: %s\n' "$GUEST_ADDRESS"
```

```sh
route -n get default | awk '/gateway:/{print $2}'
```

```sh
HOST_ADDRESS="<gateway-shown-in-the-guest>"
FEED_URL="https://$HOST_ADDRESS:8443/appcast.xml"
```

Generate a one-day root certificate and server certificate on the host. The server
certificate covers the host address seen from the guest.

```sh
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
  -keyout "$CERTIFICATE_DIRECTORY/root-key.pem" \
  -out "$CERTIFICATE_DIRECTORY/root-cert.pem" \
  -subj "/CN=Fan Curve Tart Validation Root" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
/usr/bin/openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -keyout "$CERTIFICATE_DIRECTORY/server-key.pem" \
  -out "$CERTIFICATE_DIRECTORY/server.csr" \
  -subj "/CN=$HOST_ADDRESS"
printf '%s\n' \
  '[server]' \
  "subjectAltName=IP:$HOST_ADDRESS" \
  'extendedKeyUsage=serverAuth' \
  'keyUsage=digitalSignature,keyEncipherment' \
  > "$CERTIFICATE_DIRECTORY/server.ext"
/usr/bin/openssl x509 -req -sha256 -days 1 \
  -in "$CERTIFICATE_DIRECTORY/server.csr" \
  -CA "$CERTIFICATE_DIRECTORY/root-cert.pem" \
  -CAkey "$CERTIFICATE_DIRECTORY/root-key.pem" \
  -CAcreateserial \
  -extfile "$CERTIFICATE_DIRECTORY/server.ext" \
  -extensions server \
  -out "$CERTIFICATE_DIRECTORY/server-cert.pem"
/usr/bin/openssl verify -CAfile "$CERTIFICATE_DIRECTORY/root-cert.pem" \
  "$CERTIFICATE_DIRECTORY/server-cert.pem"
/usr/bin/openssl x509 -in "$CERTIFICATE_DIRECTORY/server-cert.pem" \
  -text -noout | grep -F "IP Address:$HOST_ADDRESS"
```

Delete stale build products through the canonical host target. Build the old
signed app with the temporary feed. Build and package the candidate on the host.

```sh
make -C "$OLD_WORKTREE" clean
make -C "$CANDIDATE_WORKTREE" clean
make -C "$OLD_WORKTREE" app \
  MARKETING_VERSION=26.8.4 \
  CURRENT_PROJECT_VERSION=202608040448000001 \
  SPARKLE_FEED_URL="$FEED_URL"
make -C "$CANDIDATE_WORKTREE" release-assets \
  ARTIFACT_VERSION=26.8.5 \
  MARKETING_VERSION=26.8.5 \
  CURRENT_PROJECT_VERSION=202608040448000002 \
  SPARKLE_FEED_URL="$FEED_URL"
```

Prepare the signed candidate appcast on the host with the existing Make target.

```sh
SPARKLE_PRIVATE_KEY_FILE="$SPARKLE_PRIVATE_KEY_FILE" \
  make -C "$CANDIDATE_WORKTREE" prepare-sparkle-updates \
  ARTIFACT_VERSION=26.8.5 \
  MARKETING_VERSION=26.8.5 \
  CURRENT_PROJECT_VERSION=202608040448000002 \
  RELEASE_TAG=26.8.5 \
  SPARKLE_FEED_URL="$FEED_URL"
```

Copy the completed candidate feed outside the worktree. Record the archive hash
before editing the appcast.

```sh
cp "$CANDIDATE_WORKTREE/build/sparkle-updates/appcast.xml" \
  "$FEED_DIRECTORY/appcast.xml"
cp "$CANDIDATE_WORKTREE/Products/FanCurve-26.8.5.dmg" \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg"
CANDIDATE_DMG_HASH="$(shasum -a 256 \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg" | awk '{print $1}')"
CANDIDATE_DMG_LENGTH="$(stat -f '%z' \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg")"
```

The Make target emits a GitHub enclosure URL. Replace only that URL with the
temporary host feed URL. This manual edit does not change the archive signature.

```sh
PUBLISHED_ENCLOSURE_URL="https://github.com/agoodkind/\
macos-fan-curve/releases/download/26.8.5/FanCurve-26.8.5.dmg"
LOCAL_ENCLOSURE_URL="https://$HOST_ADDRESS:8443/\
FanCurve-26.8.5.dmg"
sed -i '' \
  "s|$PUBLISHED_ENCLOSURE_URL|$LOCAL_ENCLOSURE_URL|" \
  "$FEED_DIRECTORY/appcast.xml"
LOCAL_URL_COUNT="$(grep -cF \
  "$LOCAL_ENCLOSURE_URL" "$FEED_DIRECTORY/appcast.xml")"
test "$LOCAL_URL_COUNT" -eq 1 || exit 1
if grep -F \
  "$PUBLISHED_ENCLOSURE_URL" "$FEED_DIRECTORY/appcast.xml"; then
    exit 1
fi
test "$CANDIDATE_DMG_HASH" = "$(shasum -a 256 \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg" | awk '{print $1}')" || exit 1
APPCAST_SHORT_VERSION="$(xmllint --xpath \
  'string(//*[local-name()="shortVersionString"])' \
  "$FEED_DIRECTORY/appcast.xml")"
APPCAST_BUILD="$(xmllint --xpath \
  'string(//*[local-name()="version"])' \
  "$FEED_DIRECTORY/appcast.xml")"
APPCAST_LENGTH="$(xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@length)' \
  "$FEED_DIRECTORY/appcast.xml")"
test "$APPCAST_SHORT_VERSION" = "26.8.5" || exit 1
test "$APPCAST_BUILD" = "202608040448000002" || exit 1
test "$APPCAST_LENGTH" = "$CANDIDATE_DMG_LENGTH" || exit 1
printf '%s\n' \
  "short-version=$APPCAST_SHORT_VERSION" \
  "build=$APPCAST_BUILD" \
  "length=$APPCAST_LENGTH" \
  "url=$LOCAL_ENCLOSURE_URL" \
  "archive-sha256=$CANDIDATE_DMG_HASH" \
  'metadata-check=passed' \
  > "$EVIDENCE_DIRECTORY/appcast-validation.txt"
```

Recalculate the candidate EdDSA signature with Sparkle's host tool. Compare it
with the signature retained in the rewritten appcast.

```sh
SPARKLE_SIGN_UPDATE="$("$CANDIDATE_WORKTREE/Scripts/FindSparkleTool.swift" \
  "$CANDIDATE_WORKTREE/build" sign_update)"
EXPECTED_ED_SIGNATURE="$("$SPARKLE_SIGN_UPDATE" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg" | \
  sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
APPCAST_ED_SIGNATURE="$(xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' \
  "$FEED_DIRECTORY/appcast.xml")"
test -n "$EXPECTED_ED_SIGNATURE" || exit 1
test "$EXPECTED_ED_SIGNATURE" = "$APPCAST_ED_SIGNATURE" || exit 1
printf '%s\n' \
  "expected-ed-signature=$EXPECTED_ED_SIGNATURE" \
  "appcast-ed-signature=$APPCAST_ED_SIGNATURE" \
  'ed-signature-check=passed' \
  >> "$EVIDENCE_DIRECTORY/appcast-validation.txt"
cp "$FEED_DIRECTORY/appcast.xml" \
  "$EVIDENCE_DIRECTORY/final-appcast.xml"
```

Verify both app bundles, the packaged candidate, and their embedded executables
on the host. Preserve this output in the evidence directory.

```sh
OLD_APP="$OLD_WORKTREE/Products/Fan Curve.app"
CANDIDATE_APP="$CANDIDATE_WORKTREE/Products/Fan Curve.app"
OLD_AGENT="$OLD_APP/Contents/MacOS/FanCurveAgent"
CANDIDATE_AGENT="$CANDIDATE_APP/Contents/MacOS/FanCurveAgent"
OLD_HELPER="$OLD_APP/Contents/MacOS/io.goodkind.smcfanhelper"
CANDIDATE_HELPER="$CANDIDATE_APP/Contents/MacOS/io.goodkind.smcfanhelper"
HOST_CODESIGN_RESULTS="$EVIDENCE_DIRECTORY/host-codesign-verification.txt"
: > "$HOST_CODESIGN_RESULTS"
codesign --verify --deep --strict --verbose=4 "$OLD_APP" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --deep --strict --verbose=4 "$CANDIDATE_APP" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --strict --verbose=4 "$OLD_AGENT" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --strict --verbose=4 "$CANDIDATE_AGENT" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --strict --verbose=4 "$OLD_HELPER" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --strict --verbose=4 "$CANDIDATE_HELPER" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
codesign --verify --verbose=4 \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg" \
  >> "$HOST_CODESIGN_RESULTS" 2>&1 || exit 1
printf '%s\n' 'codesign-verification=passed' >> "$HOST_CODESIGN_RESULTS"
OLD_APP_VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$OLD_APP/Contents/Info.plist")"
OLD_APP_BUILD="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' "$OLD_APP/Contents/Info.plist")"
CANDIDATE_APP_VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$CANDIDATE_APP/Contents/Info.plist")"
CANDIDATE_APP_BUILD="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' "$CANDIDATE_APP/Contents/Info.plist")"
test "$OLD_APP_VERSION" = "26.8.4" || exit 1
test "$OLD_APP_BUILD" = "202608040448000001" || exit 1
test "$CANDIDATE_APP_VERSION" = "26.8.5" || exit 1
test "$CANDIDATE_APP_BUILD" = "202608040448000002" || exit 1
printf '%s\n' \
  "old-app-version=$OLD_APP_VERSION" \
  "old-app-build=$OLD_APP_BUILD" \
  'old-helper-version=1.0' \
  'old-helper-build=1' \
  "candidate-app-version=$CANDIDATE_APP_VERSION" \
  "candidate-app-build=$CANDIDATE_APP_BUILD" \
  'candidate-helper-version=26.8.5' \
  'candidate-helper-build=202608040448000002' \
  'version-check=passed' \
  > "$EVIDENCE_DIRECTORY/host-build-identities.txt"
shasum -a 256 \
  "$OLD_APP/Contents/MacOS/FanCurve" "$OLD_AGENT" "$OLD_HELPER" | \
  tee "$EVIDENCE_DIRECTORY/old-host-executable-hashes.txt"
shasum -a 256 \
  "$CANDIDATE_APP/Contents/MacOS/FanCurve" "$CANDIDATE_AGENT" "$CANDIDATE_HELPER" | \
  tee "$EVIDENCE_DIRECTORY/candidate-host-executable-hashes.txt"
codesign -dvvv "$OLD_APP" "$OLD_AGENT" "$OLD_HELPER" 2>&1 | \
  tee "$EVIDENCE_DIRECTORY/old-signatures.txt"
codesign -dvvv \
  "$CANDIDATE_APP" "$CANDIDATE_AGENT" "$CANDIDATE_HELPER" 2>&1 | \
  tee "$EVIDENCE_DIRECTORY/candidate-signatures.txt"
xcrun otool -P "$OLD_AGENT" | \
  tee "$EVIDENCE_DIRECTORY/old-agent-info-plist.txt"
xcrun otool -P "$OLD_HELPER" | \
  tee "$EVIDENCE_DIRECTORY/old-helper-info-plist.txt"
xcrun otool -P "$CANDIDATE_AGENT" | \
  tee "$EVIDENCE_DIRECTORY/candidate-agent-info-plist.txt"
xcrun otool -P "$CANDIDATE_HELPER" | \
  tee "$EVIDENCE_DIRECTORY/candidate-helper-info-plist.txt"
shasum -a 256 "$FEED_DIRECTORY/appcast.xml" \
  "$FEED_DIRECTORY/FanCurve-26.8.5.dmg" | \
  tee "$EVIDENCE_DIRECTORY/feed-hashes.txt"
```

Archive the old app on the host. Copy only the root certificate and completed
archive to the guest. Compare the host and guest SHA-256 hashes before
extraction.

```sh
ditto -c -k --sequesterRsrc --keepParent "$OLD_APP" \
  "$TRANSFER_DIRECTORY/FanCurve-26.8.4.zip"
OLD_ARCHIVE_HASH="$(shasum -a 256 \
  "$TRANSFER_DIRECTORY/FanCurve-26.8.4.zip" | awk '{print $1}')"
scp "$CERTIFICATE_DIRECTORY/root-cert.pem" \
  "$TRANSFER_DIRECTORY/FanCurve-26.8.4.zip" \
  "admin@$GUEST_ADDRESS:~/"
GUEST_ARCHIVE_HASH="$(
  ssh "admin@$GUEST_ADDRESS" \
    'shasum -a 256 ~/FanCurve-26.8.4.zip' | awk '{print $1}'
)"
test "$OLD_ARCHIVE_HASH" = "$GUEST_ARCHIVE_HASH" || exit 1
```

### Install and record the old release

Run these commands in the guest Terminal. Install the temporary root only in this
disposable guest. Verify the installed signature before launch. The feed remains
stopped so Sparkle cannot offer the candidate before you capture the old state.

```sh
INSTALLED_APP="/Applications/Fan Curve.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/FanCurve"
INSTALLED_AGENT="$INSTALLED_APP/Contents/MacOS/FanCurveAgent"
INSTALLED_HELPER="$INSTALLED_APP/Contents/MacOS/io.goodkind.smcfanhelper"
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/root-cert.pem
sudo ditto -x -k ~/FanCurve-26.8.4.zip /Applications/
codesign --verify --deep --strict --verbose=4 "$INSTALLED_APP"
open "$INSTALLED_APP"
```

Approve the Background Agent and System Helper in System Settings. Wait until
General Settings shows `Running`.

Open About. Record the old app version and the `FanCurve` and `FanCurveAgent`
hashes. This old release cannot report active helper identity. The host metadata
records its embedded System Helper version as `1.0` with build `1`. The guest
hashes prove which signed host binaries are active.

Run these inspection commands in the guest. Save the output outside the repository.

```sh
mkdir -p ~/fan-curve-validation-evidence
launchctl print gui/$(id -u)/io.goodkind.fancurveagent | \
  tee ~/fan-curve-validation-evidence/old-agent-launchd.txt
sudo launchctl print system/io.goodkind.smcfanhelper | \
  tee ~/fan-curve-validation-evidence/old-helper-launchd.txt
pgrep -x FanCurve | tee ~/fan-curve-validation-evidence/old-app-pid.txt
pgrep -x FanCurveAgent | tee ~/fan-curve-validation-evidence/old-agent-pid.txt
pgrep -x io.goodkind.smcfanhelper | \
  tee ~/fan-curve-validation-evidence/old-helper-pid.txt
shasum -a 256 \
  "$INSTALLED_BINARY" "$INSTALLED_AGENT" "$INSTALLED_HELPER" | \
  tee ~/fan-curve-validation-evidence/old-installed-hashes.txt
codesign -dvvv \
  "$INSTALLED_APP" "$INSTALLED_AGENT" "$INSTALLED_HELPER" 2>&1 | \
  tee ~/fan-curve-validation-evidence/old-installed-signatures.txt
screencapture -i ~/fan-curve-validation-evidence/old-about.png
screencapture -i ~/fan-curve-validation-evidence/old-general-settings.png
```

Compare the three guest hashes with the old host hashes. Confirm the Agent launchd
program is inside `/Applications/Fan Curve.app`.

### Upgrade without manual repair

Start the temporary signed feed in a dedicated host terminal from the feed
directory. Leave this command running through the update.

```sh
cd "$FEED_DIRECTORY"
/usr/bin/openssl s_server -accept 8443 \
  -cert "$CERTIFICATE_DIRECTORY/server-cert.pem" \
  -key "$CERTIFICATE_DIRECTORY/server-key.pem" \
  -WWW
```

In the guest Terminal, verify the feed before opening Sparkle. Replace
`<host-address>` with the gateway recorded earlier.

```sh
curl --fail --show-error "https://<host-address>:8443/appcast.xml"
```

Open About in the guest and click `Check Now`. Use Sparkle to install the
candidate. Let Sparkle relaunch Fan Curve. Do not click
`Reinstall System Helper` during this upgrade.

Wait until General Settings shows `Running`. Open About and confirm these values:

- Version is `26.8.5`.
- System Helper is `26.8.5 (build 202608040448000002)`.
- System Helper Hash equals the full candidate helper hash recorded on the host.
- The displayed `FanCurve` and `FanCurveAgent` hashes match the candidate host
  binaries.

Run these commands in the guest and preserve the output:

```sh
launchctl print gui/$(id -u)/io.goodkind.fancurveagent | \
  tee ~/fan-curve-validation-evidence/candidate-agent-launchd.txt
sudo launchctl print system/io.goodkind.smcfanhelper | \
  tee ~/fan-curve-validation-evidence/candidate-helper-launchd.txt
pgrep -x FanCurve | tee ~/fan-curve-validation-evidence/candidate-app-pid.txt
pgrep -x FanCurveAgent | tee ~/fan-curve-validation-evidence/candidate-agent-pid.txt
pgrep -x io.goodkind.smcfanhelper | \
  tee ~/fan-curve-validation-evidence/candidate-helper-pid.txt
shasum -a 256 \
  "$INSTALLED_BINARY" "$INSTALLED_AGENT" "$INSTALLED_HELPER" | \
  tee ~/fan-curve-validation-evidence/candidate-installed-hashes.txt
codesign --verify --deep --strict --verbose=4 "$INSTALLED_APP"
codesign -dvvv \
  "$INSTALLED_APP" "$INSTALLED_AGENT" "$INSTALLED_HELPER" 2>&1 | \
  tee ~/fan-curve-validation-evidence/candidate-installed-signatures.txt
screencapture -i ~/fan-curve-validation-evidence/candidate-about.png
screencapture -i ~/fan-curve-validation-evidence/candidate-general-settings.png
```

Compare the three guest hashes with the candidate host hashes. Confirm the Agent
launchd program still points inside `/Applications/Fan Curve.app`. Confirm the
app, Agent, and helper process identifiers changed from the old release.

Click `Reinstall System Helper` once on the healthy candidate. The busy state
must end at `Running`. About must retain the candidate System Helper version and
full hash.

Capture the final state and logs in the guest:

```sh
sudo launchctl print system/io.goodkind.smcfanhelper | \
  tee ~/fan-curve-validation-evidence/reinstalled-helper-launchd.txt
shasum -a 256 \
  "$INSTALLED_HELPER" | \
  tee ~/fan-curve-validation-evidence/reinstalled-helper-hash.txt
log show --last 30m \
  --predicate 'subsystem == "io.goodkind.fan"' \
  --style compact \
  > ~/fan-curve-validation-evidence/unified.log
screencapture -i ~/fan-curve-validation-evidence/reinstalled-about.png
screencapture -i ~/fan-curve-validation-evidence/reinstalled-general-settings.png
```

Record each check as passed or failed. Stop on any failed signature, hash, identity,
process, launchd, update, or visible-state check. Do not define a repository artifact
format for this evidence.

### Preserve evidence and clean up

Copy the guest evidence to the external evidence directory from the host. Keep command
output from the host alongside it. Do not copy a private key into evidence.

```sh
scp -r "admin@$GUEST_ADDRESS:~/fan-curve-validation-evidence" \
  "$EVIDENCE_DIRECTORY/guest"
```

Stop the feed server. Confirm the printed virtual machine name identifies only the
disposable clone, then stop and delete it from the host.

```sh
printf 'Disposable virtual machine: %s\n' "$VM_NAME"
tart stop "$VM_NAME"
tart delete "$VM_NAME"
```

Remove both temporary worktrees through Git. Delete `VALIDATION_ROOT` only after
the external evidence copy is complete. This removes the temporary
certificates, private keys, feed files, and transfer archive.

```zsh
git -C "$SOURCE_REPOSITORY" worktree remove "$OLD_WORKTREE"
git -C "$SOURCE_REPOSITORY" worktree remove "$CANDIDATE_WORKTREE"
git -C "$SOURCE_REPOSITORY" worktree prune
if [[ "$VALIDATION_ROOT" != "${TMPDIR%/}"/fancurve-sparkle.* ]]; then
  printf 'Refusing unexpected cleanup path: %s\n' "$VALIDATION_ROOT" >&2
  exit 1
fi
rm -rf -- "$VALIDATION_ROOT"
```

## Diagnose a failure

Read the app's logs first. Every component logs under one subsystem:

```sh
log show --last 10m --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Follow it live while reproducing a failure:

```sh
log stream --predicate 'subsystem == "io.goodkind.fan"' --style compact
```

Each line ends with the action the code took. For example,
`agent_client.connection.disconnected reason=invalidated recovery=schedule-reconnect` says
the connection dropped and a reconnect is scheduled. Compare the `recovery=` value against
what you expected to happen.

When a service will not register, check whether macOS is holding it for approval:

```sh
sfltool dumpbtm | grep -A5 -i fancurve
```

An entry that appears here but is disabled is awaiting approval. Approve it in System
Settings. Deleting and re-registering does not clear it, because the Background Task
Management database keeps the old record until overnight maintenance runs.

## Restore the machine

Undo the install if you tested on a machine you use. Quit the app, confirm the fans
returned to automatic, and remove the login item under General, Login Items and Extensions.
Removing the privileged helper needs an administrator password:

```sh
sudo launchctl bootout system/io.goodkind.smcfanhelper
```

Delete a disposable virtual machine rather than keeping it. The next validation then starts
from a base image instead of whatever the last run left behind.

```sh
tart delete fan-curve-check
```
