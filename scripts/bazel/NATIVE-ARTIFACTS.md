# Prepared native SDK imports

`native_artifacts.bzl` and `native_artifacts.py` consume the native SDKs'
`sdk-artifacts.json` schema 1. Both producers expose that receipt through
`scripts/bazel/sdk.sh prepare`. Preparation runs in the native SDK repository;
the downstream graph imports the resulting products without compiling that
repository again.

The caller declares `platforms` 1.0.0, `apple_support` 2.8.0, `rules_apple` 4.5.0,
`rules_swift` 4.1.0, `rules_cc` 0.2.20, and `rules_android` 0.8.0 in MODULE.bazel.
It then registers one native artifact contract:

```starlark
native = use_extension("//scripts/bazel:native_artifacts.bzl", "native_artifacts")
native.artifacts(
    pins = "//:NATIVE-PINS.json",
    android_dependencies = {
        "@maven//:com_android_billingclient_billing": "com.android.billingclient:billing:9.1.0",
        # Include every compile/runtime coordinate in the producer POM.
    },
)
use_repo(native, "nuxie_native_ios", "nuxie_native_android")
```

Set `NUXIE_IOS_ARTIFACTS` and `NUXIE_ANDROID_ARTIFACTS` to absolute manifest paths
or their containing directories. Tags `ios_manifest` and `android_manifest`
can select explicit absolute paths instead. The verifier rejects dirty native
source, a source revision different from `NATIVE-PINS.json`, missing files,
changed sizes or SHA-256 hashes, unsafe paths, and changed/escaping symlinks.
Only receipt-verified files are exposed. The repository watches the prepared
tree so replacing a product causes verification again.

The iOS repository exports `:sdk` as static Nuxie/NuxieRuntime Swift imports and
the pinned runtime XCFramework. Its Swift `data` carries `Nuxie_Nuxie.bundle`.
`:framework` imports the produced dynamic SDK framework with its compile-only
runtime Swift/C imports; `:resources` exposes the bundle. Selection follows
the Bazel Apple platform/CPU and compilation mode (`opt` selects Release,
`dbg`/`fastbuild` select Debug). Prepare each required product first. Compiled
Swift modules require the producer's compatible Xcode toolchain. Versioned
macOS dynamic framework consumption still needs qualification; static macOS
imports follow the same architecture selection.

The Android repository exports `:sdk` through `aar_import`, preserving the
native libraries/resources in the producer AAR. Every compile/runtime POM
coordinate must map to a configured dependency label. Those labels may reflect
the consumer's locked Maven conflict resolution (for example, SQLite can select
Kotlin 2.1.20 while the published POM requests 2.0.21). `:maven` exposes the
prepared Maven version for existing package consumers.

Both repositories expose `:artifacts` and the original `sdk-artifacts.json`.
The receipt remains the packaging/provenance contract. Build outputs stay in
each workspace's output base; native inputs and downstream compiler actions
use the shared immutable cache policy.

Run the independent verifier tests without a native build:

```sh
python3 -B -m unittest discover -s scripts/bazel -p 'test_native_artifacts.py'
```
