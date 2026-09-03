#include "core/config/engine.h"
#include "core/io/json.h"
#include "core/object/class_db.h"

#include <cstdint>

extern "C" {
char *NuxieGodot_Invoke(const char *p_method, const char *p_arguments);
int32_t NuxieGodot_GetPendingEventCount();
char *NuxieGodot_PopPendingEvent();
void NuxieGodot_FreeCString(char *p_value);
void NuxieGodot_Shutdown();
}

class NuxieGodotPlugin : public Object {
	GDCLASS(NuxieGodotPlugin, Object);

	static void _bind_methods();

	void _invoke(const String &p_method, const Dictionary &p_arguments) const;

public:
	void configure(String p_api_key, Dictionary p_options, bool p_use_purchase_controller, String p_wrapper_version, String p_request_id);
	void shutdown(String p_request_id);
	void identify(String p_distinct_id, Dictionary p_user_properties, Dictionary p_user_properties_set_once, String p_request_id);
	void reset(bool p_keep_anonymous_id, String p_request_id);
	void get_distinct_id(String p_request_id);
	void get_anonymous_id(String p_request_id);
	void get_is_identified(String p_request_id);
	void trigger(String p_event_name, Dictionary p_properties);
	void dismiss(String p_request_id);
	void set_locale_identifier(Variant p_locale_identifier, String p_request_id);
	void has_feature(String p_feature_id, double p_required_balance, String p_entity_id, String p_policy, String p_request_id);
	void use_feature(String p_feature_id, double p_amount, String p_entity_id, Dictionary p_metadata);
	void use_feature_and_wait(String p_feature_id, double p_amount, String p_entity_id, bool p_set_usage, Dictionary p_metadata, String p_request_id);
	void complete_purchase(String p_request_id, Dictionary p_result);
	void complete_restore(String p_request_id, Dictionary p_result);
	int get_pending_event_count() const;
	Variant pop_pending_event() const;
};

void NuxieGodotPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "apiKey", "options", "usePurchaseController", "wrapperVersion", "requestId"), &NuxieGodotPlugin::configure);
	ClassDB::bind_method(D_METHOD("shutdown", "requestId"), &NuxieGodotPlugin::shutdown);
	ClassDB::bind_method(D_METHOD("identify", "distinctId", "userProperties", "userPropertiesSetOnce", "requestId"), &NuxieGodotPlugin::identify);
	ClassDB::bind_method(D_METHOD("reset", "keepAnonymousId", "requestId"), &NuxieGodotPlugin::reset);
	ClassDB::bind_method(D_METHOD("getDistinctId", "requestId"), &NuxieGodotPlugin::get_distinct_id);
	ClassDB::bind_method(D_METHOD("getAnonymousId", "requestId"), &NuxieGodotPlugin::get_anonymous_id);
	ClassDB::bind_method(D_METHOD("getIsIdentified", "requestId"), &NuxieGodotPlugin::get_is_identified);
	ClassDB::bind_method(D_METHOD("trigger", "eventName", "properties"), &NuxieGodotPlugin::trigger);
	ClassDB::bind_method(D_METHOD("dismiss", "requestId"), &NuxieGodotPlugin::dismiss);
	ClassDB::bind_method(D_METHOD("setLocaleIdentifier", "localeIdentifier", "requestId"), &NuxieGodotPlugin::set_locale_identifier);
	ClassDB::bind_method(D_METHOD("hasFeature", "featureId", "requiredBalance", "entityId", "policy", "requestId"), &NuxieGodotPlugin::has_feature);
	ClassDB::bind_method(D_METHOD("useFeature", "featureId", "amount", "entityId", "metadata"), &NuxieGodotPlugin::use_feature);
	ClassDB::bind_method(D_METHOD("useFeatureAndWait", "featureId", "amount", "entityId", "setUsage", "metadata", "requestId"), &NuxieGodotPlugin::use_feature_and_wait);
	ClassDB::bind_method(D_METHOD("completePurchase", "requestId", "result"), &NuxieGodotPlugin::complete_purchase);
	ClassDB::bind_method(D_METHOD("completeRestore", "requestId", "result"), &NuxieGodotPlugin::complete_restore);
	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &NuxieGodotPlugin::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &NuxieGodotPlugin::pop_pending_event);
}

void NuxieGodotPlugin::_invoke(const String &p_method, const Dictionary &p_arguments) const {
	const CharString method = p_method.utf8();
	const CharString arguments = JSON::stringify(p_arguments).utf8();
	char *response = NuxieGodot_Invoke(method.get_data(), arguments.get_data());
	NuxieGodot_FreeCString(response);
}

void NuxieGodotPlugin::configure(String p_api_key, Dictionary p_options, bool p_use_purchase_controller, String p_wrapper_version, String p_request_id) {
	Dictionary arguments;
	arguments["apiKey"] = p_api_key;
	arguments["options"] = p_options;
	arguments["usePurchaseController"] = p_use_purchase_controller;
	arguments["wrapperVersion"] = p_wrapper_version;
	arguments["requestId"] = p_request_id;
	_invoke("configure", arguments);
}

