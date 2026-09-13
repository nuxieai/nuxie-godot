class_name NuxieFeatureQuery
extends RefCounted

enum Policy { CACHE_FIRST, REMOTE }
var entity_id: String = ""
var required_balance: int = 1
var policy: Policy = Policy.CACHE_FIRST
