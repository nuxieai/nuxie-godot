# Nuxie Godot API Reference

This document describes the public GDScript surface in `addons/nuxie/nuxie.gd` and the normalized event/payload contract emitted by native bridges.

## Facade class

- Class: `Nuxie`
- Type: static facade (`class_name Nuxie`)
- Native singleton target: `NuxieGodot`

## Return shape for async operations

Most async methods resolve to:

```gdscript
{
  "ok": bool,
  "result": Dictionary,
  "error": Dictionary # { code, message, nativeStack? }
}
```

## Core methods

| Method | Returns | Notes |
| --- | --- | --- |
| `Nuxie.is_available()` | `bool` | Checks native singleton availability. |
| `Nuxie.set_purchase_controller(on_purchase, on_restore)` | `void` | Registers optional purchase/restore handlers. |
| `Nuxie.on(event_name, callback)` | `void` | Subscribes to facade event stream. |
| `Nuxie.off(event_name, callback)` | `void` | Unsubscribes callback. |
| `Nuxie.configure(api_key, options := {}, use_purchase_controller := false)` | `Dictionary` | Initializes native SDK. |
| `Nuxie.shutdown()` | `Dictionary` | Shuts down SDK and clears pending state. |

## Identity methods

| Method | Returns |
| --- | --- |
| `Nuxie.identify(distinct_id, user_properties := {}, user_properties_set_once := {})` | `Dictionary` |
| `Nuxie.reset(keep_anonymous_id := true)` | `Dictionary` |
| `Nuxie.get_distinct_id()` | `String` |
| `Nuxie.get_anonymous_id()` | `String` |
| `Nuxie.get_is_identified()` | `bool` |

`get_*` helpers return fallback values on error and emit normalized engine errors through `NuxieErrors.emit`.

## Trigger methods

| Method | Returns | Notes |
| --- | --- | --- |
| `Nuxie.trigger(event_name, options := {})` | `NuxieTriggerOperation` | Starts progressive trigger stream. |
| `Nuxie.trigger_once(event_name, options := {}, timeout_ms := 0)` | `Dictionary` | Waits for terminal trigger update. |
| `Nuxie.cancel_trigger(request_id)` | `void` | Cancels in-flight native trigger handle. |

Trigger `options` keys:

- `properties: Dictionary`
- `userProperties: Dictionary`
- `userPropertiesSetOnce: Dictionary`

## Flow, profile, and feature methods

| Method | Returns |
| --- | --- |
| `Nuxie.show_flow(flow_id)` | `Dictionary` |
| `Nuxie.refresh_profile()` | `Dictionary` |
| `Nuxie.has_feature(feature_id, required_balance := -1, entity_id := "")` | `Dictionary` |
| `Nuxie.get_cached_feature(feature_id, entity_id := "")` | `Dictionary` |
| `Nuxie.check_feature(feature_id, required_balance := -1, entity_id := "")` | `Dictionary` |
| `Nuxie.refresh_feature(feature_id, required_balance := -1, entity_id := "")` | `Dictionary` |
| `Nuxie.use_feature(feature_id, amount := 1.0, entity_id := "", metadata := {})` | `Dictionary` |
| `Nuxie.use_feature_and_wait(feature_id, amount := 1.0, entity_id := "", set_usage := false, metadata := {})` | `Dictionary` |

`show_flow(...)` automatically supports native permission actions authored in
flows, including notifications, tracking, camera, microphone, photos, and
foreground location, as long as the exported mobile projects include the
matching native plist/manifest declarations.

## Event queue methods

| Method | Returns |
| --- | --- |
| `Nuxie.flush_events()` | `Dictionary` |
| `Nuxie.get_queued_event_count()` | `Dictionary` |
| `Nuxie.pause_event_queue()` | `Dictionary` |
| `Nuxie.resume_event_queue()` | `Dictionary` |

## Purchase/restore completion methods

