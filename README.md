# Nuxie for Godot

**0.4.0 release candidate · Godot 4.7.2 · iOS and Android**

Bring native Experiences, purchases and feature access into your Godot game—with one addon for iOS and Android.

Write ordinary GDScript. Let Nuxie's native SDKs deliver Experiences and manage access. Keep gameplay, scene navigation and pause behavior in your game.

Local API checks pass on both platforms, including repeated iOS warm starts. Local signed Experience publishing and iOS native screen/App Action delivery are validated. See the [measured results and remaining device/store qualification](docs/testing-and-validation.md).

## Install once, export to both platforms

1. Use the prepared `nuxie-godot-0.4.0.zip` and extract `addons/nuxie` into your project. From a source checkout, run `python3 scripts/prepare-native.py` and `python3 scripts/pack.py` on macOS to produce it in `dist/`. See the [build guide](docs/integration-guide.md) for toolchain setup.
2. Enable **Nuxie** in **Project → Project Settings → Plugins**. It registers the persistent `Nuxie` autoload and checks the native artifacts.
3. For Android, install the matching Android build template and enable Gradle builds in the export preset. For iOS, enable the staged **NuxieGodot** plugin in the iOS export preset and use the matching export templates.

You do not compile the Nuxie SDK, replace your Android Activity, or manually reconnect native dependencies after each export. Xcode, Android tooling and signing are still required for their respective platforms.

Use standard Godot 4.7.2 with matching export templates. Android requires API 24 or newer; iOS requires 15 or newer. See the [qualification record](docs/testing-and-validation.md) for the simulator-template caveat and checks actually run. This is a GDScript mobile SDK; desktop/Web native support and a typed C# facade are outside the initial release. The Editor can run the Lab UI, but native commands return unsupported-platform errors. There is no automatic simulated success.

## Connect your game

Call from a startup Node before enabling Nuxie-dependent gameplay:

```gdscript
extends Node

func _ready() -> void:
    var options := NuxieOptions.new()
    options.ios_api_key = "YOUR_IOS_PUBLIC_KEY"
    options.android_api_key = "YOUR_ANDROID_PUBLIC_KEY"
    options.environment = NuxieOptions.EnvironmentKind.DEVELOPMENT

    var result: NuxieResult = await Nuxie.configure(options)
    if not result.ok:
        push_error(result.error.message)
        return

    var identity: NuxieResult = await Nuxie.identify("player-123")
    if not identity.ok:
        push_error(identity.error.message)
        return

    var event: NuxieResult = await Nuxie.trigger("game_opened")
    if not event.ok:
        push_error(event.error.message)
```

Use public platform keys from the same Nuxie app. Server credentials never belong in your game. Production, warning logging, device locale and native billing are the defaults.

Nuxie persists across scene changes. Configure once; equivalent concurrent calls share initialization. To change configuration, explicitly `await Nuxie.shutdown()` first. Configuration success means the SDK is configured—not that feature access is already known.

Async methods return typed results. Check `ok` before using a data result's `value`; failures carry `error.code` and `error.message`. A denied feature query can succeed as an operation while its returned access has `allowed == false`.

## React to access

Connect before reading state, so your UI has an initial value and receives later changes:

```gdscript
extends Control

func _ready() -> void:
    Nuxie.features_changed.connect(_on_features_changed)
    _update_access()

func _exit_tree() -> void:
    if Nuxie.features_changed.is_connected(_on_features_changed):
        Nuxie.features_changed.disconnect(_on_features_changed)

func _on_features_changed(_snapshot: NuxieFeatureSnapshot) -> void:
    _update_access()

func _update_access() -> void:
    var state := Nuxie.get_feature_state("premium")
    $Loading.visible = state.kind == NuxieFeatureState.Kind.UNKNOWN
    $PremiumContent.visible = state.access != null and state.access.allowed
```

**Unknown** means access has not been established. **Reconciling** means the native SDK is reconciling authority, including purchases. **Ready** is authoritative and may contain no grant. Use the supplied access; do not invent a grant from a purchase callback or turn a network error into a denial.

Signals arrive on the Godot main thread. Disconnect when a scene leaves the tree, including scenes you retain for later reuse. Changing scenes does not shut down Nuxie.

## Check an entity

```gdscript
var query := NuxieFeatureQuery.new()
query.entity_id = "character-7"
query.required_balance = 1
query.policy = NuxieFeatureQuery.Policy.REMOTE

var result: NuxieFeatureResult = await Nuxie.check_feature("energy", query)
if result.ok:
    print("Can spend: ", result.value.allowed)
else:
    push_error(result.error.message)
```

Queries default to cache-first. Select remote when you need a fresh authoritative query. Entity queries use that entity's assigned grants and do not overwrite the global feature snapshot.

