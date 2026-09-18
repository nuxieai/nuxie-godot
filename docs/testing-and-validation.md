# Qualification record

## Current native pins

iOS `95d76d41eb4cc945cb57e5c1bcd8333ed15d55cc` and Android `4d65783e2eec5b585673041146dff887258d3c93` include
published Apple runtime 0.10.8 and Android runtime 0.4.8, rendered-video visibility,
and interruption recovery fixes. Three Python checks and all 69 GDScript client
checks passed at these pins. `python3 scripts/check-ios.py` resolved the exact
iOS revision and passed all six Swift bridge tests on the iPhone 18 Pro
simulator running iOS 27. Android bridge unit tests, lint and debug/release
builds passed with the exact Android pin. Its native Maven coordinate reused
the independently hash-verified artifact built by Unity preparation at the same
revision; the matching native source checkout supplies dependency licenses.
iOS artifact preparation, player builds/playback and final readiness remain
pending. Results below identify the earlier revisions they qualified.

## Native video format fix — September 18, 2026

The preceding qualification used iOS `858321e2` and Android `1514b1c`. Native preparation
completed against the iOS content-addressed-video fix. The rebuilt addon passed
independent verification of all 142 file hashes and exact native pins. Fresh
bridge checks and final readiness remain outstanding at these pins. The Lab now has playback-only `autoConnect` startup;
its import and 69 GDScript client checks passed. Android export uses ordinary
window mode so the platform's first-use immersive help cannot obscure the
qualification scene. The configured Android export passed. The actual Android player then displayed
both red and blue video phases across 12 screenshot samples, with native
`screen_shown` and `experience_shown` events. Independently hashed cached scene
and MP4 bytes matched their signed identities. The first capture was obscured
by fullscreen help; the ordinary-window build passed visible playback.
The standard iOS
simulator template again failed ARM64 linkage because its archive contains
x86_64 objects only. The documented unmodified pinned-engine ARM64 source build
completed, and the resulting simulator Lab built and visibly played both phases
across 12 screenshot samples. Its cached scene and MP4 hashes matched the signed
inventory. This is source-built simulator-engine evidence, not qualification of
the downloaded simulator archive. Audio, captions, resource/failure cases, and
final readiness remain separate requirements.

## Earlier native pin refresh — September 18, 2026

The earlier development pins were iOS `072e38b24df67f7e6326815ed5e126c93c8e67d7`
and Android `1514b1cce3d64502b483c41fa551e7290caf10b0`, including shared
decoder admission and hidden-screen suspension. `scripts/prepare-native.py`
rebuilt the native artifacts. `scripts/check.py` passed three Python checks,
69 GDScript checks, Android bridge tests/lint/debug and release builds, and
six Swift simulator tests. Shared Gradle cache metadata was unavailable, so
these checks used an isolated task cache with JDK 17/21 configured.

`scripts/pack.py` rebuilt the customer addon. Independent ZIP inspection
verified all 142 file hashes and exact native pins. Actual signed-video playback
in the Godot mobile Lab and final readiness/review remain outstanding.

## Earlier video delivery candidate — September 18, 2026

This candidate pins pushed native development revisions iOS
`38428e8bb1c65605d6c982ff22b2a18d63229950` and Android
`e76714a76e14b8f293e782934c107a789d0a67f0`, pending final native qualification
and review under [UNIV-3262](https://universe.basis.dev/issue/UNIV-3262).

With Godot 4.7.2 (`ed1daf0bf`), `scripts/check.py` passed three Python checks,
69 GDScript checks, three Android bridge tests, Android lint and debug/release
builds, and six iOS bridge tests on the simulator. `scripts/prepare-native.py`
built the pinned Android Maven artifact and all four iOS XCFrameworks: debug
and release Swift bridges and engine plugins, each with device ARM64 and
simulator ARM64/x86_64 slices. Xcode 27 checks each required architecture
individually because its multi-architecture `lipo -verify_arch` invocation fails.
The Android preparation script uses the release variant owned by the native SDK
instead of registering it again.

`scripts/pack.py` produced the addon ZIP and staged that same addon into the Lab.
Independent ZIP inspection verified all 142 file digests, exact native pins,
and the four XCFramework architecture inventories. The staged Lab imported in
Godot 4.7.2 headless mode without script errors.

This establishes bridge regression, artifact build, and package integrity.
Signed-video playback, acquisition, captions, and lifecycle behavior through
the Godot player still require device qualification. The earlier live evidence
below does not qualify this video candidate. Final readiness/review and the
parent pointer update remain pending.

## Earlier qualification

Live qualification: 2026-09-13. Review regression checks and native artifact rebuild: 2026-09-14. This record separates executed checks from release qualifications that still require a signed device and store account.

| Layer | Configuration | Evidence |
| --- | --- | --- |
| GDScript client | Godot 4.7.2, headless | 69 checks: lifecycle, stale snapshots, detached values, JSON validation, checkout correlation, timeout, paused dispatch and shutdown |
| Android bridge | Pinned native dependency, debug/release AARs | Unit tests, Android lint and both builds pass |
| iOS bridge | Pinned native dependency, iOS simulator | Six native tests pass; device/simulator debug/release frameworks build |
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