void NuxieGodotPlugin::shutdown(String p_request_id) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	_invoke("shutdown", arguments);
}

void NuxieGodotPlugin::identify(String p_distinct_id, Dictionary p_user_properties, Dictionary p_user_properties_set_once, String p_request_id) {
	Dictionary arguments;
	arguments["distinctId"] = p_distinct_id;
	arguments["userProperties"] = p_user_properties;
	arguments["userPropertiesSetOnce"] = p_user_properties_set_once;
	arguments["requestId"] = p_request_id;
	_invoke("identify", arguments);
}

void NuxieGodotPlugin::reset(bool p_keep_anonymous_id, String p_request_id) {
	Dictionary arguments;
	arguments["keepAnonymousId"] = p_keep_anonymous_id;
	arguments["requestId"] = p_request_id;
	_invoke("reset", arguments);
}

void NuxieGodotPlugin::get_distinct_id(String p_request_id) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	_invoke("getDistinctId", arguments);
}

void NuxieGodotPlugin::get_anonymous_id(String p_request_id) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	_invoke("getAnonymousId", arguments);
}

void NuxieGodotPlugin::get_is_identified(String p_request_id) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	_invoke("getIsIdentified", arguments);
}

void NuxieGodotPlugin::trigger(String p_event_name, Dictionary p_properties) {
	Dictionary arguments;
	arguments["eventName"] = p_event_name;
	arguments["properties"] = p_properties;
	_invoke("trigger", arguments);
}

void NuxieGodotPlugin::dismiss(String p_request_id) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	_invoke("dismiss", arguments);
}

void NuxieGodotPlugin::set_locale_identifier(Variant p_locale_identifier, String p_request_id) {
	Dictionary arguments;
	arguments["localeIdentifier"] = p_locale_identifier;
	arguments["requestId"] = p_request_id;
	_invoke("setLocaleIdentifier", arguments);
}

void NuxieGodotPlugin::has_feature(String p_feature_id, double p_required_balance, String p_entity_id, String p_policy, String p_request_id) {
	Dictionary arguments;
	arguments["featureId"] = p_feature_id;
	arguments["requiredBalance"] = p_required_balance;
	arguments["entityId"] = p_entity_id;
	arguments["policy"] = p_policy;
	arguments["requestId"] = p_request_id;
	_invoke("hasFeature", arguments);
}

void NuxieGodotPlugin::use_feature(String p_feature_id, double p_amount, String p_entity_id, Dictionary p_metadata) {
	Dictionary arguments;
	arguments["featureId"] = p_feature_id;
	arguments["amount"] = p_amount;
	arguments["entityId"] = p_entity_id;
	arguments["metadata"] = p_metadata;
	_invoke("useFeature", arguments);
}

void NuxieGodotPlugin::use_feature_and_wait(String p_feature_id, double p_amount, String p_entity_id, bool p_set_usage, Dictionary p_metadata, String p_request_id) {
	Dictionary arguments;
	arguments["featureId"] = p_feature_id;
	arguments["amount"] = p_amount;
	arguments["entityId"] = p_entity_id;
	arguments["setUsage"] = p_set_usage;
	arguments["metadata"] = p_metadata;
	arguments["requestId"] = p_request_id;
	_invoke("useFeatureAndWait", arguments);
}

void NuxieGodotPlugin::complete_purchase(String p_request_id, Dictionary p_result) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	arguments["result"] = p_result;
	_invoke("completePurchase", arguments);
}

void NuxieGodotPlugin::complete_restore(String p_request_id, Dictionary p_result) {
	Dictionary arguments;
	arguments["requestId"] = p_request_id;
	arguments["result"] = p_result;
	_invoke("completeRestore", arguments);
}

int NuxieGodotPlugin::get_pending_event_count() const {
	return static_cast<int>(NuxieGodot_GetPendingEventCount());
}

Variant NuxieGodotPlugin::pop_pending_event() const {
	char *event = NuxieGodot_PopPendingEvent();
	if (event == nullptr) {
		return Variant();
	}

	const Variant parsed = JSON::parse_string(String::utf8(event));
	NuxieGodot_FreeCString(event);
	return parsed;
}

static NuxieGodotPlugin *nuxie_godot_singleton = nullptr;

__attribute__((visibility("default"))) void nuxie_godot_init() {
	if (nuxie_godot_singleton != nullptr) {
		return;
	}

	nuxie_godot_singleton = memnew(NuxieGodotPlugin);
	Engine::get_singleton()->add_singleton(Engine::Singleton("NuxieGodot", nuxie_godot_singleton));
}

__attribute__((visibility("default"))) void nuxie_godot_deinit() {
	if (nuxie_godot_singleton == nullptr) {
		return;
	}

	Engine::get_singleton()->remove_singleton("NuxieGodot");
	NuxieGodot_Shutdown();
	memdelete(nuxie_godot_singleton);
	nuxie_godot_singleton = nullptr;
}
