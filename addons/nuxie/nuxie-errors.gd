class_name NuxieErrors
extends RefCounted

static func build(code: String, message: String, native_stack: String = "") -> Dictionary:
  var error := {
    "code": code,
    "message": message,
  }
  if native_stack != "":
    error["nativeStack"] = native_stack
  return error

static func normalize(raw_error: Variant, fallback_code: String = "NATIVE_ERROR", fallback_message: String = "Unknown native error") -> Dictionary:
  if raw_error is Dictionary:
    var dictionary := raw_error as Dictionary
    if dictionary.has("code") and dictionary.has("message"):
      return dictionary

    return build(
      str(dictionary.get("code", fallback_code)),
      str(dictionary.get("message", fallback_message)),
      str(dictionary.get("nativeStack", "")),
    )

  if raw_error is String:
    return build(fallback_code, raw_error)

  return build(fallback_code, fallback_message)

static func emit(operation: String, error: Variant) -> void:
  var normalized := normalize(error)
  push_error("[Nuxie][%s] %s (%s)" % [operation, normalized.get("message", "error"), normalized.get("code", "NATIVE_ERROR")])
