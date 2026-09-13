# API reference

The `Nuxie` autoload owns one native session. Call its API on Godot's main thread. Callers receive detached value objects: modifying a returned access, dictionary or receipt cannot mutate the client's cache. GDScript internal fields are not a privacy boundary.

## Lifecycle and identity

| Method | Awaited result | Contract |
| --- | --- | --- |
| `configure(NuxieOptions)` | NuxieResult | Equivalent concurrent calls share setup; changing options/controller requires shutdown. |
| `shutdown()` | NuxieResult | Settle pending calls, discard the session and invalidate access. |
| `identify(customer_id, NuxieIdentityOptions = null)` | NuxieResult | Set customer and optional `properties` / `properties_set_once`. |
| `get_identity()` | NuxieIdentityResult | Coherent `distinct_id`, `anonymous_id`, `is_identified`. |
| `reset()` | NuxieResult | Sign out and rotate the anonymous identity. |
| `set_locale(locale = "")` | NuxieResult | Empty restores device locale; native synchronization determines application timing. |

`is_available()` synchronously checks the native bridge, not connectivity. `get_status()` returns a NuxieStatus with `kind` (UNCONFIGURED, CONFIGURING, READY, SHUTTING_DOWN, FAILED) and optional error. Failed configuration can be followed by explicit shutdown and a fresh configure.

NuxieOptions is a Resource with `ios_api_key`, `android_api_key`, `environment` (EnvironmentKind.PRODUCTION or DEVELOPMENT), `log_level` (WARNING, DEBUG, INFO, ERROR, NONE, VERBOSE), and `locale`. Its `billing` defaults to native. Only the running platform's key is required. Options are copied on configuration; changing the original object does not reconfigure native state.

Identity mutations are serialized: await the preceding identify/reset. Queries arriving during a transition fail clearly. Old identity queries cannot authorize a new player. An in-flight consumption may return its original customer's receipt; it does not change the new customer's snapshot.

## Results and errors

Every awaited result has `ok` and `error`. Data results have a typed `value` on success:

- NuxieIdentityResult → NuxieIdentity.
- NuxieFeatureResult → NuxieFeatureAccess.
- NuxieUsageResult → NuxieUsageReceipt.
- NuxieResult acknowledges an operation with no value.

Errors contain `code`, `message`, and copied `details`. Client codes include `unsupportedPlatform`, `invalidArgument`, `notConfigured`, `alreadyConfigured`, `lifecycleBusy`, `identityChanged`, `sdkShutdown`, `operationTimeout`, `invalidResponse`, and `incompatibleBridge`. Native errors retain their bridge code. Do not branch on message text.

The client retains completion before notifying waiters. Normal native calls have a 90-second foreground dispatcher timeout. Timeout/shutdown stops waiting; it does not reverse a completed debit. Retry durable usage with the same operation ID. OS suspension can delay Godot code and therefore timeout delivery until the app resumes.

## Features and consumption

`get_feature_snapshot()` and `get_feature_state(feature_id)` read local state without a request. Snapshot fields include `kind`, `customer_id`, exact decimal-string `identity_generation` and `revision`. `select(feature_id)` returns a NuxieFeatureState with `kind` and nullable `access`; `get_all()` returns a detached dictionary of typed access objects.

FeatureState.Kind values: UNKNOWN, RECONCILING, READY. Access contains `allowed`, `unlimited`, nullable floating-point `balance`, and native `type` (boolean, metered, creditSystem). Missing access and unknown authority are distinct states.

`await check_feature(feature_id, query)` returns a NuxieFeatureResult. NuxieFeatureQuery has `entity_id`, integer `required_balance` (1), and Policy.CACHE_FIRST / REMOTE. Queries do not replace the global snapshot.

`await consume_feature(feature_id, command)` returns a NuxieUsageResult. NuxieFeatureCommand has required `operation_id`, integer `quantity` (1), and optional `entity_id`. Quantity and required balance are in 1…2^53−1. Invalid values are rejected before native invocation. The native consumption contract has no metadata field.

Receipt fields: `customer_id`, `feature_id`, `operation_id`, `quantity`, nullable `occurred_at_ms`, `accepted`, `code`, nullable `balance`, `unlimited`, `active`, `idempotent_replay`. Acceptance authorizes the operation even when the resulting balance is zero. Persist the operation ID before spending; implement game-side idempotency separately.

## Experiences and signals

`await trigger(event_name, properties = {})` acknowledges event acceptance, not UI presentation or Journey completion. `await dismiss()` acknowledges native dismissal. Properties and identity attributes must be finite JSON values with string object keys, no Objects/cycles and at most 32 levels of nesting; integer JSON values stay within the portable exact range.

| Signal | Payload |
| --- | --- |
| `status_changed` | NuxieStatus |
| `identity_changed` | NuxieIdentity |
| `features_changed` | NuxieFeatureSnapshot |
| `activity_received` | NuxieActivity: ID, name, timestamps and properties |
| `app_action_received` | NuxieAppAction: name, payload, typed Experience context |
| `error_received` | NuxieError for unsolicited protocol errors |

Connect before reading current state. Disconnect on scene exit, even if keeping the Node alive for reuse. Callbacks use the Godot thread. The dispatcher processes at most 128 envelopes per frame and runs through SceneTree pause. The game owns pause/audio/input policy. Native OS suspension is separate from scene pause.

## External checkout

Set `options.billing = NuxieBilling.external(controller)` before configuring. Implement NuxiePurchaseController's `purchase(product)` and `restore()` methods; each can return synchronously or await an existing checkout integration. Return NuxiePurchaseResult.purchased/cancelled/pending/failed(message), or NuxieRestoreResult.restored/no_purchases/failed(message). A missing result fails; native deadlines settle abandoned requests after 60 seconds.

The adapter deduplicates native requests and fences replies by session and deadline. Raw bridge request IDs and completion methods are private. External mode selects app-managed/observer handling: the host finishes/acknowledges transactions, while native provider authority governs verified purchase synchronization. Observe Features for access.

NuxieStoreProduct preserves the selected offer:

| Field | iOS source | Android source |
| --- | --- | --- |
| platform | ios | android |
| product_id / store_product_id / placement_id | StoreProduct identifiers | StoreProduct identifiers |
| display_name / description | name / description | raw ProductDetails name / description |
| display_price | StoreProduct price | matched base-plan/offer or purchase-option/offer price |
| product_type | StoreProduct productType | ProductDetails productType |
| period / period_count / billing_plan | Native subscription metadata | null |
| eligibility_jws / introductory_terms | Native eligibility and introductory terms | null |
| base_plan_id / purchase_option_id / offer_id | null | Exact selected identifiers |
| pricing_phases | null | Matched subscription offer's phases |

Nullable platform fields remain nullable. The native purchase result contract accepts an outcome, not a fabricated transaction dictionary. Do not run two owners for the same checkout or interpret checkout initiation as purchased.

The addon does not require .NET. C# can dynamically consume synchronous state and signals, but this release does not expose an async C# facade; GDScript coroutine state cannot be awaited through a bare GodotObject.Call.
