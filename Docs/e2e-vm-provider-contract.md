# End-to-end VM provider contract

`Scripts/EndToEndVM.swift` runs the Debug UI suite and the Release service-smoke
suite inside a disposable macOS virtual machine. The runner owns run identifiers,
artifact layout, signal handling, and evidence collection; it holds no
VM-tool-specific logic. A provider script supplies the disposable host: what
today runs against Tart could run against another VM tool, a remote macOS host, or
a CI-managed runner by pointing `E2E_VM_PROVIDER` at a different script that
speaks this same contract.

## Selecting a provider

`make e2e-debug` and `make e2e-release-smoke` read `E2E_VM_PROVIDER` (a path to an
executable) and `E2E_VM_BASE_IMAGE` (an identifier the provider resolves to a
prepared, immutable base image). The Makefile defaults `E2E_VM_PROVIDER` to
`Scripts/vm-providers/tart-provider.sh`, the Tart implementation shipped in this
repository, and `E2E_VM_BASE_IMAGE` to the prepared Tart image name. Overriding
either variable swaps the backing VM tool without touching the runner or the
guest workflow.

## Verbs the runner calls

The runner invokes the provider script as `<provider> <verb> [arguments...]`. Exit
status `0` means success; any other status is a failure, and the provider must
put a human-readable reason on stderr so the runner can log it as evidence.

| Verb | Arguments | Contract |
| --- | --- | --- |
| `require-image` | `<image-id>` | Exit `0` only when the named base image exists and is ready to clone. The runner refuses to continue otherwise, so a missing image never surfaces as a confusing clone failure. |
| `clone` | `<image-id> <instance-name>` | Create a disposable instance from the base image under the given name. The runner has already validated `instance-name` against its disposable-name pattern before this call. |
| `start` | `<instance-name> --source <host-path> --artifacts <host-path>` | Start the instance headless, with the source directory mounted read-only and the artifact directory mounted read-write. This call blocks for the life of the instance; the runner launches it as a tracked background process and stops tracking it once `stop` returns. |
| `mount-path` | `<instance-name> <source\|artifacts>` | Print, on stdout, the absolute guest-side path where the named mount landed. The runner passes this path to the guest workflow so it never assumes a mount convention. |
| `exec` | `<instance-name> -- <command>` | Run `command` inside the guest and forward its exit status, stdout, and stderr. This is the only way the runner talks to the guest: readiness probes and the guest workflow invocation both go through `exec`. Credential handling (SSH user, password, keys, or any other guest login mechanism) is entirely the provider's concern; the runner never sees or forwards a credential. |
| `ready` | `<instance-name>` | A provider-specific extra readiness gate beyond "the guest accepts `exec`" (for Tart, a running guest-agent process). A provider with no such extra concept exits `0` immediately. |
| `address` | `<instance-name>` | Best-effort: print a connection descriptor (an IP, a hostname, or `n/a`) for the run's evidence log. Failure here does not fail the run. |
| `stop` | `<instance-name>` | Stop the instance gracefully. |
| `delete` | `<instance-name>` | Delete the instance. The runner calls this only on an instance name it created and validated as disposable in this run; it never deletes an image or an instance it did not create. |

## What the runner guarantees regardless of provider

- A unique, validated, disposable instance name per run (`clone`/`delete` never
  touch the base image or a name from another run).
- `SIGINT`/`SIGTERM` terminate every tracked child process, exit the run with
  status `130`, and still run cleanup.
- Readiness waits (`exec`-reachable, `ready`, then a logged-in desktop session
  checked over `exec`) instead of a fixed sleep.
- A per-run artifact directory under `build/e2e/<run-id>/` holding host
  environment info, the `start` log, the guest workflow log, `.xcresult`
  bundles, screenshots, unified logs, and code-signing evidence.
- `stop` then `delete` run in the cleanup path unless `E2E_VM_KEEP=1`, in which
  case the instance is left running for inspection.

## What the guest workflow expects

`Scripts/e2e-guest.sh` runs inside the guest through `exec` and only reads
generic environment variables the runner sets on that call:
`FANCURVE_E2E_SOURCE_MOUNT`, `FANCURVE_E2E_ARTIFACT_MOUNT`,
`FANCURVE_E2E_GUEST_WORKSPACE`, `FANCURVE_E2E_RUN_ID`, and, for the Release
smoke mode, `FANCURVE_E2E_RELEASE_APP_SOURCE` and
`FANCURVE_E2E_RELEASE_XCTESTRUN_PATH`. None of these name a VM tool, so the same
guest script runs unmodified under any provider that honors the `mount-path` and
`exec` contract above.

## Tart as the shipped default

`Scripts/vm-providers/tart-provider.sh` implements every verb above with `tart`
and `sshpass`/`ssh`. It requires `E2E_VM_SSH_PASSWORD` from the environment and
refuses to run without it; there is no fallback default. Tart's stock guest
images ship a documented `admin`/`admin` login, so `E2E_VM_SSH_USER` may default
to `admin` when unset (a username is not a secret), but the password must always
come from the caller.
