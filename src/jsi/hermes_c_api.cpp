/**
 * Hermes C API Implementation
 *
 * This wraps the C++ Hermes JSI API with C functions
 * so Zig can call into Hermes with zero-copy performance.
 */

#include "hermes_c_api.h"

#include <jsi/jsi/jsi.h>
#include <hermes/hermes.h>
#include <memory>
#include <string>
#include <cstring>

using namespace facebook;
using namespace facebook::jsi;
using namespace facebook::hermes;

//
// Internal Wrapper Structs
// Note: OV prefix to avoid collision with facebook::hermes::HermesRuntime
//

struct OVHermesRuntime {
    std::unique_ptr<facebook::hermes::HermesRuntime> runtime;
    std::string last_exception_message;

    OVHermesRuntime() = default;
    ~OVHermesRuntime() = default;
};

struct OVHermesValue {
    Value value;

    OVHermesValue(Value&& v) : value(std::move(v)) {}
};

struct OVHermesObject {
    Object object;

    OVHermesObject(Object&& o) : object(std::move(o)) {}
};

struct OVHermesString {
    String string;

    OVHermesString(String&& s) : string(std::move(s)) {}
};

//
// Helper: Wrap host function callback
//

struct OVHostFunctionContext {
    OVHermesHostFunction callback;
    void* user_context;
};

static Value hostFunctionWrapper(
    Runtime& rt,
    const Value& thisVal,
    const Value* args,
    size_t count
) {
    // Get the context from the function
    // Note: We'll need to store this in the function somehow
    // For now, we'll use a global map (not ideal, but works)

    // Convert args to HermesValue pointers
    std::vector<OVHermesValue*> arg_wrappers;
    arg_wrappers.reserve(count);

    for (size_t i = 0; i < count; i++) {
        // Create temporary wrapper (will be destroyed after callback)
        arg_wrappers.push_back(new OVHermesValue(Value(rt, args[i])));
    }

    // Call the user's callback
    // Note: We need to pass the context somehow
    // For now, return undefined

    // Clean up arg wrappers
    for (auto* wrapper : arg_wrappers) {
        delete wrapper;
    }

    return Value::undefined();
}

//
// Runtime Lifecycle
//

