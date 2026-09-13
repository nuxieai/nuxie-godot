# Release checklist

- Update the canonical native pins and wrapper version together; build from those exact revisions.
- Run `python3 scripts/check.py` and inspect the actual test summaries.
- Run `python3 scripts/prepare-native.py` then `python3 scripts/pack.py` on the release candidate.
- Import the ZIP into a clean Godot project. Enable/disable/re-enable the editor plugin; verify one autoload and correct iOS descriptor ownership. Check unsupported-engine/missing-artifact errors.
- Export debug/release Android, inspect merged manifests and dependencies, verify release shrinking and 16 KiB native-library/ZIP alignment. The addon must not bundle a second Godot engine or conflicting C++ runtime.
- Export iOS, inspect debug/release adapter selection, resource bundles, privacy manifests and embedded frameworks. Build the device archive and qualified simulator input separately. Do not present a locally repaired simulator template as an official template result.
- Run the Lab on both mobile platforms against disposable backend grants; independently inspect the backend debit and replay identity.
- Exercise a published native Experience, real App Action, dismissal, pause restoration, scene changes and background/resume. Test external checkout while native UI covers the game.
- Record store sandbox purchases, pending/cancelled outcomes, restore and physical devices explicitly; mark unavailable checks unrun.
- Update README, API reference, VERSIONS and qualification evidence to match the final package. Remove obsolete live documentation instead of retaining two contradictory APIs.
- Commit/push the SDK branch and pass its native readiness gate before opening a ready PR. Update the parent submodule pointer in a separate PR with its own readiness evidence.
- Publish a tagged release and immutable checksum-bearing addon only after release qualification. Opening or merging a source PR does not itself publish a package.
