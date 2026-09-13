class_name NuxieFeatureState
extends RefCounted

enum Kind { UNKNOWN, RECONCILING, READY }
var kind: Kind = Kind.UNKNOWN
var access: NuxieFeatureAccess
