/**
 * Simple WebSocket Server Implementation for CDP
 *
 * This implements just enough of the WebSocket protocol to handle
 * Chrome DevTools Protocol (CDP) communication.
 */

#include "websocket_server.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// For WebSocket handshake
#include <string>
#include <sstream>

// For SHA1 hashing (WebSocket handshake)
#include <CommonCrypto/CommonDigest.h>

// For base64 encoding
static const char base64_chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789+/";

static std::string base64_encode(const unsigned char* data, size_t len) {
    std::string ret;
    int i = 0;
    int j = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];

    while (len--) {
        char_array_3[i++] = *(data++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for(i = 0; i < 4; i++)
                ret += base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for(j = i; j < 3; j++)
            char_array_3[j] = '\0';

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);

        for (j = 0; j < i + 1; j++)
            ret += base64_chars[char_array_4[j]];

        while(i++ < 3)
            ret += '=';
    }

    return ret;
}

struct WebSocketServer {
    uint16_t port;
    int server_fd;
    int client_fd;
    bool running;
    pthread_t thread;
    pthread_mutex_t mutex;

    WebSocketMessageCallback on_message;
    WebSocketConnectCallback on_connect;
    WebSocketDisconnectCallback on_disconnect;
    void* user_data;

    char url_buffer[256];
};

// WebSocket frame opcodes
#define WS_OPCODE_TEXT 0x01
#define WS_OPCODE_CLOSE 0x08
#define WS_OPCODE_PING 0x09
#define WS_OPCODE_PONG 0x0A

static bool websocket_perform_handshake(int client_fd) {
    char buffer[4096];
    ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer) - 1, 0);

    if (bytes_read <= 0) {
        return false;
    }

    buffer[bytes_read] = '\0';

    // Parse the WebSocket key from the handshake
    const char* key_header = "Sec-WebSocket-Key: ";
    const char* key_start = strstr(buffer, key_header);

    if (!key_start) {
        return false;
    }

    key_start += strlen(key_header);
    const char* key_end = strstr(key_start, "\r\n");

    if (!key_end) {
        return false;
    }

    std::string client_key(key_start, key_end - key_start);

    // Create the accept key: SHA1(client_key + magic_string)
    const char* magic_string = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    std::string accept_input = client_key + magic_string;

    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(accept_input.c_str(), accept_input.length(), hash);

    std::string accept_key = base64_encode(hash, CC_SHA1_DIGEST_LENGTH);

    // Send handshake response
    std::ostringstream response;
    response << "HTTP/1.1 101 Switching Protocols\r\n";
    response << "Upgrade: websocket\r\n";
    response << "Connection: Upgrade\r\n";
    response << "Sec-WebSocket-Accept: " << accept_key << "\r\n";
    response << "\r\n";

    std::string response_str = response.str();
    ssize_t sent = send(client_fd, response_str.c_str(), response_str.length(), 0);

    return sent == (ssize_t)response_str.length();
}

static bool websocket_send_frame(int client_fd, const char* data, size_t length) {
    if (client_fd < 0 || !data) return false;

    // WebSocket frame format:
    // FIN=1, RSV=0, opcode=text
    unsigned char header[10];
    size_t header_len = 0;

    header[0] = 0x80 | WS_OPCODE_TEXT; // FIN + text frame
    header_len = 1;

    // Payload length
    if (length < 126) {
        header[1] = length;
        header_len = 2;
    } else if (length < 65536) {
        header[1] = 126;
        header[2] = (length >> 8) & 0xFF;
        header[3] = length & 0xFF;
        header_len = 4;
    } else {
        header[1] = 127;
        for (int i = 0; i < 8; i++) {
            header[2 + i] = (length >> (56 - i * 8)) & 0xFF;
        }
        header_len = 10;
    }

    // Send header
    if (send(client_fd, header, header_len, 0) != (ssize_t)header_len) {
        return false;
    }

    // Send payload
    return send(client_fd, data, length, 0) == (ssize_t)length;
}

static bool websocket_receive_frame(int client_fd, char* buffer, size_t buffer_size, size_t* out_length) {
    unsigned char header[2];

    if (recv(client_fd, header, 2, 0) != 2) {
        return false;
    }

    bool fin = (header[0] & 0x80) != 0;
    uint8_t opcode = header[0] & 0x0F;
    bool masked = (header[1] & 0x80) != 0;
    uint64_t payload_length = header[1] & 0x7F;

    // Handle extended payload length
    if (payload_length == 126) {
        unsigned char ext_len[2];
        if (recv(client_fd, ext_len, 2, 0) != 2) return false;
        payload_length = (ext_len[0] << 8) | ext_len[1];
    } else if (payload_length == 127) {
        unsigned char ext_len[8];
        if (recv(client_fd, ext_len, 8, 0) != 8) return false;
        payload_length = 0;
        for (int i = 0; i < 8; i++) {
            payload_length = (payload_length << 8) | ext_len[i];
        }
    }

    // Read masking key if present
    unsigned char mask[4] = {0};
    if (masked) {
        if (recv(client_fd, mask, 4, 0) != 4) return false;
    }

    // Handle close frame
    if (opcode == WS_OPCODE_CLOSE) {
        return false;
    }

    // Handle ping frame
    if (opcode == WS_OPCODE_PING) {
        // Send pong response
        unsigned char pong[2] = {0x80 | WS_OPCODE_PONG, 0};
        send(client_fd, pong, 2, 0);
        return websocket_receive_frame(client_fd, buffer, buffer_size, out_length);
    }

    // Read payload
    if (payload_length > buffer_size - 1) {
        return false; // Buffer too small
    }

    ssize_t received = recv(client_fd, buffer, payload_length, 0);
    if (received != (ssize_t)payload_length) {
        return false;
    }

    // Unmask if needed
    if (masked) {
        for (size_t i = 0; i < payload_length; i++) {
            buffer[i] ^= mask[i % 4];
        }
    }

    buffer[payload_length] = '\0';
    *out_length = payload_length;

    return true;
}

