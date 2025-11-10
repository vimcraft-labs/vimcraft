/**
 * Chrome DevTools Protocol Debugger Integration
 *
 * This bridges the WebSocket server with the Hermes CDP Agent
 * to enable Chrome DevTools debugging.
 */

#ifndef OPENVIM_CDP_DEBUGGER_H
#define OPENVIM_CDP_DEBUGGER_H

#include "../../system/jsi/hermes_c_api.h"
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CDPDebugger CDPDebugger;

/**
 * Create a CDP debugger instance
 *
 * This creates the WebSocket server and CDP agent, ready to accept
 * connections from Chrome DevTools.
 *
 * @param runtime The Hermes runtime to debug
 * @param port WebSocket port (default: 9229)
 * @return Debugger instance, or NULL on failure
 */
CDPDebugger* cdp_debugger_create(OVHermesRuntime* runtime, uint16_t port);

/**
 * Start the CDP debugger server
 *
 * This starts the WebSocket server and prints the Chrome DevTools URL.
 *
 * @param debugger The debugger instance
 * @return true on success, false on failure
 */
bool cdp_debugger_start(CDPDebugger* debugger);

/**
 * Check if Chrome DevTools is connected
 *
 * @param debugger The debugger instance
 * @return true if connected
 */
bool cdp_debugger_is_connected(CDPDebugger* debugger);

/**
 * Send a console log message to Chrome DevTools
 *
 * This allows Zig code to send messages to the Chrome Console.
 *
 * @param debugger The debugger instance
 * @param message The message to log
 * @param level 0=log, 1=debug, 2=info, 3=error, 4=warning
 */
void cdp_debugger_log(CDPDebugger* debugger, const char* message, int level);

/**
 * Send console log with JavaScript values (React Native approach)
 *
 * This passes raw JavaScript values to Chrome DevTools for proper formatting
 * of objects, arrays, and other complex types.
 *
 * @param debugger The debugger instance
 * @param values Array of JavaScript values to log
 * @param value_count Number of values
 * @param level 0=log, 1=debug, 2=info, 3=error, 4=warning
 */
void cdp_debugger_log_values(
    CDPDebugger* debugger,
    OVHermesValue** values,
    size_t value_count,
    int level
);

/**
 * Stop the CDP debugger
 *
 * @param debugger The debugger instance
 */
void cdp_debugger_stop(CDPDebugger* debugger);

/**
 * Destroy the CDP debugger and free resources
 *
 * @param debugger The debugger instance
 */
void cdp_debugger_destroy(CDPDebugger* debugger);

/**
 * Get the Chrome DevTools URL
 *
 * @param debugger The debugger instance
 * @return URL like "devtools://devtools/bundled/inspector.html?ws=localhost:9229"
 */
const char* cdp_debugger_get_url(CDPDebugger* debugger);

#ifdef __cplusplus
}
#endif

#endif // OPENVIM_CDP_DEBUGGER_H
