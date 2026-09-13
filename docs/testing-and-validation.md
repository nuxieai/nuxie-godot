# Qualification record

Qualification date: 2026-09-13. This record separates executed checks from release qualifications that still require a signed device and store account.

| Layer | Configuration | Evidence |
| --- | --- | --- |
| GDScript client | Godot 4.7.2, headless | 33 checks: lifecycle, stale snapshots, detached values, JSON validation, checkout correlation, timeout, paused dispatch and shutdown |
| Android bridge | Pinned native dependency, debug/release AARs | Unit tests, Android lint and both builds pass |
| iOS bridge | Pinned native dependency, iOS simulator | Three native tests pass; device/simulator debug/release frameworks build |
| Android player | Godot 4.7.2 standard templates, emulator | 21 live API checks pass against a local development app |
| iOS player | Godot 4.7.2 source-built ARM64 simulator engine | All 21 checks pass on a clean install; warm startup is blocked below |

The live checks use the public addon and actual native clients: configure, identify, feature readiness, remote entity queries, consumption, retrying the same operation ID, receipt equality, exactly one debit, unchanged second entity, locale override/reset, anonymous identity rotation and reidentification. They do not mock backend grants or purchase outcomes. The Lab writes `user://validation.json` with every assertion.

## Known release blockers

- **iOS warm startup:** a retained authenticated profile can deadlock native Journey recovery before EventLog readiness opens. Configure/identify complete, but native snapshots remain UNKNOWN; clean installation passes. The native-layer dependency cycle is tracked in [UNIV-3158](https://universe.basis.dev/issue/UNIV-3158). Do not erase customer data or fabricate READY to work around it.
- **Native Experience qualification:** local publication failed with `journey-release-signing.config-required`; a supported local signing/trust path is tracked in [UNIV-3157](https://universe.basis.dev/issue/UNIV-3157). Native screen/App Action/external-checkout-under-overlay qualification remains incomplete.

The release-mode Android APK was built with local development signing. All eight native libraries passed 16 KiB ELF LOAD alignment and uncompressed ZIP entry alignment, with one C++ shared runtime per ABI and no iOS framework resources leaked into Android assets. This is not Play Store signing or physical-device evidence.

## Apple Silicon simulator input

The downloaded 4.7.2 standard iOS template's simulator archive contained x86_64 objects only, despite its `ios-arm64_x86_64-simulator` directory name. The installed iOS 26.5 simulator runtime required ARM64. Local validation therefore compiled the unmodified, pinned Godot source:

```sh
cd .native/godot
scons platform=ios arch=arm64 ios_simulator=yes target=template_debug -j8
```

For that local simulator run, replace the generated Xcode project's `NuxieLab.xcframework/ios-arm64_x86_64-simulator/libgodot.a` with `bin/libgodot.ios.template_debug.arm64.simulator.a`, then build ARM64 with signing disabled. Do not describe this as validation of Apple's device signing or the official simulator binary. The device export uses the standard template's ARM64 archive.

## Running checks

From the SDK checkout:

```sh
python3 scripts/prepare-native.py
python3 scripts/pack.py
python3 scripts/check.py
```

The prepared archive is copied into the Lab by `pack.py`, so mobile validation exercises the same addon layout a customer installs. Follow the [Lab guide](../examples/sdk-lab/README.md) for platform exports and local HTTP debugging.

## Release qualifications

Physical-device signing, App Store / Play sandbox purchases and restores, release-store installation, and native Experience presentation/App Action qualification must be recorded before publishing a production release. Automated callback tests are not evidence that a store transaction succeeded. See the [release checklist](release-checklist.md).
