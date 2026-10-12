# CI runner lanes

The repository pipeline renders `scripts/ci/pipeline.py`. Its default graph
retains the original full readiness commands. `NUXIE_SDK_SPLIT_LANES=1` selects
the platform graph only with `NUXIE_CI_RUNNER_POLICY_VERSION=2` and the
consolidated topology. Invalid activation fails before uploading work.

Each v2 job declares its installed profile and capability before checkout:
Linux uses `linux-14g-v2` with `linux-portable` or `linux-native`; Apple uses
`mac-64g-v2` with `macos-apple`. All substantial jobs use eager concurrency one
in `nuxie/physical/proxmox-heavy` or `nuxie/physical/mac-m2`. The Mac runs one
agent. Repository upload uses Linux portable resources; the LIVE Buildkite
initial upload step must also receive the corresponding selector/profile before
v2 activation. Landing these source files does not change that live bootstrap.

The guarded Bazel frontend loads the actual installed root-owned helper and
policy: `/Library/NuxieBuildkite/hooks/runner-policy.py` and
`/Library/NuxieBuildkite/runner-policy.json` on Mac; Linux uses
`/usr/local/lib/nuxie-buildkite/hooks/runner-policy.py` and
`/etc/nuxie/buildkite-runner-policy.json`. Per-Bazel execution uses its admission,
cache owner lock and ceilings. The whole lane is not wrapped in a nested cache
lock. Profile/BEP files under `output/pipeline/` upload before the owning
post-artifact hook requests installed cleanup; uncertain or active outputs are
preserved. Native product receipts and failure evidence survive cleanup.

Remote caching defaults off, including upload jobs. Separately qualified read
clients require `NUXIE_CI_BAZEL_REMOTE_CACHE_MODE=read`, explicit comma-separated
`NUXIE_CI_BAZEL_CACHE_PROFILES`, eligibility `1`, a `sha256:` toolchain domain,
and all transport inputs: `NUXIE_BAZEL_REMOTE_CACHE_URL`, `_CA_FILE`,
`_TLS_PIN_FILE`, `_CREDENTIAL_FILE`, `_ELIGIBLE`, and `_DOMAIN` (all share the
`NUXIE_BAZEL_REMOTE_CACHE` prefix). The canonical helper validates the protected
single server leaf/pin, origin and private credential file before auth. Missing
qualification keeps the client off. SDK writer requests stay off. Synthetic
wrapper/receipt tests confer no native hermeticity or installed-host qualification.

This work belongs to [UNIV-4312](https://universe.basis.dev/issue/UNIV-4312).
Canonical native readiness remains mandatory before a ready PR; lightweight
fixtures prove routing and receipt behavior only.

`prepare-native.py --platform android|ios` and `check.py --platform
android|ios|portable` execute only the selected oracles. Their default `all`
still runs both mobile platforms and portable behavior. Android readiness
includes the pinned Godot/GDScript checks, Android bridge tests, independent
Gradle lint, and Debug/Release preparation. The Mac runs Debug/Release Apple
preparation, simulator bridge confidence and final dual-platform packaging.
Linux requires a provisioned pinned Godot editor for portable confidence. The
Mac retains its checksum-verified pinned Godot setup for the final Lab import;
the split Mac path performs no Android setup or rebuild.

The Android prerequisite exports `output/pipeline/android-products/` using
`lane_artifacts.py export`. This transport inventory binds the exact Godot
commit, exact Buildkite build/producer-job identities, raw native-pins hash, both bridge variants, published runtime identity,
Maven bytes and Android license while carrying the original native producer's
`sdk-artifacts.json` unchanged. The Mac downloads only `godot-android` from
`${BUILDKITE_BUILD_ID}`, verifies everything before restoration, and repeats
verification before `pack.py --require-android-handoff`. Missing, corrupt,
wrong-pin, wrong-candidate, symlinked or unlisted products fail without native
fallback. Final packing verifies both original iOS configuration receipts,
platforms and dependency license, retains all four XCFrameworks and both AARs,
and hashes the complete addon inventory plus exact pins/licenses into the
customer ZIP and identical Lab copy. Native `NATIVE-PINS.json`, runtime release
identities and authored plugin sources are unchanged.

The default `ci.sh` invokes full native readiness once, packs, then checks the
fresh Lab. The split `ci.sh --platform ios` requires restored Android products,
runs Apple readiness, packs both inventories and imports the fresh Lab.
Canonical local qualification remains `python3 scripts/check.py`.
