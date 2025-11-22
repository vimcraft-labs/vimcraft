/**
 * CDP Debugger Implementation
 *
 * Bridges WebSocket server ↔ CDP Agent to enable Chrome DevTools debugging
 */

#include "cdp_debugger.h"
#include "websocket_server.h"
#include "../../system/jsi/hermes_c_api.h"

#include <stdio.h>
#include <string.h>
#include <string>

struct CDPDebugger {
    OVHermesRuntime* runtime;
    OVCDPDebugAPI* cdp_debug;
    OVCDPAgent* cdp_agent;
    WebSocketServer* ws_server;
    uint16_t port;
    char devtools_url[512];
};

// Callback when WebSocket receives a message from Chrome
static void on_ws_message(const char* message, size_t length, void* user_data) {
    CDPDebugger* debugger = (CDPDebugger*)user_data;

    // Forward CDP command to agent
    if (debugger->cdp_agent) {
        hermes_cdp_agent_handle_command(debugger->cdp_agent, message);
    }
}

// Callback when CDP agent wants to send a message to Chrome
static void on_cdp_message(const char* json_message, void* context) {
    CDPDebugger* debugger = (CDPDebugger*)context;

    // Forward CDP response/event to WebSocket
    if (debugger->ws_server) {
        websocket_server_send(debugger->ws_server, json_message, strlen(json_message));
    }
}

// Callback when Chrome connects
static void on_ws_connect(void* user_data) {
    CDPDebugger* debugger = (CDPDebugger*)user_data;
    // Chrome DevTools connected (silent mode)

    // Enable Runtime and Debugger domains
    if (debugger->cdp_agent) {
        hermes_cdp_agent_enable_runtime(debugger->cdp_agent);
        hermes_cdp_agent_enable_debugger(debugger->cdp_agent);
    }
}

// Callback when Chrome disconnects
static void on_ws_disconnect(void* user_data) {
    // Chrome DevTools disconnected (silent mode)
}

extern "C" {

CDPDebugger* cdp_debugger_create(OVHermesRuntime* runtime, uint16_t port) {
    if (!runtime) return NULL;

    CDPDebugger* debugger = new CDPDebugger();
    if (!debugger) return NULL;

    memset(debugger, 0, sizeof(CDPDebugger));
    debugger->runtime = runtime;
    debugger->port = port;

    // Create CDP debug session
    debugger->cdp_debug = hermes_cdp_debug_create(runtime);
    if (!debugger->cdp_debug) {
        fprintf(stderr, "[CDP] Failed to create CDP debug session\n");
        delete debugger;
        return NULL;
    }

    // Create CDP agent
    debugger->cdp_agent = hermes_cdp_agent_create(
        debugger->cdp_debug,
        1, // execution context ID
        on_cdp_message,
        debugger,
        NULL, // runtime task callback (handled internally)
        NULL
    );

    if (!debugger->cdp_agent) {
        fprintf(stderr, "[CDP] Failed to create CDP agent\n");
        hermes_cdp_debug_destroy(debugger->cdp_debug);
        delete debugger;
        return NULL;
    }

    // Create WebSocket server
    debugger->ws_server = websocket_server_create(
        port,
        on_ws_message,
        on_ws_connect,
        on_ws_disconnect,
        debugger
    );

    if (!debugger->ws_server) {
        fprintf(stderr, "[CDP] Failed to create WebSocket server\n");
        hermes_cdp_agent_destroy(debugger->cdp_agent);
        hermes_cdp_debug_destroy(debugger->cdp_debug);
        delete debugger;
        return NULL;
    }

    // Create Chrome DevTools URL
    snprintf(debugger->devtools_url, sizeof(debugger->devtools_url),
             "devtools://devtools/bundled/inspector.html?ws=localhost:%d", port);

    return debugger;
}

bool cdp_debugger_start(CDPDebugger* debugger) {
    if (!debugger || !debugger->ws_server) return false;

    if (!websocket_server_start(debugger->ws_server)) {
        fprintf(stderr, "[CDP] Failed to start WebSocket server\n");
        return false;
    }

    // Chrome launches automatically, no need for instructions

    return true;
}

bool cdp_debugger_is_connected(CDPDebugger* debugger) {
    if (!debugger || !debugger->ws_server) return false;
    return websocket_server_is_connected(debugger->ws_server);
}

void cdp_debugger_log(CDPDebugger* debugger, const char* message, int level) {
    if (!debugger || !debugger->cdp_debug || !message) return;

    hermes_cdp_add_console_message(debugger->cdp_debug, message, level);
}

void cdp_debugger_log_values(
    CDPDebugger* debugger,
    OVHermesValue** values,
    size_t value_count,
    int level
) {
    if (!debugger || !debugger->runtime || !debugger->cdp_debug || !values) return;

    hermes_cdp_add_console_message_values(
        debugger->runtime,
        debugger->cdp_debug,
        values,
        value_count,
        level
    );
}

void cdp_debugger_stop(CDPDebugger* debugger) {
    if (!debugger) return;

    if (debugger->ws_server) {
        websocket_server_stop(debugger->ws_server);
    }
}

void cdp_debugger_destroy(CDPDebugger* debugger) {
    if (!debugger) return;

    if (debugger->ws_server) {
        websocket_server_destroy(debugger->ws_server);
    }

    if (debugger->cdp_agent) {
        hermes_cdp_agent_destroy(debugger->cdp_agent);
    }

    if (debugger->cdp_debug) {
        hermes_cdp_debug_destroy(debugger->cdp_debug);
    }

    delete debugger;
}

const char* cdp_debugger_get_url(CDPDebugger* debugger) {
    return debugger ? debugger->devtools_url : NULL;
}

} // extern "C"