## Spend safely, including after a retry

Save an operation ID with your game action before spending. Pass that same ID every time you retry the action:

```gdscript
func spend_energy(saved_action_id: String) -> bool:
    var command := NuxieFeatureCommand.new()
    command.operation_id = saved_action_id
    command.entity_id = "character-7"
    command.quantity = 1

    var result: NuxieUsageResult = await Nuxie.consume_feature("energy", command)
    if not result.ok:
        push_error(result.error.message)
        return false

    return result.value.accepted
```

Native delivery is durable. A retry with the same ID returns the original decision; a new ID means a new spend. Your game must also make the resulting action idempotent. A lost response is not proof that a debit failed.

Check `accepted`, not `active`: consuming the final unit can succeed while leaving no usable balance. Receipts preserve the original customer, feature, operation, quantity, decision time and replay indicator. Some older native receipts have no decision timestamp. The current native consumption APIs do not accept usage metadata; attach game context to a separate event when needed. Quantities and required balances must be positive integers at most 2^53−1; balances can be fractional.

## Show an Experience and handle its actions

Trigger the event configured for your published Experience:

```gdscript
var result: NuxieResult = await Nuxie.trigger("shop_opened", {"source": "pause_menu"})
if not result.ok:
    push_error(result.error.message)
```

Completion acknowledges native event acceptance. Audience rules and Journey behavior determine what happens next; completion does not promise that a screen appeared.

Connect `Nuxie.app_action_received` to handle authored actions in your game. The typed action includes its name, payload, and Experience/Journey context. Connect `Nuxie.activity_received` for native lifecycle activity. Use `await Nuxie.dismiss()` when your game requests dismissal.

Your game owns pause, audio and input. The Lab demonstrates preserving an existing pause state through native screen transitions and restoring it after dismissal, including Journey exit. The Nuxie dispatcher continues through SceneTree pause; platform overlay behavior must be qualified on the mobile player.

## Choose who owns checkout

Native billing is enabled by default. Nuxie handles its store transaction lifecycle and updates feature access from native authority.

If your game already owns checkout, supply a `NuxiePurchaseController` through `options.billing = NuxieBilling.external(controller)`. Its `purchase(product)` method returns a typed purchased, cancelled, pending or failed result. `restore()` returns restored, no purchases or failed. Methods may await your store integration.

Preserve the exact selected product/offer and transaction context. External mode leaves finishing and acknowledgement to your integration; Nuxie's provider rules still govern verified transaction synchronization. Only one integration handles each checkout request. The SDK handles correlation, deadlines and late completion internally—there are no public request IDs to finish manually.

Continue observing features after checkout. A successful purchase callback alone is not an access grant.

## Account and locale changes

`await Nuxie.get_identity()` returns the coherent current identity in a `NuxieIdentityResult`. `await Nuxie.reset()` signs out and rotates the anonymous identity; observations from the previous customer are invalidated.

`await Nuxie.set_locale("fr_FR")` overrides the locale. An empty string returns to the device setting. The change follows native synchronization timing and does not promise an immediate profile refresh.

## Explore the SDK Lab

The [SDK Lab](examples/sdk-lab/README.md) is one complete example project for iOS and Android. Its startup and gameplay scenes demonstrate the same public API you use in your game.

Configure your local development app, public keys, published trigger event, metered feature and two disposable entity grants. The Lab checks identity, readiness, entity isolation, one-unit consumption, same-ID retry and original receipt fields against the real backend. A fresh operation spends a unit; rerunning its saved ID tests replay.

Then trigger a real native Experience, tap an authored App Action, dismiss it, and verify game pause and input restoration. Store sandbox checks are separate from API checks. The release qualification record identifies the exact editor, templates, native versions, devices and checks that passed.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Native adapter unavailable in the Editor | Run an iOS/Android player, or explicitly choose the Lab's simulated mode if supplied. |
| Export reports missing or mismatched artifacts | Install the prepared package for the qualified engine/templates and enable the platform export plugin. |
| Feature stays Unknown | Inspect configuration, identity and synchronization errors; Unknown is not a denial. |
| Trigger succeeds but nothing appears | Check the published event, audience rules and native activity. Success means event acceptance. |
| A spend appears twice | Reuse the saved operation ID and make the game's resulting action idempotent. |
| Callback works in tests but stalls over a native screen | Run the mobile overlay qualification; SceneTree pause and platform suspension are different lifecycle states. |

Continue with the [API reference](docs/api-reference.md), [SDK Lab](examples/sdk-lab/README.md), [native build and integration guide](docs/integration-guide.md), [qualification record](docs/testing-and-validation.md), and [release checklist](docs/release-checklist.md).
