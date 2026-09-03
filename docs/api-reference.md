# Nuxie Godot API Reference

The public API is the static `Nuxie` facade in `addons/nuxie/nuxie.gd`. Android and iOS both expose the native engine singleton as `NuxieGodot`.

## Operation results

Awaitable methods resolve to this shape:

```gdscript
{
  "ok": bool,
  "result": Dictionary,
  "error": Dictionary, # { code, message, nativeStack? }
}
```

The bridge uses request IDs and native operation events internally. They are transport details and are not part of the public subscription API.

## Lifecycle and identity

| Method | Return | Behavior |
| --- | --- | --- |
| `Nuxie.is_available()` | `bool` | Reports whether the native singleton is present. |
| `Nuxie.configure(api_key, options := {}, use_purchase_controller := false)` | `Dictionary` | Configures the native SDK. |
| `Nuxie.shutdown()` | `Dictionary` | Shuts down the native SDK and rejects pending wrapper operations. |
| `Nuxie.identify(distinct_id, user_properties := {}, user_properties_set_once := {})` | `Dictionary` | Updates local identity and properties. |
| `Nuxie.reset(keep_anonymous_id := false)` | `Dictionary` | Resets identity. The breaking-change default is `false`. |
| `Nuxie.get_distinct_id()` | `String` | Returns the current distinct ID or `""` on error. |
| `Nuxie.get_anonymous_id()` | `String` | Returns the current anonymous ID or `""` on error. |
| `Nuxie.get_is_identified()` | `bool` | Reports whether the current identity is identified. |
| `Nuxie.dismiss()` | `Dictionary` | Dismisses the currently presented experience. |
| `Nuxie.set_locale_identifier(locale_identifier := null)` | `Dictionary` | Sets an explicit locale or clears the override with `null`. |

## Journey events

```gdscript
Nuxie.trigger("level_completed", {
  "level": 7,
  "score": 4200,
})
```

`Nuxie.trigger(event_name, properties := {}) -> void` records the event. Any matching Journey evaluates asynchronously in the native SDK, and Journey evaluation always remains enabled.

## Feature access

Policy constants:

- `Nuxie.FEATURE_POLICY_CACHE_FIRST`
- `Nuxie.FEATURE_POLICY_REMOTE`

| Method | Return | Behavior |
| --- | --- | --- |
| `Nuxie.has_feature(feature_id, required_balance := 1.0, entity_id := "", policy := FEATURE_POLICY_CACHE_FIRST)` | `Dictionary` | Resolves feature access under the selected policy. |
| `Nuxie.use_feature(feature_id, amount := 1.0, entity_id := "", metadata := {})` | `void` | Records use without waiting for server confirmation. |
| `Nuxie.use_feature_and_wait(feature_id, amount := 1.0, entity_id := "", set_usage := false, metadata := {})` | `Dictionary` | Resolves after the server returns the authoritative usage result. |

Feature access result:

```gdscript
{
  "allowed": bool,
  "unlimited": bool,
  "balance": float | null,
  "type": "boolean" | "metered" | "creditSystem",
}
```

Authoritative usage result:

```gdscript
{
  "success": bool,
  "featureId": String,
  "amountUsed": float,
  "message": String | null,
  "usage": {
    "current": float,
    "limit": float | null,
    "remaining": float | null,
  } | null,
  "authoritativeAccess": Dictionary | null,
}
```

## Public events

Subscribe and unsubscribe with:

```gdscript
Nuxie.on("activity", callback)
Nuxie.off("activity", callback)
```

The only public event names are:

- `feature_access_changed`
- `activity`
- `app_action`
- `purchase_request`
- `restore_request`

### `feature_access_changed`

```gdscript
{
  "featureId": String,
  "from": Dictionary | null,
  "to": Dictionary,
  "timestampMs": int,
}
```

### `activity`

```gdscript
{
  "schemaVersion": int,
  "id": String,
  "timestampMs": int,
  "receivedAtMs": int,
  "name": String,
  "properties": Dictionary,
}
```

Activity property values are strings, integers, floats, or booleans.

### `app_action`

```gdscript
{
  "name": String,
  "payload": Dictionary | null,
  "experience": {
    "experienceId": String,
    "experienceVersion": String | null,
    "journeyId": String | null,
  },
}
```

App action payload values are strings, integers, floats, or booleans.

### `purchase_request`

```gdscript
{
  "request_id": String,
  "platform": "android" | "ios",
  "product_id": String,
  "store_product_id": String,
  "base_plan_id": String | null,
  "purchase_option_id": String | null,
  "offer_id": String | null,
  "placement_id": String | null,
  "display_name": String | null,
  "display_price": String | null,
  "timestamp_ms": int,
}
```

### `restore_request`

```gdscript
{
  "request_id": String,
  "platform": "android" | "ios",
  "timestamp_ms": int,
}
```

## App-managed purchase completion

`Nuxie.set_purchase_controller(on_purchase := Callable(), on_restore := Callable())` stores optional synchronous or asynchronous callbacks. The facade invokes them for native requests and completes the native continuation automatically.

Purchase callback results:

```gdscript
{"type": "purchased"}
{"type": "cancelled"}
{"type": "pending"}
{"type": "failed", "message": "reason"}
```

Restore callback results:

```gdscript
{"type": "restored"}
{"type": "no_purchases"}
{"type": "failed", "message": "reason"}
```

Manual completion methods are also available for event-based hosts:

- `Nuxie.complete_purchase(request_id, result) -> void`
- `Nuxie.complete_restore(request_id, result) -> void`

## Configuration

`options` accepts the same compact keys on Android and iOS:

| Key | Values | Default |
| --- | --- | --- |
| `environment` | `"production"`, `"development"` | `"production"` |
| `log_level` | `"verbose"`, `"debug"`, `"info"`, `"warning"`, `"error"`, `"none"` | `"warning"` |
| `enable_console_logging` | `bool` | Native default; iOS only |
| `redact_sensitive_data` | `bool` | Native default; iOS only |
| `locale_identifier` | locale string or `null` | system locale |
| `purchase_handling_mode` | `"full"`, `"observer"` | `"full"` |
| `test_store_enabled` | `bool` | `false`; iOS development builds only |

Set `use_purchase_controller` to `true` only when callbacks have been registered. The wrapper also enables it automatically when either callback is valid. Purchase delegation does not change transaction ownership; select `observer` explicitly when the app or another billing SDK owns transaction finishing.