| Method | Returns |
| --- | --- |
| `Nuxie.complete_purchase(request_id, result)` | `Dictionary` |
| `Nuxie.complete_restore(request_id, result)` | `Dictionary` |

## Emitted events

The facade emits callbacks registered with `Nuxie.on(...)`.

### `operation_result`

```gdscript
{
  "requestId": String,
  "method": String,
  "ok": bool,
  "result": Dictionary,
  "error": Dictionary,
  "timestampMs": int
}
```

### `trigger_update`

```gdscript
{
  "requestId": String,
  "update": Dictionary,
  "isTerminal": bool,
  "timestampMs": int
}
```

### `feature_access_changed`

```gdscript
{
  "featureId": String,
  "from": Dictionary,
  "to": Dictionary,
  "timestampMs": int
}
```

### `purchase_request`

```gdscript
{
  "requestId": String,
  "platform": "ios" | "android",
  "productId": String, # purchase only
  "displayName": String, # optional
  "displayPrice": String, # optional
  "price": float, # optional
  "timestampMs": int
}
```

### `restore_request`

```gdscript
{
  "requestId": String,
  "platform": "ios" | "android",
  "timestampMs": int
}
```

### `flow_lifecycle`

```gdscript
{
  "type": String,
  "timestampMs": int,
  "flowId": String, # optional
  "reason": String, # optional
  "payload": Dictionary # optional, event-specific fields
}
```

## Trigger update contract

Update kinds:

- `decision`
- `entitlement`
- `journey`
- `error`

Decision `type` values:

- `no_match`
- `allowed_immediate`
- `denied_immediate`
- `journey_started`
- `journey_resumed`
- `flow_shown`
- `suppressed`

Entitlement `type` values:

- `pending`
- `allowed`
- `denied`

Terminal rules:

- Terminal:
- `error`
- `journey`
- `decision.no_match`
- `decision.allowed_immediate`
- `decision.denied_immediate`
- `decision.suppressed`
- `entitlement.allowed`
- `entitlement.denied`
- Non-terminal:
- `decision.journey_started`
- `decision.journey_resumed`
- `decision.flow_shown`
- `entitlement.pending`

## Purchase/restore completion payloads

Purchase completion payload (`Nuxie.complete_purchase`):

```gdscript
{ "type": "success", "productId": "pro_monthly", ... }
{ "type": "cancelled" }
{ "type": "pending" }
{ "type": "failed", "message": "purchase_failed_reason" }
```

Restore completion payload (`Nuxie.complete_restore`):

```gdscript
{ "type": "success", "restoredCount": 2 }
{ "type": "no_purchases" }
{ "type": "failed", "message": "restore_failed_reason" }
```

## Configure option keys

`Nuxie.configure(api_key, options, ...)` supports these keys:

- `environment`: `production | staging | development | custom`
- `apiEndpoint`
- `logLevel`: `verbose | debug | info | warning | error | none`
- `enableConsoleLogging`
- `enableFileLogging`
- `redactSensitiveData`
- `requestTimeoutSeconds`
- `retryCount`
- `retryDelaySeconds`
- `syncIntervalSeconds`
- `enableCompression`
- `eventBatchSize`
- `flushAt`
- `flushIntervalSeconds`
- `maxQueueSize`
- `maxCacheSizeBytes`
- `cacheExpirationSeconds`
- `enableEncryption`
- `featureCacheTtlSeconds`
- `defaultPaywallTimeoutSeconds`
- `respectDoNotTrack`
- `localeIdentifier`
- `isDebugMode`
- `enablePlugins`
- `maxFlowCacheSizeBytes`
- `flowCacheExpirationSeconds`
- `maxConcurrentFlowDownloads`
- `flowDownloadTimeoutSeconds`
- `customStoragePath`
- `flowCacheDirectory`
- `eventLinkingPolicy`: `keep_separate | keepSeparate | migrate_on_identify(default)`
- `purchaseTimeoutSeconds`