extern "C" {

OVHermesRuntime* hermes_runtime_create(void) {
    try {
        auto wrapper = new OVHermesRuntime();

        // Create Hermes runtime with default config
        wrapper->runtime = makeHermesRuntime();

        if (!wrapper->runtime) {
            delete wrapper;
            return nullptr;
        }

        return wrapper;
    } catch (...) {
        return nullptr;
    }
}

OVHermesRuntime* hermes_runtime_create_minimal(void) {
    try {
        auto wrapper = new OVHermesRuntime();

        // Create minimal runtime configuration
        ::hermes::vm::RuntimeConfig::Builder config_builder;
        config_builder.withMicrotaskQueue(false);

        wrapper->runtime = makeHermesRuntime(config_builder.build());

        if (!wrapper->runtime) {
            delete wrapper;
            return nullptr;
        }

        return wrapper;
    } catch (...) {
        return nullptr;
    }
}

void hermes_runtime_destroy(OVHermesRuntime* runtime) {
    if (runtime) {
        delete runtime;
    }
}

//
// JavaScript Execution
//

OVHermesValue* hermes_evaluate_javascript(
    OVHermesRuntime* runtime,
    const char* source,
    size_t source_len,
    const char* source_url
) {
    if (!runtime || !source) return nullptr;

    try {
        std::string source_str(source, source_len);
        std::string url = source_url ? source_url : "<eval>";

        auto buffer = std::make_shared<StringBuffer>(std::move(source_str));

        Value result = runtime->runtime->evaluateJavaScript(buffer, url);

        return new OVHermesValue(std::move(result));

    } catch (const JSError& e) {
        runtime->last_exception_message = e.what();
        return nullptr;
    } catch (const std::exception& e) {
        runtime->last_exception_message = e.what();
        return nullptr;
    }
}

OVHermesValue* hermes_evaluate_bytecode(
    OVHermesRuntime* runtime,
    const uint8_t* bytecode,
    size_t bytecode_len
) {
    if (!runtime || !bytecode) return nullptr;

    try {
        // Create a buffer from bytecode
        // Hermes automatically detects bytecode format
        std::vector<uint8_t> data(bytecode, bytecode + bytecode_len);
        auto buffer = std::make_shared<StringBuffer>(
            std::string(reinterpret_cast<const char*>(data.data()), data.size())
        );

        Value result = runtime->runtime->evaluateJavaScript(buffer, "<bytecode>");

        return new OVHermesValue(std::move(result));

    } catch (const JSError& e) {
        runtime->last_exception_message = e.what();
        return nullptr;
    } catch (const std::exception& e) {
        runtime->last_exception_message = e.what();
        return nullptr;
    }
}

bool hermes_has_exception(OVHermesRuntime* runtime) {
    return !runtime->last_exception_message.empty();
}

const char* hermes_get_exception_message(OVHermesRuntime* runtime) {
    if (runtime->last_exception_message.empty()) {
        return nullptr;
    }
    return runtime->last_exception_message.c_str();
}

//
// Host Function Registration
//

// Global map to store host function contexts
// Not ideal, but works for now. Better: use jsi::HostObject with context
static std::map<std::string, OVHostFunctionContext> g_host_function_contexts;

void hermes_register_host_function(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostFunction callback,
    void* context
) {
    if (!runtime || !name || !callback) return;

    try {
        std::string func_name(name);

        // Store context in global map
        g_host_function_contexts[func_name] = OVHostFunctionContext{
            .callback = callback,
            .user_context = context
        };

        // Create JSI host function
        auto hostFunc = Function::createFromHostFunction(
            *runtime->runtime,
            PropNameID::forAscii(*runtime->runtime, name),
            0, // parameter count (variable)
            [func_name](Runtime& rt, const Value& thisVal, const Value* args, size_t count) -> Value {
                // Get context from global map
                auto it = g_host_function_contexts.find(func_name);
                if (it == g_host_function_contexts.end()) {
                    return Value::undefined();
                }

                auto& ctx = it->second;

                // Convert args to OVHermesValue pointers
                std::vector<OVHermesValue*> arg_wrappers;
                arg_wrappers.reserve(count);

                for (size_t i = 0; i < count; i++) {
                    arg_wrappers.push_back(new OVHermesValue(Value(rt, args[i])));
                }

                // Call user callback
                OVHermesValue* result = ctx.callback(
                    nullptr, // runtime wrapper (we could pass this)
                    ctx.user_context,
                    arg_wrappers.data(),
                    count
                );

                // Clean up arg wrappers
                for (auto* wrapper : arg_wrappers) {
                    delete wrapper;
                }

                // Return result
                if (result) {
                    Value ret(rt, result->value);
                    delete result;
                    return ret;
                } else {
                    return Value::undefined();
                }
            }
        );

        // Set as global property
        runtime->runtime->global().setProperty(
            *runtime->runtime,
            name,
            std::move(hostFunc)
        );

    } catch (...) {
        // Silently fail for now
    }
}

//
// Value Operations
//

HermesValueType hermes_value_get_type(OVHermesValue* value) {
    if (!value) return HERMES_TYPE_UNDEFINED;

    if (value->value.isUndefined()) return HERMES_TYPE_UNDEFINED;
    if (value->value.isNull()) return HERMES_TYPE_NULL;
    if (value->value.isBool()) return HERMES_TYPE_BOOLEAN;
    if (value->value.isNumber()) return HERMES_TYPE_NUMBER;
    if (value->value.isString()) return HERMES_TYPE_STRING;
    if (value->value.isObject()) return HERMES_TYPE_OBJECT;

    return HERMES_TYPE_UNDEFINED;
}

bool hermes_value_is_undefined(OVHermesValue* value) {
    return value && value->value.isUndefined();
}

bool hermes_value_is_null(OVHermesValue* value) {
    return value && value->value.isNull();
}

bool hermes_value_is_boolean(OVHermesValue* value) {
    return value && value->value.isBool();
}

bool hermes_value_is_number(OVHermesValue* value) {
    return value && value->value.isNumber();
}

bool hermes_value_is_string(OVHermesValue* value) {
    return value && value->value.isString();
}

bool hermes_value_is_object(OVHermesValue* value) {
    return value && value->value.isObject();
}

bool hermes_value_get_boolean(OVHermesValue* value) {
    if (!value || !value->value.isBool()) return false;
    return value->value.getBool();
}

double hermes_value_get_number(OVHermesValue* value) {
    if (!value || !value->value.isNumber()) return 0.0;
    return value->value.getNumber();
}

// Thread-local storage for string data
thread_local std::string g_string_buffer;

const char* hermes_value_get_string(
    OVHermesRuntime* runtime,
    OVHermesValue* value,
    size_t* out_length
) {
    if (!runtime || !value || !value->value.isString()) {
        if (out_length) *out_length = 0;
        return nullptr;
    }

    try {
        String str = value->value.getString(*runtime->runtime);
        g_string_buffer = str.utf8(*runtime->runtime);

        if (out_length) {
            *out_length = g_string_buffer.length();
        }

        return g_string_buffer.c_str();

    } catch (...) {
        if (out_length) *out_length = 0;
        return nullptr;
    }
}

OVHermesValue* hermes_value_create_undefined(OVHermesRuntime* runtime) {
    if (!runtime) return nullptr;
    return new OVHermesValue(Value::undefined());
}

OVHermesValue* hermes_value_create_null(OVHermesRuntime* runtime) {
    if (!runtime) return nullptr;
    return new OVHermesValue(Value::null());
}

OVHermesValue* hermes_value_create_boolean(OVHermesRuntime* runtime, bool value) {
    if (!runtime) return nullptr;
    return new OVHermesValue(Value(value));
}

OVHermesValue* hermes_value_create_number(OVHermesRuntime* runtime, double value) {
    if (!runtime) return nullptr;
    return new OVHermesValue(Value(value));
}

OVHermesValue* hermes_value_create_string(
    OVHermesRuntime* runtime,
    const char* str,
    size_t length
) {
    if (!runtime || !str) return nullptr;

    try {
        std::string s(str, length);
        String jsi_str = String::createFromUtf8(*runtime->runtime, s);
        return new OVHermesValue(Value(*runtime->runtime, jsi_str));
    } catch (...) {
        return nullptr;
    }
}

void hermes_value_destroy(OVHermesValue* value) {
    if (value) {
        delete value;
    }
}

//
// Utility Functions
//

const char* hermes_get_version(void) {
    return "Hermes 0.12.0"; // TODO: Get actual version
}

bool hermes_is_bytecode(const uint8_t* data, size_t len) {
    if (!data || len < 8) return false;

    try {
        auto rootAPI = makeHermesRootAPI();
        auto hermesRootAPI = dynamic_cast<IHermesRootAPI*>(rootAPI);
        if (!hermesRootAPI) return false;

        return hermesRootAPI->isHermesBytecode(data, len);
    } catch (...) {
        return false;
    }
}

} // extern "C"
