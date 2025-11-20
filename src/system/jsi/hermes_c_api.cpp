/**
 * Hermes C API Implementation
 *
 * This wraps the C++ Hermes JSI API with C functions
 * so Zig can call into Hermes with zero-copy performance.
 */

#include "hermes_c_api.h"

#include <jsi/jsi/jsi.h>
#include <hermes/hermes.h>
#include <hermes/cdp/CDPDebugAPI.h>
#include <hermes/cdp/CDPAgent.h>
#include <hermes/cdp/ConsoleMessage.h>
#include <memory>
#include <string>
#include <cstring>
#include <chrono>

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

    // Error throwing support (Phase 4)
    bool pending_throw;          // True if host function wants to throw
    std::string pending_throw_message;  // Error message
    std::string pending_throw_type;     // "Error", "TypeError", "RangeError", etc.

    OVHermesRuntime() : pending_throw(false), pending_throw_type("Error") {}
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
// ExternalMutableBuffer - Wraps native memory for zero-copy ArrayBuffer
// React Native pattern: Used for realtime camera frames, large buffers
//

class ExternalMutableBuffer : public jsi::MutableBuffer {
private:
    uint8_t* data_;
    size_t size_;
    OVHermesArrayBufferFinalizer finalizer_;
    void* finalizer_ctx_;

public:
    ExternalMutableBuffer(
        uint8_t* data,
        size_t size,
        OVHermesArrayBufferFinalizer finalizer,
        void* finalizer_ctx
    ) : data_(data),
        size_(size),
        finalizer_(finalizer),
        finalizer_ctx_(finalizer_ctx) {}

    ~ExternalMutableBuffer() override {
        // Call finalizer when JavaScript garbage collects the ArrayBuffer
        if (finalizer_) {
            finalizer_(data_, finalizer_ctx_);
        }
    }

    size_t size() const override {
        return size_;
    }

    uint8_t* data() override {
        return data_;
    }
};

//
// Helper: Wrap host function callback
//

struct OVHostFunctionContext {
    OVHermesRuntime* runtime;
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

void hermes_throw_error(OVHermesRuntime* runtime, const char* message) {
    if (!runtime || !message) return;

    // Set pending throw flag and message
    runtime->pending_throw = true;
    runtime->pending_throw_message = std::string(message);
    runtime->pending_throw_type = "Error";
}

void hermes_throw_type_error(OVHermesRuntime* runtime, const char* message) {
    if (!runtime || !message) return;

    // Set pending throw flag and message
    runtime->pending_throw = true;
    runtime->pending_throw_message = std::string(message);
    runtime->pending_throw_type = "TypeError";
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
            .runtime = runtime,
            .callback = callback,
            .user_context = context
        };

