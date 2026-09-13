class_name NuxieOptions
extends Resource

enum EnvironmentKind { PRODUCTION, DEVELOPMENT }
enum LogLevel { WARNING, DEBUG, INFO, ERROR, NONE, VERBOSE }

@export var ios_api_key: String = ""
@export var android_api_key: String = ""
@export var environment: EnvironmentKind = EnvironmentKind.PRODUCTION
@export var log_level: LogLevel = LogLevel.WARNING
@export var locale: String = ""
var billing: NuxieBilling = NuxieBilling.new()
