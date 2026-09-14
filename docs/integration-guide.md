# Installation and native builds

Use Godot 4.7.2 and matching templates. Android players require API 24+, Gradle exports and a 64-bit ABI (arm64-v8a or x86_64). iOS requires 15+, Xcode and signing for devices. Use Compatibility rendering for the Lab's simulator path.

## Customer addon

Extract the prepared ZIP into the game root, enable Nuxie under Project Settings → Plugins, and select the NuxieGodot iOS export plugin. Android uses the local Maven repository included in the addon, plus ordinary transitive dependencies fetched by Gradle. The Godot engine is compile-only for the bridge and is supplied by the export template.

The EditorPlugin owns its autoload registration and stages an iOS descriptor under `ios/plugins/nuxie`. It preserves conflicting user-owned registrations/files. Disabling the plugin removes its unchanged managed iOS descriptor and checksum marker. Native frameworks stay under `addons/nuxie/ios`; the exporter chooses the debug/release Swift framework, and Godot selects the matching singleton adapter. Native callbacks enter a value queue and are drained on the engine thread.

## Source checkout

Requirements: Python 3, Git, JDK 17, Android SDK 36 and the native SDK's pinned NDK, Xcode, SCons, XcodeGen, and Godot 4.7.2. `NATIVE-PINS.json` is the dependency source of truth. The build scripts fetch exact source revisions; no source checkout is silently substituted for a pin.

```sh
python3 scripts/prepare-native.py
python3 scripts/pack.py
```

The first command creates ignored `.native` inputs and builds Android and iOS artifacts. The second creates `dist/nuxie-godot-0.4.0.zip` and copies exactly that staged addon into `examples/sdk-lab/addons`. Prepared binaries are generated artifacts, not hidden uncommitted SDK source. Preserve `.native` for incremental builds. Never pack the repository root as the addon.

The iOS build generates engine headers and compiles separate debug/release singleton adapters with matching DEBUG_ENABLED and threading flags. It packages Nuxie's Swift resource bundle inside each framework. The ZIP includes an artifact checksum manifest. Godot's export preflight checks version and configuration; use the complete native qualification before releasing.

## Local backend

Use a disposable Nuxie development app and public platform keys. The Lab reads ignored `local-settings.json`, or its form saves public settings to `user://settings.json`. Root Nuxie development uses `pnpm run dev:print` and `pnpm run dev`; derive the ingest endpoint from that checkout's resolved ports. Android emulator loopback can reach the host with `adb reverse`; physical devices need an appropriate reachable development origin.

The debug native bridges support a local endpoint without weakening release builds:

- Android: launch the exported launcher Activity with the `NUXIE_GODOT_API_ENDPOINT` string extra. The Lab's standardDebug manifest overlay permits local HTTP.
- iOS: set `NUXIE_GODOT_API_ENDPOINT` in the debug scheme environment or prefix `simctl launch` with `SIMCTL_CHILD_NUXIE_GODOT_API_ENDPOINT`. Configure local-network transport allowance in a development export when needed.

Neither override applies to the release bridge. Store credentials, backend private keys and signing identities are never committed in the Lab. Published native screens may need a development asset origin as well as an API origin; use the backend's published delivery configuration.

## Validation

```sh
python3 scripts/check.py
```

This runs the pinned Godot client tests, Android unit tests/lint/builds, and real iOS simulator bridge tests. `GODOT_BIN` can select an installed copy of the pinned editor. The [Lab guide](../examples/sdk-lab/README.md) and [qualification record](testing-and-validation.md) describe player tests. Passing this command alone does not qualify store purchases or native presentation.

Buildkite runs `bash scripts/ci.sh` on macOS. It installs the manifest's editor version after checking the official SHA-512 checksum, prepares the exact native revisions, packages the addon into the Lab, and runs the same checks above. The iOS test runner selects an available iPhone simulator. CI requires the same native toolchain as a source build.
