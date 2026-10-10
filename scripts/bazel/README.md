# Bazel worktree caches

The Bazel workspace imports `.bazel-cache.bazelrc`, matching `nuxie-runtime`
and all Nuxie SDKs. Action products, dependency downloads, and fetched
repository trees share `~/.cache/nuxie/bazel` across Git worktrees.

Bazel derives a separate output base from each checkout's path. Its `bazel-*`
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

This workspace establishes the cache policy for the SDK's Bazel migration.
Existing host-language build and qualification commands remain available.
