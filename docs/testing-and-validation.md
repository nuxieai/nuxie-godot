# Qualification record

Live qualification: 2026-09-13. Review regression checks and native artifact rebuild: 2026-09-14. This record separates executed checks from release qualifications that still require a signed device and store account.

| Layer | Configuration | Evidence |
| --- | --- | --- |
| GDScript client | Godot 4.7.2, headless | 62 checks: lifecycle, stale snapshots, detached values, JSON validation, checkout correlation, timeout, paused dispatch and shutdown |
| Android bridge | Pinned native dependency, debug/release AARs | Unit tests, Android lint and both builds pass |
| iOS bridge | Pinned native dependency, iOS simulator | Three native tests pass; device/simulator debug/release frameworks build |
| Android player | Godot 4.7.2 standard templates, emulator | 21 live API checks pass against a local development app |
| iOS player | Godot 4.7.2 source-built ARM64 simulator engine | 21 checks pass on a clean install and on three consecutive warm launches with the authenticated cache retained |

The recorded live iOS runs used startup-fix revision `36d1c99ae11b3ded93583166fd1cace899260093`. Subsequent Codex review fixes to retained-route ordering, offline fallback, and concurrent profile recovery are validated by the native SDK regression suite and rebuilt bridge artifacts; the live player runs have not been repeated for those later revisions.

The live checks use the public addon and actual native clients: configure, identify, feature readiness, remote entity queries, consumption, retrying the same operation ID, receipt equality, exactly one debit, unchanged second entity, locale override/reset, anonymous identity rotation and reidentification. They do not mock backend grants or purchase outcomes. The Lab writes `user://validation.json` with every assertion.

## Resolved startup and local publication failures

- **iOS warm startup:** [iOS PR #421](https://github.com/nuxieai/nuxie-ios/pull/421) prepares the durable Journey journal before opening EventLog, then performs event-dependent recovery after readiness. The pinned native revision includes this repair. A real EventLog/SQLite regression first reproduced the timeout; lifecycle and buffered-event tests now pass, as do three consecutive 21-check simulator runs without clearing customer data. Tracked in [UNIV-3158](https://universe.basis.dev/issue/UNIV-3158).
- **Local publication:** [parent PR #6478](https://github.com/nuxieai/nuxie-dev/pull/6478) supplies local development signing to the embedded publisher, shares the worker registry with Miniflare, aligns the Vite plugin with the installed Wrangler protocol, and forwards the local HTTPS artifact origin. Both iOS and Android local publications succeeded with signed releases. Tracked in [UNIV-3157](https://universe.basis.dev/issue/UNIV-3157).

The iOS Lab rendered the actual published “Godot native Experience is active” screen. Tapping Continue delivered `sdk_lab_continue` through the public addon and dismissed the native screen back to the game. The local builds were `01m2ect086hkmayw6w7p0kqsbx` (iOS) and `01m2eeb41x33e60etsendc3gjh` (Android). Their RIV and font bytes were served from an HTTPS fixture endpoint after SHA-256 and byte-count verification; no production artifacts were uploaded. Android publication is verified, but an Android native screen/App Action interaction is not included in this run's evidence.

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

Physical-device signing, App Store / Play sandbox purchases and restores, release-store installation, Android native Experience presentation/App Action interaction, and external checkout under a native overlay must be recorded before publishing a production release. Automated callback tests are not evidence that a store transaction succeeded. See the [release checklist](release-checklist.md).
