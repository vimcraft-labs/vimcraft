/// Fetch API for JavaScript plugins
/// Provides Browser-compatible HTTP fetch functionality
const std = @import("std");
const c = @import("c_api.zig").c;

/// Context passed to fetch function
pub const FetchContext = struct {
    allocator: std.mem.Allocator,
};

// ============================================================================
// Fetch Function
// ============================================================================

/// fetch(url, options?) -> Response object
pub export fn fetchFunction(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "fetch requires a URL argument");
        return null;
    }

    const ctx: *FetchContext = @ptrCast(@alignCast(context));
    const url_val = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid URL argument");
        return null;
    };

    // Get URL string
    var url_len: usize = 0;
    const url_ptr = c.hermes_value_get_string(runtime, url_val, &url_len);
    if (url_ptr == null or url_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get URL string");
        return null;
    }
    const url_str = url_ptr[0..url_len];

    // Parse options
    var method: std.http.Method = .GET;
    var request_body: ?[]const u8 = null;
    var extra_headers: std.ArrayListUnmanaged(std.http.Header) = .empty;
    defer extra_headers.deinit(ctx.allocator);

    if (arg_count >= 2) {
        const opts_val = args[1];
        if (opts_val != null and c.hermes_value_is_object(opts_val)) {
            // Get method
            const method_prop = c.hermes_value_get_property(runtime, opts_val, "method");
            if (method_prop != null and c.hermes_value_is_string(method_prop)) {
                var method_len: usize = 0;
                const method_ptr = c.hermes_value_get_string(runtime, method_prop, &method_len);
                if (method_ptr != null and method_len > 0) {
                    method = parseMethod(method_ptr[0..method_len]);
                }
            }
            if (method_prop != null) c.hermes_value_destroy(method_prop);

            // Get body
            const body_prop = c.hermes_value_get_property(runtime, opts_val, "body");
            if (body_prop != null and c.hermes_value_is_string(body_prop)) {
                var body_len: usize = 0;
                const body_ptr = c.hermes_value_get_string(runtime, body_prop, &body_len);
                if (body_ptr != null and body_len > 0) {
                    request_body = ctx.allocator.dupe(u8, body_ptr[0..body_len]) catch null;
                }
            }
            if (body_prop != null) c.hermes_value_destroy(body_prop);

            // Get headers
            const headers_prop = c.hermes_value_get_property(runtime, opts_val, "headers");
            if (headers_prop != null and c.hermes_value_is_object(headers_prop)) {
                // Common headers to check
                const common_headers = [_][]const u8{
                    "Content-Type",
                    "Accept",
                    "Authorization",
                    "User-Agent",
                    "X-API-Key",
                };

                for (common_headers) |header_name| {
                    const header_val = c.hermes_value_get_property(runtime, headers_prop, header_name.ptr);
                    if (header_val != null and c.hermes_value_is_string(header_val)) {
                        var header_len: usize = 0;
                        const header_ptr = c.hermes_value_get_string(runtime, header_val, &header_len);
                        if (header_ptr != null and header_len > 0) {
                            const header_value = ctx.allocator.dupe(u8, header_ptr[0..header_len]) catch {
                                c.hermes_value_destroy(header_val);
                                continue;
                            };
                            extra_headers.append(ctx.allocator, .{
                                .name = header_name,
                                .value = header_value,
                            }) catch {
                                ctx.allocator.free(header_value);
                            };
                        }
                    }
                    if (header_val != null) c.hermes_value_destroy(header_val);
                }
            }
            if (headers_prop != null) c.hermes_value_destroy(headers_prop);
        }
    }

    defer {
        if (request_body) |body| ctx.allocator.free(body);
        for (extra_headers.items) |header| {
            ctx.allocator.free(header.value);
        }
    }

    // Parse URL
    const uri = std.Uri.parse(url_str) catch {
        c.hermes_throw_error(runtime, "Invalid URL");
        return null;
    };

    // Use the Zig 0.15 fetch API
    var client = std.http.Client{ .allocator = ctx.allocator };
    defer client.deinit();

    // Create a response body writer using std.Io.Writer.Allocating (Zig 0.15 API)
    var response_writer: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer response_writer.deinit();

    const result = client.fetch(.{
        .location = .{ .uri = uri },
        .method = method,
        .payload = request_body,
        .extra_headers = extra_headers.items,
        .response_writer = &response_writer.writer,
    }) catch {
        c.hermes_throw_error(runtime, "HTTP request failed");
        return null;
    };

    // Get response body content
    const response_body = response_writer.written();

    // Create Response object
    const response_obj = c.hermes_value_create_object(runtime);
    if (response_obj == null) {
        c.hermes_throw_error(runtime, "Failed to create response object");
        return null;
    }

    // status
    const status: u16 = @intFromEnum(result.status);
    c.hermes_value_set_property(
        runtime,
        response_obj,
        "status",
        c.hermes_value_create_number(runtime, @floatFromInt(status)),
    );

    // ok (status 200-299)
    c.hermes_value_set_property(
        runtime,
        response_obj,
        "ok",
        c.hermes_value_create_boolean(runtime, status >= 200 and status < 300),
    );

    // statusText
    const status_text = getStatusText(result.status);
    c.hermes_value_set_property(
        runtime,
        response_obj,
        "statusText",
        c.hermes_value_create_string(runtime, status_text.ptr, status_text.len),
    );

    // _body (internal, used by text() and json())
    c.hermes_value_set_property(
        runtime,
        response_obj,
        "_body",
        c.hermes_value_create_string(runtime, response_body.ptr, response_body.len),
    );

    // headers object (simplified)
    const headers_obj = c.hermes_value_create_object(runtime);
    if (headers_obj != null) {
        c.hermes_value_set_property(runtime, response_obj, "headers", headers_obj);
    }

    return response_obj;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn parseMethod(method_str: []const u8) std.http.Method {
    if (std.mem.eql(u8, method_str, "GET")) return .GET;
    if (std.mem.eql(u8, method_str, "POST")) return .POST;
    if (std.mem.eql(u8, method_str, "PUT")) return .PUT;
    if (std.mem.eql(u8, method_str, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, method_str, "PATCH")) return .PATCH;
    if (std.mem.eql(u8, method_str, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, method_str, "OPTIONS")) return .OPTIONS;
    return .GET;
}

fn getStatusText(status: std.http.Status) []const u8 {
    return switch (status) {
        .ok => "OK",
        .created => "Created",
        .accepted => "Accepted",
        .no_content => "No Content",
        .moved_permanently => "Moved Permanently",
        .found => "Found",
        .see_other => "See Other",
        .not_modified => "Not Modified",
        .bad_request => "Bad Request",
        .unauthorized => "Unauthorized",
        .forbidden => "Forbidden",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_server_error => "Internal Server Error",
        .bad_gateway => "Bad Gateway",
        .service_unavailable => "Service Unavailable",
        else => "Unknown",
    };
}

// ============================================================================
// Registration
// ============================================================================

pub fn register(runtime: *c.OVHermesRuntime, context: *FetchContext) void {
    // Register as global function (prefixed with __ for runtime.js wrapper)
    c.hermes_register_host_function(
        runtime,
        "__fetch",
        fetchFunction,
        @ptrCast(context),
    );
}
