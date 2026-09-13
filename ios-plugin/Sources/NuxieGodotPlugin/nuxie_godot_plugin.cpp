#include "core/config/engine.h"
#include "core/object/class_db.h"

extern "C" {
void NuxieGodot_Dispatch(const char *message);
char *NuxieGodot_PopMessage();
void NuxieGodot_FreeCString(char *message);
void NuxieGodot_Detach();
}

class NuxieGodotPlugin : public Object {
    GDCLASS(NuxieGodotPlugin, Object);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("dispatch", "message"), &NuxieGodotPlugin::dispatch);
        ClassDB::bind_method(D_METHOD("pop_message"), &NuxieGodotPlugin::pop_message);
    }
public:
    void dispatch(const String &message) { NuxieGodot_Dispatch(message.utf8().get_data()); }
    String pop_message() {
        char *message = NuxieGodot_PopMessage();
        if (!message) return String();
        String result = String::utf8(message);
        NuxieGodot_FreeCString(message);
        return result;
    }
};

static NuxieGodotPlugin *instance = nullptr;
__attribute__((visibility("default"))) void nuxie_godot_init() {
    if (instance) return;
    instance = memnew(NuxieGodotPlugin);
    Engine::get_singleton()->add_singleton(Engine::Singleton("NuxieGodot", instance));
}
__attribute__((visibility("default"))) void nuxie_godot_deinit() {
    if (!instance) return;
    Engine::get_singleton()->remove_singleton("NuxieGodot");
    NuxieGodot_Detach();
    memdelete(instance);
    instance = nullptr;
}
