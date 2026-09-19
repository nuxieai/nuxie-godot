# SDK Lab

One complete Godot project for iOS and Android, with separate startup and gameplay scenes. It consumes the staged public addon; it does not call native bridge methods directly.

1. Build/package the addon from the SDK root with `python3 scripts/prepare-native.py` and `python3 scripts/pack.py`.
2. Open this directory in Godot 4.7.2. Install matching export templates and the Android Gradle build template.
3. Copy the `android-overrides/standardDebug` directory to `android/build/src/standardDebug` to allow HTTP only in the local debug Lab. Godot owns and rewrites `src/debug`, so do not put the override there.
4. Copy `local-settings.example.json` to ignored `local-settings.json` and enter public development keys, a customer, a metered Feature, two entity IDs with disposable grants, and a published trigger. Alternatively use the on-screen form.
5. Export **Android** or **iOS**. Supply your real Apple team for a signed device export. **iOS Simulator** is an unsigned-project preset: its SIMULATOR team placeholder is not a signing identity; clear DEVELOPMENT_TEAM and disable signing when building it with Xcode.

For playback-only qualification, set `autoConnect: true` and leave `autorun`
false in local settings. The Lab configures and identifies on startup without
querying or consuming Features.

Run API Checks calls the real native/backend APIs and spends one unit. It records configuration, identity, readiness, scoped access, consumption, same-ID replay, original receipt preservation, one debit, entity isolation, locale and anonymous reset. Results are displayed and saved to `user://validation.json`; they also appear as `NUXIE_GODOT_VALIDATION` in the player log.

Play a turn persists a pending action before consuming energy and reuses that ID after an interruption. Game progress stores the last applied action ID so replay cannot award the score twice. Recover a pending turn as its original customer; do not silently spend on another account.

Trigger a published Experience and tap a real App Action. The Lab records its name and payload and tracks native screen dismissal to restore the prior SceneTree pause state. Change scene demonstrates autoload persistence and signal cleanup. The Editor displays the UI, but native commands fail explicitly; it is not a backend simulator.

Inspect the [qualification record](../../docs/testing-and-validation.md) before interpreting a successful build as runtime evidence. Store sandbox and physical-device purchase checks are separate from the API checks.

### Development audio coordination probe

Set `audioQualification: true` with `autoConnect: true` in the ignored local
settings to run the real engine's 440 Hz tone while a signed video Experience
opens. This flag is honored only in debug builds. The probe checks nonzero mixer
output and an advancing tone clock before presentation, the Lab's existing
SceneTree pause policy during presentation, then dismisses through the SDK and
checks restored tone progression and output. Inspect `NUXIE_GAME_AUDIO` logs and
confirm the visible video was moving; run with both audible and muted signed
fixtures. The Lab deliberately pauses game audio for every presented screen.
This measures engine output and ownership restoration, not external speaker
latency or other apps' audio. Remove the local flag for ordinary use.
