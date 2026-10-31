# Development

## Toolchain

- Xcode 26.1 or newer with an iOS 26.1+ simulator runtime.
- XcodeGen (`brew install xcodegen`).
- Python 3.10+ for the repository guard and fake-server tests; no pip packages needed.
- No car, server, signing credentials or Swift packages are required for the simulator demo.

`project.yml` is the source of truth. Run `xcodegen generate` after changing target settings. The generated `.xcodeproj` is checked in so the project can also be opened directly.

## Build

```bash
./scripts/build.sh
SIMULATOR_NAME="iPhone 17" ./scripts/build.sh
```

The helper regenerates the project and preserves the build's exit status. Simulator signing is disabled. `build/` is ignored.

## Run and capture

In Xcode, select BetterOpel and an iPhone simulator, then run. The app starts with demo data when there is no saved connection.

To capture an already booted simulator:

```bash
./scripts/run.sh light captures/car.png 4 -tab car
./scripts/shot.sh light captures/charge.png 4 -tab charge
./scripts/shot.sh dark captures/climate.png 4 -tab climate -theme petrol
./scripts/record.sh dark captures/demo.mp4 12 -tab charge
```

These helpers explicitly disconnect saved server settings before capture. The screenshot helper normalizes the status bar and clears its override on exit. Captures are ignored by Git. Boot the same simulator named by `SIMULATOR_NAME` when using `run.sh`.

Debug launch options:

| Option | Effect |
| --- | --- |
| `-resetDemo` | Disconnect, then reset the simulated snapshot and departures. |
| `-server none` | Disconnect a saved server. |
| `-tab car\|charge\|climate\|trips` | Select an initial tab. |
| `-theme volt\|copper\|petrol` | Select a complete colourway. |
| `-guide widgets\|shortcuts` | Open the corresponding guide. |
| `-parked` | Start the demo car unplugged, so nothing ticks during a capture. |
| `-climatePhase sending\|waking\|running\|ready` | Hold the climate screen in one state. |
| `-warmUp edit\|new` | Open the ready-by editor directly. |
| `-stale 70` | Age the range reading by 70 minutes. |
| `-autoRefresh 3` | Refresh three seconds after launch. |
| `-refreshDelay 2` | Keep the demo car silent for two seconds on a refresh. |
| `-lensAt 0.4` | Freeze the refresh lens 0.4 s after it starts (add `-lensAnswerAt` or `-lensFailAt` for the endings). |

Network-development arguments are documented with the [optional server](../Server/README.md). Do not use them for public captures.

## Your own physical device

The public source uses `com.example.betteropel`, `com.example.betteropel.widgets` and `group.com.example.betteropel`. For a signed device build, choose your own identifiers and team. Update both targets in `project.yml`, both App Group entries and `SnapshotStore.appGroup` in `Shared/Model/VehicleAPI.swift`, then regenerate the project. Set the signing team locally in Xcode; do not commit it.

Changing identifiers deliberately creates a separate installation; it does not migrate the author's private app data.

## Validation

Before publishing this snapshot:

- Built the app and widget extension locally with Xcode 26.3 for the iPhone 17 Pro / iOS 26.2 simulator, with signing disabled.
- Ran the tracked-file privacy guard and regression tests for its matching rules.
- Ran HTTP integration tests against the loopback fake PSACC server, including charge, climate, lock, history and missing-endpoint responses.
- Replaced non-redistributable Technor binaries with unmodified OFL-licensed Oxanium.
- Checked curated PNG integrity, metadata and visible content. Excluded a truncated dark-mode montage and the connection-settings capture.

The images and clips in `docs/media` were captured from the current build in the iPhone 17 Pro simulator, Volt light unless a colourway is the subject, with `-resetDemo -server none` and, for the refresh and climate takes, `-parked`. That capture build used Technor; the public build ships Oxanium. Siri, VoiceOver and every widget and Control Center configuration have not been audited for this snapshot.

To repeat the repository checks:

```bash
python3 scripts/privacy_check.py
python3 -m unittest discover -s tests -v
```

CI uses an unsigned generic iOS Simulator build on GitHub's [macOS 26 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md). It also runs the privacy and Python tests. CI is a compile and fixture check, not a device UI test suite.
