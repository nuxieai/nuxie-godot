# Bazel worktree caches

The Bazel workspace imports `.bazel-cache.bazelrc`, matching `nuxie-runtime`
and all Nuxie SDKs. Action products, dependency downloads, and fetched
repository trees share `~/.cache/nuxie/bazel` across Git worktrees.

Bazel derives a separate output base from each checkout's path. Its hidden `.bazel-*`
links and build outputs remain specific to that checkout, while matching actions
can be restored from the shared cache.

Use `scripts/bazel/bazel.sh` to run the pinned Bazel version. Set an absolute
`NUXIE_BAZEL_CACHE_DIR` to relocate only the reusable caches. A shared
`NUXIE_BAZEL_OUTPUT_USER_ROOT` still contains separate output bases for each
checkout; an explicit `--output_base` must be unique to the checkout.

Verify the cache override without compiling native sources:

```sh
python3 -B -m unittest discover -s scripts/bazel -p 'test_cache.py'
```

## Direct bridge builds and package preparation

```sh
python3 scripts/bazel/sdk.py test-android
NUXIE_IOS_SIMULATOR_ID=<available-simulator-id> python3 scripts/bazel/sdk.py test-ios
python3 scripts/prepare-native.py
python3 scripts/pack.py
python3 scripts/check.py
```

Kotlin sources compile in `//:android_bridge`; Godot's checksum-pinned Android
AAR is a compile-only engine API. `//:android_bridge_aar` preserves the owning
consumer rules. Swift compiles in `//:ios_bridge`; the C++ iOS plugin compiles in
`//:ios_plugin`. Bazel's Apple rules produce each device/simulator slice and
both Debug/Release XCFramework products consumed by the existing addon package.
Preparation verifies every binary and static archive member's Mach-O platform
as well as its declared device/simulator architectures.
Official SCons generators produce declared headers from the checksum-pinned
Godot 4.7.2 source archive; they do not compile the plugin or engine.

The standalone native helper prepares exact `NATIVE-PINS.json` revisions in
`.native/`. A parent build may provide absolute `NUXIE_IOS_ARTIFACTS` and
`NUXIE_ANDROID_ARTIFACTS` paths to its already prepared SDK receipts. Both paths
use the same revision/hash verifier and retain native resources and licenses.
Android Maven files, both bridge AAR variants and both XCFramework variants are
staged only in this checkout. Release packaging includes only the selected
source-addressed native Maven coordinate.

`scripts/check.py` remains the independent public contract: the pinned Godot
Editor imports and executes GDScript behavior tests, Android lint remains an
upstream analyzer, and direct Bazel bridge targets run JUnit and XCTest. CI uses
`scripts/ci.sh`, the same compiler targets and the same package/export contract.
It requires Xcode, Java 21, Android SDK 36/build-tools 36.0.0 and the native SDK's
pinned NDK. Compiler downloads
and matching actions share root/runtime caches; `.native/`, staged addon files,
Bazel output bases and engine import products remain checkout-local.

Godot ignores the hidden Bazel convenience links, so Editor imports cannot scan
or write import metadata into compiler outputs and toolchain repositories.
Artifact staging resolves Bazel's execution root directly instead of relying on
a particular convenience-link name.

CI runs its iOS tests through `scripts/bazel/ios_simulator.py`. The helper
creates and boots a private iPhone on the newest available compatible iOS
runtime, passes its exact UUID to the Bazel test runner, and deletes it after
success, failure or cancellation. Set `NUXIE_IOS_SIMULATOR_ID` to use an existing
caller-owned simulator; the helper preserves that device. The same helper can
wrap a local command, for example:

```sh
python3 scripts/bazel/ios_simulator.py -- python3 scripts/bazel/sdk.py test-ios
```
