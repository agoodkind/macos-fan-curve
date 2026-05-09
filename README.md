<p align="center">
  <img src="Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="128" height="128" alt="FanCurve app icon">
</p>

<h1 align="center">FanCurve</h1>

<p align="center">
  Quiet fan control for Apple Silicon Macs.
</p>

<p align="center">
  <a href="https://github.com/agoodkind/macos-fan-curve/releases">Download</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

Apple Silicon Macs are quiet at idle but the firmware fan control is blunt. Under sustained load, fans spin up fast and stay loud well past the thermal peak, and macOS gives you no way to tune that behavior.

FanCurve is a SwiftUI app powered by [macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) that lets you draw a custom temperature-to-fan-speed curve and apply it continuously in the background.

![FanCurve main window](Docs/Screenshots/fancurve-main.png)

## What You Can Do

### Shape the fan response

The main window shows a curve with temperature on the X axis and fan speed on the Y axis. You drag the control points to define exactly how the fans should respond at every temperature. A typical setup keeps them off during light work, brings them up gradually as things warm up, and only runs them hard when the chip is actually under pressure.

### See what is happening right now

While the app is open, two live markers sit on the curve so you can watch the controller work. One tracks the fan's current speed and the other tracks what the controller is currently targeting. When the two are far apart, the controller is holding the fan back to avoid a jarring speed change.

### Keep fans from lurching

The controller applies smoothing to every speed change in both directions, so a short burst of load does not cause a sudden spin-up and the fans do not drop abruptly the moment it is over. The result is a machine that responds to heat without the constant audible surging that makes the stock firmware annoying.

## Download

Get the latest signed and notarized DMG from [GitHub Releases](https://github.com/agoodkind/macos-fan-curve/releases).

Requires macOS 13 or later on Apple Silicon hardware.

## Build From Source

FanCurve uses [Tuist](https://tuist.dev) to generate the Xcode workspace. Use the Makefile rather than running `tuist` or `xcodebuild` directly.

```sh
make install-dependencies
make build
make run
```

Other useful targets:

| Command | What it does |
|---|---|
| `make generate-project` | Regenerates `FanCurveApp.xcworkspace` |
| `make open-project` | Regenerates and opens the workspace in Xcode |
| `make app` | Builds and stages `Products/FanCurve.app` |
| `make dmg` | Builds `Products/FanCurve-Release.dmg` |
| `make test` | Runs the model test suite |
| `make lint` | Runs SwiftLint and logging audits |
| `make verify` | Runs guard checks and tests |

## Project Layout

```
Sources/
  App/        SwiftUI app entry point and window scaffolding
  Agent/      Background login item that polls sensors and writes fan commands
  Views/      Curve editor, sensor dashboard, and settings views
  Models/     Fan curve, interpolation, command mapping, and presets
  Services/   XPC client, sensor polling, and shared config
  Common/     Logging, constants, and shared utilities
Tests/ModelTests/      Model-level unit tests
Scripts/               Build, audit, icon generation, and signing utilities
Templates/             Generated plist templates
deploy/appcast-worker/ Cloudflare worker that serves the Sparkle update feed
```

## Contributing

Bug reports and pull requests are welcome. Run `make verify` before opening a PR. If your change touches the fan control loop, read `AGENTS.md` first. It documents the runtime semantics that must be preserved.

### Sharing thermal profiles

FanCurve can learn a curve from your current system by observing how the firmware responds to load across the temperature range. After the sampling run completes, clicking "Share Results" opens a pre-filled GitHub issue with your machine model, macOS version, temperature range, and the full curve data. You do not need to copy anything manually.

Submissions are useful because Apple Silicon variants behave differently enough that a curve tuned on one chip is often a poor starting point on another. The goal is a library of community-sourced presets so new installs start from something sensible for the hardware they are running on.

## License

[MIT](LICENSE)
