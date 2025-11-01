/**
 * Simple WebSocket Server for Chrome DevTools Protocol
 *
 * This is a minimal WebSocket implementation specifically for CDP debugging.
 * It handles the WebSocket handshake and framing to bridge Chrome DevTools
 * with the Hermes CDP Agent.
 */

#ifndef OPENVIM_WEBSOCKET_SERVER_H
#define OPENVIM_WEBSOCKET_SERVER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WebSocketServer WebSocketServer;

/**
 * Callback when a WebSocket message is received from Chrome DevTools
 *
 * @param message The CDP command as JSON string
 * @param length Length of the message
 * @param user_data User context
 */
typedef void (*WebSocketMessageCallback)(
    const char* message,
    size_t length,
    void* user_data
);

/**
 * Callback when a client connects
 *
 * @param user_data User context
 */
typedef void (*WebSocketConnectCallback)(void* user_data);

/**
 * Callback when a client disconnects
 *
 * @param user_data User context
 */
typedef void (*WebSocketDisconnectCallback)(void* user_data);

/**
 * Create a WebSocket server
 *
 * @param port Port to listen on (e.g., 9229 for Chrome DevTools)
 * @param on_message Callback for incoming messages
 * @param on_connect Callback when client connects (optional)
 * @param on_disconnect Callback when client disconnects (optional)
 * @param user_data User context passed to callbacks
 * @return Server instance, or NULL on failure
 */
WebSocketServer* websocket_server_create(
    uint16_t port,
    WebSocketMessageCallback on_message,
    WebSocketConnectCallback on_connect,
    WebSocketDisconnectCallback on_disconnect,
    void* user_data
);

/**
 * Start the WebSocket server (non-blocking)
 * Spawns a background thread to handle connections
 *
 * @param server The server instance
 * @return true on success, false on failure
 */
bool websocket_server_start(WebSocketServer* server);

/**
 * Send a message to the connected client
 *
 * @param server The server instance
 * @param message The message to send (will be framed as WebSocket message)
 * @param length Length of the message
 * @return true on success, false on failure
 */
bool websocket_server_send(
    WebSocketServer* server,
    const char* message,
    size_t length
);

/**
 * Check if a client is connected
 *
 * @param server The server instance
 * @return true if client is connected
 */
bool websocket_server_is_connected(WebSocketServer* server);

/**
 * Stop the WebSocket server
 *
 * @param server The server instance
 */
void websocket_server_stop(WebSocketServer* server);

/**
 * Destroy the WebSocket server and free resources
 *
 * @param server The server instance
 */
void websocket_server_destroy(WebSocketServer* server);

/**
 * Get the WebSocket URL that Chrome DevTools should connect to
 * Returns a static buffer (don't free)
 *
 * @param server The server instance
 * @return WebSocket URL like "ws://localhost:9229"
 */
const char* websocket_server_get_url(WebSocketServer* server);

#ifdef __cplusplus
}
#endif

#endif // OPENVIM_WEBSOCKET_SERVER_H
