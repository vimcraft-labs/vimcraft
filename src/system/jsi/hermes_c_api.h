/**
 * Hermes C API Wrapper for Vimcraft
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

#ifndef VIMCRAFT_HERMES_C_API_H
#define VIMCRAFT_HERMES_C_API_H

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

/**
 * Clear any pending exception
 */
void hermes_clear_exception(OVHermesRuntime* runtime);

/**
 * Throw a JavaScript Error from native code
 *
 * This sets a pending throw flag that will be checked by the host function
 * wrapper. When the host function returns, a JavaScript Error will be thrown
 * with the provided message.
 *
 * Usage in host functions:
 * 1. Call hermes_throw_error(runtime, "error message")
 * 2. Return NULL from host function
 * 3. JavaScript caller receives Error exception
 *
 * @param runtime The Hermes runtime
 * @param message Error message (will be copied)
 *
 * @example
 * if (!valid_arg) {
 *     hermes_throw_error(runtime, "Invalid argument");
 *     return NULL;  // Host function wrapper will throw
 * }
 */
void hermes_throw_error(OVHermesRuntime* runtime, const char* message);

/**
 * Throw a JavaScript TypeError from native code
 *
 * Similar to hermes_throw_error(), but creates a TypeError instead of Error.
 * Use this for type validation failures (e.g., expected string, got number).
 *
 * @param runtime The Hermes runtime
 * @param message Error message
 *
 * @example
 * if (!hermes_value_is_string(arg)) {
 *     hermes_throw_type_error(runtime, "Expected string argument");
 *     return NULL;
 * }
 */
void hermes_throw_type_error(OVHermesRuntime* runtime, const char* message);

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
// HostObject Support (Zero-Copy JSI)
//

/**
 * HostObject callback types
 * These are called when JavaScript accesses properties on a HostObject
 */

// Get property callback (called when JavaScript reads a property)
typedef OVHermesValue* (*OVHermesHostObjectGet)(
    OVHermesRuntime* runtime,
    void* context,
    const char* prop_name
);

// Set property callback (called when JavaScript writes a property)
typedef OVHermesValue* (*OVHermesHostObjectSet)(
    OVHermesRuntime* runtime,
    void* context,
    const char* prop_name,
    OVHermesValue* value
);

// Enumerate properties callback (called when JavaScript calls Object.keys())
typedef OVHermesValue* (*OVHermesHostObjectEnumerator)(
    OVHermesRuntime* runtime,
    void* context
);

/**
 * Create a Function value (for returning from HostObject getter)
 * This wraps a host function into a callable JavaScript Function object
 *
 * @param runtime The Hermes runtime
 * @param name Function name (for stack traces)
 * @param callback Native function to call
 * @param context User context passed to callback
 * @return Function value
 */
OVHermesValue* hermes_create_function(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostFunction callback,
    void* context
);

/**
 * Register a HostObject (for zero-copy property access)
 * This is the recommended way to expose native APIs to JavaScript
 *
 * Benefits over host functions:
 * - 3-5x faster (no per-call allocation overhead)
 * - Clean namespace (vim.motion.up vs vimMotionUp)
 * - Property enumeration support (Object.keys works)
 * - Foundation for Plugin SDK
 *
 * @param runtime The Hermes runtime
 * @param name Object name (will be global in JavaScript)
 * @param getter Callback for property access (required)
 * @param setter Callback for property writes (NULL for read-only)
 * @param enumerator Callback for property enumeration (NULL to disable Object.keys)
 * @param context User context passed to callbacks
 */
void hermes_register_host_object(
    OVHermesRuntime* runtime,
    const char* name,
    OVHermesHostObjectGet getter,
    OVHermesHostObjectSet setter,
    OVHermesHostObjectEnumerator enumerator,
    void* context
);

/**
 * Create a JavaScript array
 * @param runtime The Hermes runtime
 * @param length Initial array length
 * @return Array value
 */
OVHermesValue* hermes_array_create(OVHermesRuntime* runtime, size_t length);

/**
 * Set an array element
 * @param runtime The Hermes runtime
 * @param array The array value
 * @param index Element index
 * @param value Value to set
 */
void hermes_array_set(
    OVHermesRuntime* runtime,
    OVHermesValue* array,
    size_t index,
    OVHermesValue* value
);

/**
 * Get array length
 * @param runtime The Hermes runtime
 * @param array The array value
 * @return Array length, or 0 if not an array
 */