static void* websocket_server_thread(void* arg) {
    WebSocketServer* server = (WebSocketServer*)arg;

    while (server->running) {
        // Accept connection
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        int client_fd = accept(server->server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            if (server->running) {
                perror("accept failed");
            }
            continue;
        }

        // Client connected (silent mode)

        // Perform WebSocket handshake
        if (!websocket_perform_handshake(client_fd)) {
            close(client_fd);
            continue;
        }

        pthread_mutex_lock(&server->mutex);
        server->client_fd = client_fd;
        pthread_mutex_unlock(&server->mutex);

        // Call connect callback
        if (server->on_connect) {
            server->on_connect(server->user_data);
        }

        // Message loop
        char buffer[65536];
        while (server->running && server->client_fd >= 0) {
            size_t length;
            if (websocket_receive_frame(client_fd, buffer, sizeof(buffer), &length)) {
                if (server->on_message) {
                    server->on_message(buffer, length, server->user_data);
                }
            } else {
                break;
            }
        }

        // Client disconnected (silent mode)

        pthread_mutex_lock(&server->mutex);
        if (server->client_fd == client_fd) {
            close(server->client_fd);
            server->client_fd = -1;
        }
        pthread_mutex_unlock(&server->mutex);

        // Call disconnect callback
        if (server->on_disconnect) {
            server->on_disconnect(server->user_data);
        }
    }

    return NULL;
}

extern "C" {

WebSocketServer* websocket_server_create(
    uint16_t port,
    WebSocketMessageCallback on_message,
    WebSocketConnectCallback on_connect,
    WebSocketDisconnectCallback on_disconnect,
    void* user_data
) {
    WebSocketServer* server = new WebSocketServer();
    if (!server) return NULL;

    server->port = port;
    server->server_fd = -1;
    server->client_fd = -1;
    server->running = false;
    server->on_message = on_message;
    server->on_connect = on_connect;
    server->on_disconnect = on_disconnect;
    server->user_data = user_data;

    pthread_mutex_init(&server->mutex, NULL);

    snprintf(server->url_buffer, sizeof(server->url_buffer),
             "ws://localhost:%d", port);

    return server;
}

bool websocket_server_start(WebSocketServer* server) {
    if (!server || server->running) return false;

    // Create socket
    server->server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server->server_fd < 0) {
        perror("socket failed");
        return false;
    }

    // Allow address reuse
    int opt = 1;
    setsockopt(server->server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(server->port);

    if (bind(server->server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind failed");
        close(server->server_fd);
        server->server_fd = -1;
        return false;
    }

    // Listen
    if (listen(server->server_fd, 1) < 0) {
        perror("listen failed");
        close(server->server_fd);
        server->server_fd = -1;
        return false;
    }

    // Server listening (silent mode - messages go to Chrome console)

    // Start server thread
    server->running = true;
    if (pthread_create(&server->thread, NULL, websocket_server_thread, server) != 0) {
        perror("pthread_create failed");
        server->running = false;
        close(server->server_fd);
        server->server_fd = -1;
        return false;
    }

    return true;
}

bool websocket_server_send(
    WebSocketServer* server,
    const char* message,
    size_t length
) {
    if (!server) return false;

    pthread_mutex_lock(&server->mutex);
    bool success = false;

    if (server->client_fd >= 0) {
        success = websocket_send_frame(server->client_fd, message, length);
    }

    pthread_mutex_unlock(&server->mutex);
    return success;
}

bool websocket_server_is_connected(WebSocketServer* server) {
    if (!server) return false;

    pthread_mutex_lock(&server->mutex);
    bool connected = server->client_fd >= 0;
    pthread_mutex_unlock(&server->mutex);

    return connected;
}

void websocket_server_stop(WebSocketServer* server) {
    if (!server || !server->running) return;

    server->running = false;

    // Close server socket to unblock accept()
    if (server->server_fd >= 0) {
        shutdown(server->server_fd, SHUT_RDWR);
        close(server->server_fd);
        server->server_fd = -1;
    }

    // Close client socket
    pthread_mutex_lock(&server->mutex);
    if (server->client_fd >= 0) {
        close(server->client_fd);
        server->client_fd = -1;
    }
    pthread_mutex_unlock(&server->mutex);

    // Wait for thread to finish
    pthread_join(server->thread, NULL);
}

void websocket_server_destroy(WebSocketServer* server) {
    if (!server) return;

    websocket_server_stop(server);
    pthread_mutex_destroy(&server->mutex);
    delete server;
}

const char* websocket_server_get_url(WebSocketServer* server) {
    return server ? server->url_buffer : NULL;
}

} // extern "C"
