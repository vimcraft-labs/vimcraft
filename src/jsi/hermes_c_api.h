/**
 * Hermes C API Wrapper for OpenVim
 *
 * This provides a C ABI interface to Hermes JSI (which is C++)
 * so that Zig can easily call into Hermes with zero-copy performance.
 *
 * Design:
 * - Opaque pointers for C++ objects
 * - C function signatures for all operations
 * - Zero-copy string passing via pointers + lengths
 * - Context pointer for host function callbacks
 */

#ifndef OPENVIM_HERMES_C_API_H
#define OPENVIM_HERMES_C_API_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types (C++ objects wrapped for C)
// Using OV prefix to avoid name collision with Hermes C++ types
typedef struct OVHermesRuntime OVHermesRuntime;
typedef struct OVHermesValue OVHermesValue;
typedef struct OVHermesString OVHermesString;
typedef struct OVHermesObject OVHermesObject;

// Host function callback type
// This is called when JavaScript invokes a native function
typedef OVHermesValue* (*OVHermesHostFunction)(
    OVHermesRuntime* runtime,
    void* context,           // User context (e.g., Editor pointer)
    OVHermesValue** args,      // Array of arguments from JavaScript
    size_t arg_count
);

//
// Runtime Lifecycle
//

/**
 * Create a new Hermes runtime with default configuration
 * Returns NULL on failure
 */
OVHermesRuntime* hermes_runtime_create(void);

/**
 * Create a Hermes runtime with minimal configuration
 * (Smaller memory footprint, faster startup)
 */
OVHermesRuntime* hermes_runtime_create_minimal(void);

/**
 * Destroy a Hermes runtime and free all resources
 */
void hermes_runtime_destroy(OVHermesRuntime* runtime);

//
// JavaScript Execution
//

/**
 * Evaluate JavaScript source code
 *
 * @param runtime The Hermes runtime
 * @param source JavaScript source code
 * @param source_len Length of source code
 * @param source_url Source URL for stack traces (can be NULL)
 * @return Result value, or NULL if exception occurred
 */
OVHermesValue* hermes_evaluate_javascript(
    OVHermesRuntime* runtime,
    const char* source,
    size_t source_len,
    const char* source_url
);

/**
 * Evaluate Hermes bytecode (.hbc file)
 *
 * @param runtime The Hermes runtime
 * @param bytecode Bytecode buffer
 * @param bytecode_len Length of bytecode
 * @return Result value, or NULL if exception occurred
 */
OVHermesValue* hermes_evaluate_bytecode(
    OVHermesRuntime* runtime,
    const uint8_t* bytecode,
    size_t bytecode_len
);

/**
 * Check if the runtime has a pending exception
 */
bool hermes_has_exception(OVHermesRuntime* runtime);

/**
 * Get the current exception message
 * Returns NULL if no exception
 */
const char* hermes_get_exception_message(OVHermesRuntime* runtime);

//
// Host Function Registration
//

/**
 * Register a global host function that JavaScript can call
 * This enables zero-copy calls from JS to native code!
 *
 * @param runtime The Hermes runtime
 * @param name Function name (will be global in JavaScript)
 * @param callback Native function to call
 * @param context User context passed to callback
 */
void hermes_register_host_function(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostFunction callback,
    void* context
);

//
// Value Operations
//

/**
 * Get the type of a value
 */
typedef enum {
    HERMES_TYPE_UNDEFINED,
    HERMES_TYPE_NULL,
    HERMES_TYPE_BOOLEAN,
    HERMES_TYPE_NUMBER,
    HERMES_TYPE_STRING,
    HERMES_TYPE_OBJECT,
} HermesValueType;

HermesValueType hermes_value_get_type(OVHermesValue* value);

/**
 * Check value types
 */
bool hermes_value_is_undefined(OVHermesValue* value);
bool hermes_value_is_null(OVHermesValue* value);
bool hermes_value_is_boolean(OVHermesValue* value);
bool hermes_value_is_number(OVHermesValue* value);
bool hermes_value_is_string(OVHermesValue* value);
bool hermes_value_is_object(OVHermesValue* value);

/**
 * Extract values (these fail if type is wrong)
 */
bool hermes_value_get_boolean(OVHermesValue* value);
double hermes_value_get_number(OVHermesValue* value);

/**
 * Get string value (zero-copy!)
 * Returns pointer to internal string data and sets length
 * The pointer is valid until the value is destroyed
 */
const char* hermes_value_get_string(
    OVHermesRuntime* runtime,
    OVHermesValue* value,
    size_t* out_length
);

/**
 * Create new values
 */
OVHermesValue* hermes_value_create_undefined(OVHermesRuntime* runtime);
OVHermesValue* hermes_value_create_null(OVHermesRuntime* runtime);
OVHermesValue* hermes_value_create_boolean(OVHermesRuntime* runtime, bool value);
OVHermesValue* hermes_value_create_number(OVHermesRuntime* runtime, double value);

/**
 * Create string value (copies the string data)
 */
OVHermesValue* hermes_value_create_string(
    OVHermesRuntime* runtime,
    const char* str,
    size_t length
);

/**
 * Destroy a value (release reference)
 */
void hermes_value_destroy(OVHermesValue* value);

//
// Global Object Access
//

/**
 * Get the global object
 */
OVHermesObject* hermes_get_global_object(OVHermesRuntime* runtime);

/**
 * Get a property from an object
 */
OVHermesValue* hermes_object_get_property(
    OVHermesRuntime* runtime,
    OVHermesObject* object,
    const char* property_name
);

/**
 * Set a property on an object
 */
void hermes_object_set_property(
    OVHermesRuntime* runtime,
    OVHermesObject* object,
    const char* property_name,
    OVHermesValue* value
);

//
// Utility Functions
//

/**
 * Get the Hermes version string
 */
const char* hermes_get_version(void);

/**
 * Check if a buffer is valid Hermes bytecode
 */
bool hermes_is_bytecode(const uint8_t* data, size_t len);

#ifdef __cplusplus
}
#endif

#endif // OPENVIM_HERMES_C_API_H