        // Create JSI host function
        auto hostFunc = Function::createFromHostFunction(
            *runtime->runtime,
            PropNameID::forAscii(*runtime->runtime, name),
            0, // parameter count (variable)
            [func_name = func_name](Runtime& rt, const Value& thisVal, const Value* args, size_t count) -> Value {
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
                    ctx.runtime, // Pass the runtime wrapper
                    ctx.user_context,
                    arg_wrappers.data(),
                    count
                );

                // Clean up arg wrappers
                for (auto* wrapper : arg_wrappers) {
                    delete wrapper;
                }

                // Check if callback requested throw (Phase 4 - Error Throwing)
                if (ctx.runtime->pending_throw) {
                    ctx.runtime->pending_throw = false;  // Reset flag

                    try {
                        // Get Error constructor (Error, TypeError, etc.)
                        auto ErrorCtor = rt.global().getPropertyAsFunction(rt,
                            ctx.runtime->pending_throw_type.c_str());

                        // Create Error object with message
                        auto error = ErrorCtor.callAsConstructor(rt,
                            String::createFromUtf8(rt, ctx.runtime->pending_throw_message));

                        // Throw JSError (propagates to JavaScript)
                        throw JSError(rt, std::move(error));
                    } catch (const JSError&) {
                        // Re-throw JSError
                        throw;
                    } catch (...) {
                        // Fallback: throw generic error if constructor failed
                        throw JSError(rt, String::createFromUtf8(rt, ctx.runtime->pending_throw_message));
                    }
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
// HostObject Support (for zero-copy JSI)
//

// CustomHostObject implementation - wraps Zig callbacks into JSI HostObject
class CustomHostObject : public HostObject {
private:
    // Callback signatures matching Zig functions
    using GetterCallback = OVHermesValue* (*)(
        OVHermesRuntime* runtime,
        void* context,
        const char* prop_name
    );

    using SetterCallback = OVHermesValue* (*)(
        OVHermesRuntime* runtime,
        void* context,
        const char* prop_name,
        OVHermesValue* value
    );

    using EnumeratorCallback = OVHermesValue* (*)(
        OVHermesRuntime* runtime,
        void* context
    );

    OVHermesRuntime* runtime_;
    GetterCallback getter_;
    SetterCallback setter_;
    EnumeratorCallback enumerator_;
    void* context_;
    std::string name_;

public:
    CustomHostObject(
        OVHermesRuntime* runtime,
        const std::string& name,
        GetterCallback getter,
        SetterCallback setter,
        EnumeratorCallback enumerator,
        void* context
    ) : runtime_(runtime),
        getter_(getter),
        setter_(setter),
        enumerator_(enumerator),
        context_(context),
        name_(name) {}

    ~CustomHostObject() override {
        // Destructor may be called on arbitrary thread by GC
        // Ensure thread-safe cleanup if needed
    }

    Value get(Runtime& rt, const PropNameID& name) override {
        if (!getter_) {
            return Value::undefined();
        }

        try {
            std::string prop_name = name.utf8(rt);

            // Call Zig getter callback
            OVHermesValue* result = getter_(runtime_, context_, prop_name.c_str());

            if (result) {
                Value ret(rt, result->value);
                delete result;
                return ret;
            } else {
                return Value::undefined();
            }
        } catch (...) {
            return Value::undefined();
        }
    }

    void set(Runtime& rt, const PropNameID& name, const Value& value) override {
        if (!setter_) {
            // Property is read-only
            return;
        }

        try {
            std::string prop_name = name.utf8(rt);
            OVHermesValue value_wrapper(Value(rt, value));

            // Call Zig setter callback
            OVHermesValue* result = setter_(runtime_, context_, prop_name.c_str(), &value_wrapper);

            if (result) {
                delete result;
            }
        } catch (...) {
            // Silently ignore errors
        }
    }

    std::vector<PropNameID> getPropertyNames(Runtime& rt) override {
        std::vector<PropNameID> props;

        if (!enumerator_) {
            return props;
        }

        try {
            // Call Zig enumerator callback to get array of property names
            OVHermesValue* result = enumerator_(runtime_, context_);

            if (result && result->value.isObject()) {
                Object obj = result->value.asObject(rt);

                if (obj.isArray(rt)) {
                    Array arr = obj.getArray(rt);
                    size_t len = arr.size(rt);

                    for (size_t i = 0; i < len; i++) {
                        Value val = arr.getValueAtIndex(rt, i);
                        if (val.isString()) {
                            std::string prop = val.getString(rt).utf8(rt);
                            props.push_back(PropNameID::forUtf8(rt, prop));
                        }
                    }
                }

                delete result;
            }
        } catch (...) {
            // Return empty array on error
        }

        return props;
    }
};

// C API for creating function values (used by HostObject getter)
OVHermesValue* hermes_create_function(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostFunction callback,
    void* context
) {
    if (!runtime || !name || !callback) return nullptr;

    try {
        std::string func_name(name);

        // Store context in global map (same as hermes_register_host_function)
        g_host_function_contexts[func_name] = OVHostFunctionContext{
            .runtime = runtime,
            .callback = callback,
            .user_context = context
        };

        // Create JSI Function object (not registered globally)
        auto hostFunc = Function::createFromHostFunction(
            *runtime->runtime,
            PropNameID::forAscii(*runtime->runtime, name),
            0,
            [func_name = func_name](Runtime& rt, const Value& thisVal, const Value* args, size_t count) -> Value {
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
                    ctx.runtime,
                    ctx.user_context,
                    arg_wrappers.data(),
                    count
                );

                // Clean up arg wrappers
                for (auto* wrapper : arg_wrappers) {
                    delete wrapper;
                }

                // Check if callback requested throw (Phase 4 - Error Throwing)
                if (ctx.runtime->pending_throw) {
                    ctx.runtime->pending_throw = false;  // Reset flag

                    try {
                        // Get Error constructor (Error, TypeError, etc.)
                        auto ErrorCtor = rt.global().getPropertyAsFunction(rt,
                            ctx.runtime->pending_throw_type.c_str());

                        // Create Error object with message
                        auto error = ErrorCtor.callAsConstructor(rt,
                            String::createFromUtf8(rt, ctx.runtime->pending_throw_message));

                        // Throw JSError (propagates to JavaScript)
                        throw JSError(rt, std::move(error));
                    } catch (const JSError&) {
                        // Re-throw JSError
                        throw;
                    } catch (...) {
                        // Fallback: throw generic error if constructor failed
                        throw JSError(rt, String::createFromUtf8(rt, ctx.runtime->pending_throw_message));
                    }
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

        return new OVHermesValue(Value(*runtime->runtime, std::move(hostFunc)));
    } catch (...) {
        return nullptr;
    }
}

// C API for registering HostObject
void hermes_register_host_object(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostObjectGet getter,
    OVHermesHostObjectSet setter,
    OVHermesHostObjectEnumerator enumerator,
    void* context
) {
    if (!runtime || !name || !getter) return;

    try {
        std::string obj_name(name);

        // Create CustomHostObject
        auto hostObject = std::make_shared<CustomHostObject>(
            runtime,
            obj_name,
            getter,
            setter,
            enumerator,
            context
        );

        // Register as global property
        runtime->runtime->global().setProperty(
            *runtime->runtime,
            name,
            Object::createFromHostObject(*runtime->runtime, hostObject)
        );
    } catch (...) {
        // Silently fail
    }
}

//
// Array Operations (for HostObject enumerator)
//

OVHermesValue* hermes_array_create(OVHermesRuntime* runtime, size_t length) {
    if (!runtime) return nullptr;

    try {
        Array arr = Array(*runtime->runtime, length);
        return new OVHermesValue(Value(*runtime->runtime, std::move(arr)));
    } catch (...) {
        return nullptr;
    }
}

void hermes_array_set(
    OVHermesRuntime* runtime,
    OVHermesValue* array,
    size_t index,
    OVHermesValue* value
) {
    if (!runtime || !array || !value) return;

    try {
        if (!array->value.isObject()) return;

        Object obj = array->value.asObject(*runtime->runtime);
        if (!obj.isArray(*runtime->runtime)) return;

        Array arr = obj.getArray(*runtime->runtime);
        arr.setValueAtIndex(*runtime->runtime, index, Value(*runtime->runtime, value->value));
    } catch (...) {
        // Silently ignore errors
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

bool hermes_value_is_function(OVHermesRuntime* runtime, OVHermesValue* value) {
    if (!runtime || !value || !value->value.isObject()) {
        return false;
    }
    try {
        return value->value.asObject(*runtime->runtime).isFunction(*runtime->runtime);
    } catch (...) {
        return false;
    }
}

OVHermesValue* hermes_call_function(
    OVHermesRuntime* runtime,
    OVHermesValue* function,
    OVHermesValue** args,
    size_t arg_count
) {
    if (!runtime || !function) {
        return nullptr;
    }

    try {
        Runtime& rt = *runtime->runtime;

        // Convert function value to Function object
        if (!function->value.isObject() || !function->value.asObject(rt).isFunction(rt)) {
            return nullptr;
        }

        Function func = function->value.asObject(rt).getFunction(rt);

        // Call the function with proper argument handling
        Value result = Value::undefined();

        if (args && arg_count > 0) {
            // Create arguments array
            std::vector<Value> argValues;
            argValues.reserve(arg_count);

            for (size_t i = 0; i < arg_count; i++) {
                if (args[i]) {
                    argValues.emplace_back(Value(rt, args[i]->value));
                } else {
                    argValues.emplace_back(Value::undefined());
                }
            }

            // Call with pointer to vector data
            // IMPORTANT: Cast to const Value* to select the correct overload
            // Otherwise variadic template overload is selected
            result = func.call(rt, static_cast<const Value*>(argValues.data()), static_cast<size_t>(argValues.size()));
        } else {
            // No arguments - call with nullptr
            result = func.call(rt, nullptr, 0);
        }

        return new OVHermesValue(std::move(result));
    } catch (const facebook::jsi::JSIException& e) {
        runtime->last_exception_message = e.what();
        return nullptr;
    } catch (...) {
        runtime->last_exception_message = "Unknown error calling function";
        return nullptr;
    }
}

OVHermesValue* hermes_value_clone(OVHermesRuntime* runtime, OVHermesValue* value) {
    if (!runtime || !value) {
        return nullptr;
    }

    // Create a new Value by copying from the existing one
    return new OVHermesValue(Value(*runtime->runtime, value->value));
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

OVHermesValue* hermes_value_create_object(OVHermesRuntime* runtime) {
    if (!runtime) return nullptr;

    try {
        Object obj(*runtime->runtime);
        return new OVHermesValue(Value(*runtime->runtime, std::move(obj)));
    } catch (...) {
        return nullptr;
    }
}

//
// ArrayBuffer Support (Zero-Copy External Memory)
//

// Helper to access protected Runtime::createArrayBuffer method
// This uses a standard C++ pattern to expose protected methods when needed
namespace {
    struct RuntimeHelper : public Runtime {
        ArrayBuffer createArrayBufferPublic(std::shared_ptr<MutableBuffer> buffer) {
            // Call protected createArrayBuffer method
            return this->createArrayBuffer(std::move(buffer));
        }
    };
}

OVHermesValue* hermes_value_create_arraybuffer_external(
    OVHermesRuntime* runtime,
    void* data,
    size_t size,
    OVHermesArrayBufferFinalizer finalizer,
    void* finalizer_ctx
) {
    if (!runtime || !data) return nullptr;

    try {
        // Create ExternalMutableBuffer wrapping native memory
        auto buffer = std::make_shared<ExternalMutableBuffer>(
            static_cast<uint8_t*>(data),
            size,
            finalizer,
            finalizer_ctx
        );

        // Access protected createArrayBuffer via helper pattern
        // This is zero-copy: JavaScript sees native memory directly
        Runtime* rt_ptr = runtime->runtime.get();
        auto arraybuffer = static_cast<RuntimeHelper*>(rt_ptr)->createArrayBufferPublic(std::move(buffer));

        return new OVHermesValue(Value(*runtime->runtime, std::move(arraybuffer)));
    } catch (...) {
        return nullptr;
    }
}

bool hermes_value_get_arraybuffer_data(
    OVHermesRuntime* runtime,
    OVHermesValue* arraybuffer,
    void** out_data,
    size_t* out_size
) {
    if (!runtime || !arraybuffer || !out_data || !out_size) {
        return false;
    }

    try {
        // Check if value is an object
        if (!arraybuffer->value.isObject()) {
            return false;
        }

        Object obj = arraybuffer->value.asObject(*runtime->runtime);

        // Check if object is ArrayBuffer
        if (!obj.isArrayBuffer(*runtime->runtime)) {
            return false;
        }

        // Get ArrayBuffer
        ArrayBuffer ab = obj.getArrayBuffer(*runtime->runtime);

        // Get data pointer and size
        *out_data = ab.data(*runtime->runtime);
        *out_size = ab.size(*runtime->runtime);

        return true;
    } catch (...) {
        return false;
    }
}

void hermes_value_destroy(OVHermesValue* value) {
    if (value) {
        delete value;
    }
}

//
// Global Object Access
//

OVHermesObject* hermes_get_global_object(OVHermesRuntime* runtime) {
    if (!runtime) return nullptr;

    try {
        Object global = runtime->runtime->global();
        return new OVHermesObject(std::move(global));
    } catch (...) {
        return nullptr;
    }
}

void hermes_object_destroy(OVHermesObject* object) {
    if (object) {
        delete object;
    }
}

OVHermesValue* hermes_object_get_property(
    OVHermesRuntime* runtime,
    OVHermesObject* object,
    const char* property_name
) {
    if (!runtime || !object || !property_name) return nullptr;

    try {
        Value value = object->object.getProperty(*runtime->runtime, property_name);
        return new OVHermesValue(std::move(value));
    } catch (...) {
        return nullptr;
    }
}

void hermes_object_set_property(
    OVHermesRuntime* runtime,
    OVHermesObject* object,
    const char* property_name,
    OVHermesValue* value
) {
    if (!runtime || !object || !property_name || !value) return;

    try {
        object->object.setProperty(
            *runtime->runtime,
            property_name,
            Value(*runtime->runtime, value->value)
        );
    } catch (...) {
        // Silently ignore errors
    }
}

OVHermesValue* hermes_value_get_property(
    OVHermesRuntime* runtime,
    OVHermesValue* object_value,
    const char* property_name
) {
    if (!runtime || !object_value || !property_name) return nullptr;

    try {
        if (!object_value->value.isObject()) return nullptr;

        Object obj = object_value->value.asObject(*runtime->runtime);
        Value value = obj.getProperty(*runtime->runtime, property_name);
        return new OVHermesValue(std::move(value));
    } catch (...) {
        return nullptr;
    }
}

void hermes_value_set_property(
    OVHermesRuntime* runtime,
    OVHermesValue* object_value,
    const char* property_name,
    OVHermesValue* value
) {
    if (!runtime || !object_value || !property_name || !value) return;

    try {
        if (!object_value->value.isObject()) return;

        Object obj = object_value->value.asObject(*runtime->runtime);
        obj.setProperty(
            *runtime->runtime,
            property_name,
            Value(*runtime->runtime, value->value)
        );
    } catch (...) {
        // Silently ignore errors
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

//
// Chrome DevTools Protocol (CDP) Implementation
//

using namespace facebook::hermes::cdp;
using namespace facebook::hermes::debugger;

struct OVCDPDebugAPI {
    std::unique_ptr<CDPDebugAPI> cdp_debug;
    facebook::hermes::HermesRuntime* runtime_ptr;

    OVCDPDebugAPI(std::unique_ptr<CDPDebugAPI>&& debug, facebook::hermes::HermesRuntime* rt)
        : cdp_debug(std::move(debug)), runtime_ptr(rt) {}
};

struct OVCDPAgent {
    std::unique_ptr<CDPAgent> agent;
    OVCDPMessageCallback message_callback;
    void* message_context;

    OVCDPAgent(
        std::unique_ptr<CDPAgent>&& ag,
        OVCDPMessageCallback cb,
        void* ctx
    ) : agent(std::move(ag)), message_callback(cb), message_context(ctx) {}
};

OVCDPDebugAPI* hermes_cdp_debug_create(OVHermesRuntime* runtime) {
    if (!runtime || !runtime->runtime) return nullptr;

    try {
        auto cdp_debug = CDPDebugAPI::create(*runtime->runtime);
        if (!cdp_debug) return nullptr;

        return new OVCDPDebugAPI(std::move(cdp_debug), runtime->runtime.get());
    } catch (...) {
        return nullptr;
    }
}

void hermes_cdp_debug_destroy(OVCDPDebugAPI* cdp_debug) {
    if (cdp_debug) {
        delete cdp_debug;
    }
}

OVCDPAgent* hermes_cdp_agent_create(
    OVCDPDebugAPI* cdp_debug,
    int32_t execution_context_id,
    OVCDPMessageCallback message_callback,
    void* message_context,
    OVCDPRuntimeTaskCallback task_callback,
    void* task_context
) {
    if (!cdp_debug || !cdp_debug->cdp_debug || !message_callback) {
        return nullptr;
    }

    try {
        // Create message callback wrapper
        auto outbound_func = [message_callback, message_context](const std::string& json) {
            message_callback(json.c_str(), message_context);
        };

        // Create runtime task callback wrapper
        // For now, we'll use a simple implementation
        auto& runtime_ref = cdp_debug->cdp_debug->runtime();
        auto task_func = [task_callback, task_context, &runtime_ref](facebook::hermes::debugger::RuntimeTask task) {
            if (task_callback) {
                // Execute the task immediately for simplicity
                // In a full implementation, this would queue the task
                task(runtime_ref);
            } else {
                // Execute immediately if no callback provided
                task(runtime_ref);
            }
        };

        // Create CDP agent
        auto agent = CDPAgent::create(
            execution_context_id,
            *cdp_debug->cdp_debug,
            task_func,
            outbound_func
        );

        if (!agent) return nullptr;

        return new OVCDPAgent(std::move(agent), message_callback, message_context);
    } catch (...) {
        return nullptr;
    }
}

void hermes_cdp_agent_destroy(OVCDPAgent* agent) {
    if (agent) {
        delete agent;
    }
}

void hermes_cdp_agent_handle_command(
    OVCDPAgent* agent,
    const char* json_command
) {
    if (!agent || !agent->agent || !json_command) return;

    try {
        agent->agent->handleCommand(std::string(json_command));
    } catch (...) {
        // Silently ignore errors for now
    }
}

void hermes_cdp_agent_enable_runtime(OVCDPAgent* agent) {
    if (!agent || !agent->agent) return;

    try {
        agent->agent->enableRuntimeDomain();
    } catch (...) {
        // Silently ignore errors
    }
}

void hermes_cdp_agent_enable_debugger(OVCDPAgent* agent) {
    if (!agent || !agent->agent) return;

    try {
        agent->agent->enableDebuggerDomain();
    } catch (...) {
        // Silently ignore errors
    }
}

void hermes_cdp_add_console_message(
    OVCDPDebugAPI* cdp_debug,
    const char* message,
    int level
) {
    if (!cdp_debug || !cdp_debug->cdp_debug || !message) return;

    try {
        // Get current timestamp
        auto now = std::chrono::system_clock::now();
        auto duration = now.time_since_epoch();
        double timestamp = std::chrono::duration<double, std::milli>(duration).count();

        // Map level to ConsoleAPIType
        ConsoleAPIType type;
        switch (level) {
            case 0: type = ConsoleAPIType::kLog; break;
            case 1: type = ConsoleAPIType::kDebug; break;
            case 2: type = ConsoleAPIType::kInfo; break;
            case 3: type = ConsoleAPIType::kError; break;
            case 4: type = ConsoleAPIType::kWarning; break;
            default: type = ConsoleAPIType::kLog; break;
        }

        // Create console message with the message as a string argument
        std::vector<jsi::Value> args;
        auto& runtime = cdp_debug->cdp_debug->runtime();
        args.push_back(jsi::String::createFromUtf8(runtime, message));

        ConsoleMessage console_msg(timestamp, type, std::move(args));
        cdp_debug->cdp_debug->addConsoleMessage(std::move(console_msg));
    } catch (...) {
        // Silently ignore errors
    }
}

void hermes_cdp_add_console_message_values(
    OVHermesRuntime* ov_runtime,
    OVCDPDebugAPI* cdp_debug,
    OVHermesValue** values,
    size_t value_count,
    int level
) {
    if (!ov_runtime || !cdp_debug || !cdp_debug->cdp_debug || !values) return;

    try {
        // Get the JSI runtime
        auto& runtime = cdp_debug->cdp_debug->runtime();

        // Get current timestamp
        auto now = std::chrono::system_clock::now();
        auto duration = now.time_since_epoch();
        double timestamp = std::chrono::duration<double, std::milli>(duration).count();

        // Map level to ConsoleAPIType
        ConsoleAPIType type;
        switch (level) {
            case 0: type = ConsoleAPIType::kLog; break;
            case 1: type = ConsoleAPIType::kDebug; break;
            case 2: type = ConsoleAPIType::kInfo; break;
            case 3: type = ConsoleAPIType::kError; break;
            case 4: type = ConsoleAPIType::kWarning; break;
            default: type = ConsoleAPIType::kLog; break;
        }

        // Convert OVHermesValue* to jsi::Value
        std::vector<jsi::Value> args;
        args.reserve(value_count);

        for (size_t i = 0; i < value_count; i++) {
            if (!values[i]) {
                args.push_back(jsi::Value::undefined());
                continue;
            }

            OVHermesValue* ov_value = values[i];

            // Clone the value using the copy constructor
            // This properly handles all value types (primitives, objects, arrays, etc.)
            args.push_back(jsi::Value(runtime, ov_value->value));
        }

        // Create and dispatch console message
        ConsoleMessage console_msg(timestamp, type, std::move(args));
        cdp_debug->cdp_debug->addConsoleMessage(std::move(console_msg));
    } catch (...) {
        // Silently ignore errors
    }
}

} // extern "C"