size_t hermes_array_length(OVHermesRuntime* runtime, OVHermesValue* array);

/**
 * Get array element at index
 * @param runtime The Hermes runtime
 * @param array The array value
 * @param index Element index
 * @return Element value, or NULL if out of bounds or not an array
 */
OVHermesValue* hermes_array_get(
    OVHermesRuntime* runtime,
    OVHermesValue* array,
    size_t index
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
bool hermes_value_is_array(OVHermesRuntime* runtime, OVHermesValue* value);
bool hermes_value_is_function(OVHermesRuntime* runtime, OVHermesValue* value);

/**
 * Call a JavaScript function
 *
 * @param runtime The Hermes runtime
 * @param function The function value to call
 * @param args Array of argument values (can be NULL if arg_count is 0)
 * @param arg_count Number of arguments
 * @return The return value from the function call (or NULL on error)
 */
OVHermesValue* hermes_call_function(
    OVHermesRuntime* runtime,
    OVHermesValue* function,
    OVHermesValue** args,
    size_t arg_count
);

/**
 * Clone a value (creates a new independent copy)
 * The returned value must be freed with hermes_value_destroy()
 */
OVHermesValue* hermes_value_clone(OVHermesRuntime* runtime, OVHermesValue* value);

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
 * Create a new empty object
 */
OVHermesValue* hermes_value_create_object(OVHermesRuntime* runtime);

//
// ArrayBuffer Support (Zero-Copy External Memory)
//

/**
 * Finalizer callback type for External ArrayBuffers
 * Called when JavaScript garbage collects the ArrayBuffer
 *
 * @param data Pointer to the external memory
 * @param context User context passed to create_arraybuffer_external
 */
typedef void (*OVHermesArrayBufferFinalizer)(
    void* data,
    void* context
);

/**
 * Create an External ArrayBuffer (zero-copy!)
 * The ArrayBuffer wraps external native memory without copying data.
 *
 * React Native JSI pattern: Used for realtime camera frames, large buffers, etc.
 *
 * @param runtime The Hermes runtime
 * @param data Pointer to native memory (must remain valid until finalizer called)
 * @param size Size of memory in bytes
 * @param finalizer Callback when JavaScript releases the ArrayBuffer (can be NULL)
 * @param finalizer_ctx User context passed to finalizer
 * @return ArrayBuffer value wrapping the external memory
 *
 * Example (zero-copy buffer access):
 *   const content = try buffer.content.toString(); // Rope → string
 *   defer allocator.free(content);
 *   const ab = hermes_value_create_arraybuffer_external(
 *       runtime, content.ptr, content.len, finalizer, finalizer_ctx);
 *   // JavaScript can now read 'content' directly via ArrayBuffer!
 *   // Finalizer will free the memory when JS GC collects the ArrayBuffer
 */
OVHermesValue* hermes_value_create_arraybuffer_external(
    OVHermesRuntime* runtime,
    void* data,
    size_t size,
    OVHermesArrayBufferFinalizer finalizer,
    void* finalizer_ctx
);

/**
 * Get pointer to ArrayBuffer's underlying data
 *
 * @param runtime The Hermes runtime
 * @param arraybuffer The ArrayBuffer value
 * @param out_data Output pointer to buffer data
 * @param out_size Output buffer size in bytes
 * @return true if successful, false if value is not an ArrayBuffer
 */
bool hermes_value_get_arraybuffer_data(
    OVHermesRuntime* runtime,
    OVHermesValue* arraybuffer,
    void** out_data,
    size_t* out_size
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
 * Destroy an object (release reference)
 */
void hermes_object_destroy(OVHermesObject* object);

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

/**
 * Get a property from a value (if it's an object)
 * Returns NULL if value is not an object or property doesn't exist
 */
OVHermesValue* hermes_value_get_property(
    OVHermesRuntime* runtime,
    OVHermesValue* object_value,
    const char* property_name
);

/**
 * Set a property on a value (if it's an object)
 */
void hermes_value_set_property(
    OVHermesRuntime* runtime,
    OVHermesValue* object_value,
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

/**
 * Drain the microtask queue (process pending Promise callbacks)
 *
 * Hermes schedules Promise .then() callbacks as microtasks. These microtasks
 * must be explicitly drained after native code resolves promises.
 *
 * Call this after:
 * - Processing async fetch callbacks (resolve/reject)
 * - Any native code that resolves JavaScript Promises
 *
 * @param runtime The Hermes runtime
 * @param max_hint Maximum number of microtasks to process (-1 for unlimited)
 * @return true if all microtasks were processed, false if more remain
 *
 * Example:
 *   // After resolving a Promise from native code
 *   hermes_call_function(runtime, resolve_callback, ...);
 *   hermes_drain_microtasks(runtime, -1);  // Process .then() callbacks
 */
bool hermes_drain_microtasks(OVHermesRuntime* runtime, int max_hint);

//
// Chrome DevTools Protocol (CDP) Support
//

// Opaque types for CDP
typedef struct OVCDPDebugAPI OVCDPDebugAPI;
typedef struct OVCDPAgent OVCDPAgent;

/**
 * Callback for outbound CDP messages (responses and events)
 * This is called when Hermes wants to send a CDP message to the debugger
 *
 * @param json_message CDP message as JSON string (null-terminated)
 * @param context User context
 */
typedef void (*OVCDPMessageCallback)(
    const char* json_message,
    void* context
);

/**
 * Callback for runtime tasks
 * CDP agent needs to enqueue tasks that run on the runtime thread
 *
 * @param task Opaque task pointer
 * @param context User context
 */
typedef void (*OVCDPRuntimeTaskCallback)(
    void* task,
    void* context
);

/**
 * Create a CDP debug session for a runtime
 * This must be called before creating any CDP agents
 *
 * @param runtime The Hermes runtime to debug
 * @return CDP debug API instance, or NULL on failure
 */
OVCDPDebugAPI* hermes_cdp_debug_create(OVHermesRuntime* runtime);

/**
 * Destroy a CDP debug session
 */
void hermes_cdp_debug_destroy(OVCDPDebugAPI* cdp_debug);

/**
 * Create a CDP agent for handling protocol messages
 *
 * @param cdp_debug The CDP debug session
 * @param execution_context_id Unique ID for this execution context (use 1)
 * @param message_callback Callback for outbound CDP messages
 * @param message_context User context for message callback
 * @param task_callback Callback for runtime tasks (can be NULL for now)
 * @param task_context User context for task callback
 * @return CDP agent instance, or NULL on failure
 */
OVCDPAgent* hermes_cdp_agent_create(
    OVCDPDebugAPI* cdp_debug,
    int32_t execution_context_id,
    OVCDPMessageCallback message_callback,
    void* message_context,
    OVCDPRuntimeTaskCallback task_callback,
    void* task_context
);

/**
 * Destroy a CDP agent
 */
void hermes_cdp_agent_destroy(OVCDPAgent* agent);

/**
 * Handle an incoming CDP command (from Chrome DevTools)
 *
 * @param agent The CDP agent
 * @param json_command CDP command as JSON string (null-terminated)
 */
void hermes_cdp_agent_handle_command(
    OVCDPAgent* agent,
    const char* json_command
);

/**
 * Enable the Runtime domain (required for console.log)
 * Call this after creating the agent
 */
void hermes_cdp_agent_enable_runtime(OVCDPAgent* agent);

/**
 * Enable the Debugger domain (required for breakpoints)
 * Call this after creating the agent
 */
void hermes_cdp_agent_enable_debugger(OVCDPAgent* agent);

/**
 * Add a console message (for console.log from native code)
 *
 * @param cdp_debug The CDP debug session
 * @param message The message text
 * @param level Message level: 0=log, 1=debug, 2=info, 3=error, 4=warning
 */
void hermes_cdp_add_console_message(
    OVCDPDebugAPI* cdp_debug,
    const char* message,
    int level
);

/**
 * Add a console message with JavaScript values (React Native approach)
 *
 * This passes raw JavaScript values to Chrome DevTools, letting it handle
 * the formatting. This properly displays objects, arrays, etc.
 *
 * @param runtime The Hermes runtime
 * @param cdp_debug The CDP debug session
 * @param values Array of JavaScript values to log
 * @param value_count Number of values
 * @param level Message level: 0=log, 1=debug, 2=info, 3=error, 4=warning
 */
void hermes_cdp_add_console_message_values(
    OVHermesRuntime* runtime,
    OVCDPDebugAPI* cdp_debug,
    OVHermesValue** values,
    size_t value_count,
    int level
);

#ifdef __cplusplus
}
#endif

#endif // VIMCRAFT_HERMES_C_API_H
