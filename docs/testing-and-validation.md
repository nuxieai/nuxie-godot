# Qualification record

## Native v3 dependency qualification

This migration selects iOS
`28587b9b8e0c1fbcb012ebdff9645626706adcb8`
([iOS PR #488](https://github.com/nuxieai/nuxie-ios/pull/488)) and Android
`2e4c39929b397c808da0b9eefe4741aa83f8a4d0`
([Android PR #191](https://github.com/nuxieai/nuxie-android/pull/191)) for
[UNIV-4288](https://universe.basis.dev/issue/UNIV-4288).
`NATIVE-PINS.json` selects these inputs. Native product receipts must retain
their exact clean producer revisions; an earlier product cannot be relabeled.
Bazel compile actions share the existing host caches across worktrees, while
compiler outputs, staged products and fixture evidence remain checkout-owned.

The native v3 test target runs the shipped Swift adapter in a test-only UIKit
app with scene lifecycle support, against four reproducible, genuinely signed
profiles over a private loopback HTTP server.
It requires accepted v3 admission, ordered adapter and native Journey events,
matching identities and completion outcome, and exact number/string/Boolean
run outputs. Retired v1/v2 schemas and a v3 descriptor signed under the retired
domain require a concrete native authentication failure after the identified
profile response completes. Live event transport and successful shutdown are
required for every case. Test results execute afresh even when compilation
reuses cached actions. The fixture generator, original native wire golden and
independent verifier are tracked alongside the harness.

Qualification ran on clean source
`e938faf021eb87ed0c04406ba30a7ef73be667f9`:

- Native preparation passed for Debug and Release Android bridge/Maven products
  and iOS Swift/engine-plugin frameworks using the exact authenticated native
  revisions above.
- The default iOS 27 simulator passed all six existing Swift bridge cases and
  four fresh signed-profile cases. Each signed case delivered all 45 transport
  controls and completed public shutdown. The accepted case verified ordered
  adapter/native Journey identity, outcome and typed outputs. Negatives observed
  the terminal native authentication class after the complete identified-profile
  response. The log redacts its specific reason; each exact signed descriptor
  and domain input was independently checked against schema/signature rules.
- All 56 frontend helpers passed with zero skips, including the real Mach-O
  compiler checks.
- The first owning `python3 scripts/check.py` invocation, through the canonical
  simulator helper, passed six Python cases, real pinned-editor imports,
  69 GDScript checks and three freshly executed
  Android bridge cases. It exited 1 when independent Gradle lint could not find
  the native Maven coordinate because native preparation had been omitted.
  That whole invocation remains a failure, rather than an aggregate PASS.
- The canonical `python3 scripts/prepare-native.py` followed by
  `python3 scripts/pack.py` passed. The pinned editor imported the freshly
  packaged Lab. The independent Gradle lint replay passed with zero errors and
  one Gradle-version warning using the authenticated staged Maven coordinate,
  a private Gradle/JVM scratch root, and this exact command:

  ```sh
  ./gradlew :android-plugin:lint --max-workers=1 --no-daemon \
    -Pkotlin.compiler.execution.strategy=in-process
  ```

The original command/stage records join successful checks against unchanged
compiler inputs, generated resolver locks and authenticated native products.
The final documentation-only revision is packed separately, and its
package/source closure and ZIP identity belong in the PR or external release record. No
uninterrupted whole-check PASS is asserted here.

These checks cover screenless native adapter sessions, their public event/run
output boundary, headless GDScript behavior and package/import integrity. They
leave rendered forms, native text-input UI, Android Journey execution, physical
mobile devices and engine-player presentation unqualified. Historical native-v2
and player evidence below retains the revisions and limits it names.

### Selecting the local simulator

The hosted native-v3 target passed its strict log-readiness and authentication
oracle on the helper's default iOS 27 simulator. A same-binary control established
that the pinned standalone logic runner's `simctl spawn -s` disables the tested
log path; ordinary hosted launch delivers the marker. The earlier standalone
capture observations remain in
[UNIV-4333](https://universe.basis.dev/issue/UNIV-4333).
[UNIV-4322](https://universe.basis.dev/issue/UNIV-4322) tracks the separate React
Native example lifecycle issue. This Godot adapter qualification covers its
actual hosted sessions and does not establish other SDK consumers' runtime
support.

Use the canonical simulator helper from the SDK checkout:

```sh
python3 scripts/bazel/ios_simulator.py -- python3 scripts/check.py
```

The helper selects the latest available supported iPhone runtime, creates and
boots a private simulator, then shuts down and deletes only its own device after
completion or failure. To use a separately leased, already booted device, pass
its UUID:

```sh
NUXIE_IOS_SIMULATOR_ID=YOUR_BOOTED_DEVICE_UUID \
  python3 scripts/bazel/ios_simulator.py -- python3 scripts/check.py
```

The caller retains shutdown and preservation ownership for that device.
Authentication, response-completion barriers, signed-profile verification,
PID/time scoping and event assertions stay unchanged. Qualification records must
retain the selected UUID/runtime, exact command, original logs and result.

## Previous native v2 Bazel build migration

The native v2 Bazel migration used iOS
`615a31bd03483e79a8590f8408b035659581f8f7`, landed in
[iOS PR #487](https://github.com/nuxieai/nuxie-ios/pull/487). Its Android
dependency was `7ebe2d72570b169712fd913fd2c5b2de4bf2848d`, landed in
[Android PR #189](https://github.com/nuxieai/nuxie-android/pull/189).
These pins and the results in this section belong to the previous native v2
build migration. They do not qualify the native v3 inputs above.

The owning SDK uses direct Bazel targets in local development and CI. Repository
and action caches are shared across worktrees; compiler outputs and staged
products are private to each checkout.

At build-source revision `fad60a728c2527ec9a427e08e457bd0ac40ea15a`,
`python3 scripts/check.py` passed with the original native producer receipts and
a temporary owned iOS simulator. It covered six Python tests, all 69 GDScript
client checks, the original Android bridge tests, independent Gradle lint,
Debug/Release native preparation, and all six original Swift tests. The three
Android cases executed successfully in the preceding
`python3 scripts/bazel/sdk.py test-android` retry; the owning check reused that
passed result. All 44 frontend helper tests also passed. Authored native sources
and behavioral assertions are unchanged.

`python3 scripts/pack.py` produced `nuxie-godot-0.4.0.zip`, SHA-256
`705a3366b9093675f24b4abd4b24653242f678583f64785a81dfaf2c8b0b3340`.
Independent inspection verified all 176 checksummed addon files, both bridge
AARs at API 23, all 25 files in the selected native Maven coordinate, all four
XCFrameworks, licenses, exact native pins, and the standalone Lab's identical
file hashes. The pinned Godot editor imported the freshly packed Lab headlessly.

Actual Debug/Release Swift and C++ action graphs contain exactly the iOS 15
ARM64 device and ARM64/x86_64 simulator target triples. Mach-O inspection confirms
the corresponding device/simulator platforms and architectures. Each bridge
slice retains the six inventoried SDK resource files and generated interface;
licenses match the original receipts. The strict dependency checker passes,
and the test runtime excludes the compile-only Godot engine classes. These are
build and package checks; historical player/store measurements below retain
their original revisions and scope.
`swift package --package-path ios-plugin --scratch-path .native/swift-resolution resolve`
resolved the exact landed iOS revision and refreshed the checked-in SwiftPM lock
without compiling. Historical qualification below applies only to the revisions
it names.

## Previous Experience goal and eligibility pin qualification

iOS `8c41617716c5c5086aba44e0d64f048692c515ae` and Android
`0cbe8086068eb1a0d7e1c53c4440de4c9e3bd5ae` implement the Experience policy
hard cut: one optional goal, retained conversion measurement, presentation-safe
exits, and offer-specific access checks. Both preserve internal action and
renderer origins through redaction, durable capture, and recovery; ordinary
analytics IDs cannot authorize direct custom attribution. Old milestone/policy
payloads are rejected. Terminal dismissals before presentation complete without
manufacturing screen events.

Both native SDK full gates passed at these pins. The iOS timestamp correction
preserves millisecond occurrence ordering for renderer goals. Native preparation
and `python3 scripts/check.py` passed (4559 exit 0): three Python tests, pinned
Godot imports and client checks, Android bridge tests/lint/builds, and six iOS
bridge tests. Preparation produced Android Maven/bridge artifacts and iOS
device/simulator XCFrameworks; the Swift lock resolves the exact iOS revision.
Logs: `/tmp/nuxie-goal-clock-godot-{prepare,full}.txt`.

The parent eight-case iOS/server core acceptance passed at `a7c5b5d094`, including
renderer goals with exits enabled/disabled and owned-offer routing. This is
native behavioral evidence; the wrapper checks prove bridge and host integration.
Coordinated delivery remains pending.

## Previous video SDK pin qualification

iOS `1e6970f306a9dac2ed567a239bf0e64a83e2d7cc` and Android
`20f9d42f7d5fe1cba6e2426d63c24499eb966ce7` include shared immutable-video
bindings, cancellation of obsolete acquisition, and live caption preference
refresh. Native preparation rebuilt the four iOS XCFrameworks and both Android
bridge variants. The addon independently verified its exact pins and all 142
artifact hashes. Final committed-tree readiness is recorded in the PR.

On the API 36 emulator, the actual Godot Lab passed the opt-in game audio probe
with both audible and muted signed video. Screenshots contained red and blue
frames. The engine's 440 Hz tone produced approximately −20 dB mixer output
before presentation, its playback position stayed fixed under the Lab's
SceneTree pause policy, and SDK dismissal restored both clock progression and
mixer output. The muted run used an eight-second presentation after an earlier
four-second capture sampled only red and was excluded. Both runs cleared the
synthetic Lab's data first. This proves the app's explicit game-audio ownership
policy; it does not measure acoustic speaker output or other applications.

## Earlier cache-preservation pin qualification

iOS `48fa51d6591f61d437620abfa06eb7fcb1a64564` preserves a verified cached object when a conflicting
signed byte-count claim is rejected. Android remains
`4d65783e2eec5b585673041146dff887258d3c93`. All four native iOS XCFrameworks were rebuilt against this cache-only fix;
the customer addon passed independent verification of its exact pins and all
142 artifact hashes. Final readiness is recorded in the pull request. Player
measurements below name the preceding iOS pin and the same Android revision.

## Final video playback candidate checks

iOS `95d76d41eb4cc945cb57e5c1bcd8333ed15d55cc` and Android `4d65783e2eec5b585673041146dff887258d3c93` include
published Apple runtime 0.10.8 and Android runtime 0.4.8, rendered-video visibility,
and interruption recovery fixes. Three Python checks and all 69 GDScript client
checks passed at these pins. `python3 scripts/check-ios.py` resolved the exact
iOS revision and passed all six Swift bridge tests on the iPhone 18 Pro
simulator running iOS 27. Android bridge unit tests, lint and debug/release
builds passed with the exact Android pin. Its native Maven coordinate reused
the independently hash-verified artifact built by Unity preparation at the same
revision; the matching native source checkout supplies dependency licenses.
The canonical iOS build script produced all four release/debug Swift bridge
and engine-plugin XCFrameworks with device ARM64 and simulator ARM64/x86_64
slices against the resolved iOS pin. The addon passed independent verification of all 142 file hashes and exact
native pins. Player results on both platforms follow.

The actual ARM64 iOS simulator player passed a clean cold launch, background /
foreground return, and process restart while the delivery origin timed out.
Each 12-screenshot sequence observed at least three red/blue transitions after
startup, excluding a static launch snapshot as a playback oracle. Independently
hashed cached scene `242a0ebc242f2617d923a9e1e04a7cf01b9d5d6a8e62cc934f1f26df6efef4db`
and MP4 `f0a65563c100506c0f98c138e8be1ae333c9879bb77237fbada60bddcfa78669`
matched the signed inventory. This establishes the tested iOS playback and bounded
origin-outage cases, not audio measurement, caption accessibility, or every
resource/failure scenario. Canonical readiness passed at this candidate, including
all bridge and source checks. The actual Android player passed clean cold playback and Home/Recents return,
with at least three video color changes in each accepted capture. Its cached
scene and MP4 hashes matched the signed inventory, and the APK passed 16 KiB ZIP
alignment. Intermittent host ADB daemon restarts produced rejected empty
screenshots; they are retained as harness errors rather than playback evidence.

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

Follow the [integration guide](integration-guide.md) for the pinned editor and
native toolchain setup. From the SDK checkout, prepare native products and the
customer package before the owning check:

```sh
python3 scripts/prepare-native.py
python3 scripts/pack.py
python3 scripts/bazel/ios_simulator.py -- python3 scripts/check.py
```

Preparation supplies the exact native Maven coordinate required by independent
Gradle lint. Packing stages the same addon into the Lab that customers install,
so its headless import checks the prepared package layout. The owning check
includes source tests, pinned Godot imports/GDScript behavior, Android bridge
unit tests, independent Gradle lint and the original plus signed-v3 iOS suites.
Inspect the actual summaries and original exit status.

Use `NUXIE_IOS_SIMULATOR_ID` with the canonical helper for a leased, already
booted caller device as described above; otherwise the helper owns its temporary
simulator. Record any interrupted or failed command separately from successful
source-equivalent stage replays. Follow the [Lab guide](../examples/sdk-lab/README.md)
for platform exports and local HTTP debugging.

## Release qualifications

Physical-device signing, App Store / Play sandbox purchases and restores, release-store installation, Android native Experience presentation/App Action interaction, and external checkout under a native overlay must be recorded before publishing a production release. Automated callback tests are not evidence that a store transaction succeeded. See the [release checklist](release-checklist.md).
