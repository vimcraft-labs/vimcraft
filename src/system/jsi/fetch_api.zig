/// Async Fetch API for JavaScript plugins
/// Provides Browser-compatible HTTP fetch functionality with Promise support
/// Uses libuv work queue for non-blocking HTTP requests (React Native pattern)
///
/// Addresses:
/// - Thread-safe request tracking for proper shutdown
/// - Response size limits to prevent OOM
/// - Cancellation support via AbortController pattern
/// - Proper error propagation to JavaScript Promises
///
/// Limitations:
/// - Headers limited to predefined whitelist (Hermes lacks property enumeration)
const std = @import("std");
const c = @import("c_api.zig").c;
const debug_log = @import("../../backends/headless/log.zig");

// Import libuv
const uv = @cImport({
    @cInclude("uv.h");
});

// Import event loop module
const event_loop = @import("../event_loop/libuv.zig");

// ============================================================================
// Configuration Constants
// ============================================================================

/// Maximum response body size in bytes (10 MB)
const MAX_RESPONSE_SIZE: usize = 10 * 1024 * 1024;

/// Maximum number of concurrent fetch requests
const MAX_CONCURRENT_REQUESTS: usize = 64;

// ============================================================================
// Context and Options
// ============================================================================

/// Context passed to fetch function
pub const FetchContext = struct {
    allocator: std.mem.Allocator,
};

// ============================================================================
// Fetch Result Queue (Thread-Safe)
// ============================================================================

/// Result of an async fetch operation
const FetchResult = struct {
    fetch_id: usize,
    success: bool,
    status: u16,
    status_text: []const u8,
    body: []const u8,
    error_msg: ?[]const u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *FetchResult) void {
        if (self.status_text.len > 0) {
            self.allocator.free(self.status_text);
        }
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
        if (self.error_msg) |msg| {
            self.allocator.free(msg);
        }
    }
};

/// Thread-safe fetch result queue (React Native style)
/// libuv work callbacks add results here, main thread processes them
const FetchQueue = struct {
    mutex: std.Thread.Mutex = .{},
    pending_results: std.ArrayList(FetchResult),
    /// Track failed enqueues so we can reject Promises
    failed_ids: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) FetchQueue {
        return .{
            .pending_results = .empty,
            .failed_ids = .empty,
            .allocator = allocator,
        };
    }

    fn deinit(self: *FetchQueue) void {
        // Clean up any pending results
        for (self.pending_results.items) |*result| {
            result.deinit();
        }
        self.pending_results.deinit(self.allocator);
        self.failed_ids.deinit(self.allocator);
    }

    /// Add fetch result to queue (called from libuv worker thread)
    /// Returns false if enqueue failed (will be tracked for error reporting)
    fn enqueue(self: *FetchQueue, result: FetchResult) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pending_results.append(self.allocator, result) catch {
            // Track this ID for error reporting
            debug_log.log("[FETCH] CRITICAL: Failed to enqueue result for id={d}, OOM", .{result.fetch_id});
            self.failed_ids.append(self.allocator, result.fetch_id) catch {};
            // Clean up the result we couldn't enqueue
            var mutable_result = result;
            mutable_result.deinit();
            return false;
        };
        return true;
    }

    /// Get all pending results (called from main thread)
    fn dequeueAll(self: *FetchQueue, allocator: std.mem.Allocator) !struct {
        results: std.ArrayList(FetchResult),
        failed_ids: std.ArrayList(usize),
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var results: std.ArrayList(FetchResult) = .empty;
        var failed: std.ArrayList(usize) = .empty;

        try results.appendSlice(allocator, self.pending_results.items);
        try failed.appendSlice(allocator, self.failed_ids.items);

        self.pending_results.clearRetainingCapacity();
        self.failed_ids.clearRetainingCapacity();

        return .{ .results = results, .failed_ids = failed };
    }
};

// ============================================================================
// In-Flight Request Tracking (for proper shutdown)
// ============================================================================

/// Tracks in-flight requests for cancellation and cleanup
const InFlightTracker = struct {
    mutex: std.Thread.Mutex = .{},
    /// Map of fetch_id -> work_data pointer for cancellation
    requests: std.AutoHashMap(usize, *FetchWorkData),
    allocator: std.mem.Allocator,
    /// Flag to reject new requests during shutdown
    shutting_down: bool = false,

    fn init(allocator: std.mem.Allocator) InFlightTracker {
        return .{
            .requests = std.AutoHashMap(usize, *FetchWorkData).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *InFlightTracker) void {
        self.requests.deinit();
    }

    /// Register a new in-flight request
    fn register(self: *InFlightTracker, fetch_id: usize, work_data: *FetchWorkData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.shutting_down) {
            return error.ShuttingDown;
        }

        if (self.requests.count() >= MAX_CONCURRENT_REQUESTS) {
            return error.TooManyRequests;
        }

        try self.requests.put(fetch_id, work_data);
    }

    /// Unregister a completed request
    fn unregister(self: *InFlightTracker, fetch_id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.requests.remove(fetch_id);
    }

    /// Mark a request as cancelled
    fn cancel(self: *InFlightTracker, fetch_id: usize) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.requests.get(fetch_id)) |work_data| {
            work_data.cancelled = true;
            return true;
        }
        return false;
    }

    /// Cancel all in-flight requests (for shutdown)
    fn cancelAll(self: *InFlightTracker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.shutting_down = true;

        var iter = self.requests.valueIterator();
        while (iter.next()) |work_data| {
            work_data.*.cancelled = true;
        }
    }

    /// Get count of in-flight requests
    fn count(self: *InFlightTracker) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.requests.count();
    }
};

// ============================================================================
// Module State
// ============================================================================

var fetch_allocator: std.mem.Allocator = undefined;
var fetch_runtime: ?*c.OVHermesRuntime = null;
var fetch_initialized = false;
var fetch_queue: FetchQueue = undefined;
var fetch_queue_initialized = false;
var in_flight: InFlightTracker = undefined;
var in_flight_initialized = false;

// ============================================================================
// libuv Work Request Data
// ============================================================================

/// Data passed to libuv work queue
const FetchWorkData = struct {
    // Input
    fetch_id: usize,
    url: []const u8,
    method: std.http.Method,
    headers: std.ArrayList(std.http.Header),
    body: ?[]const u8,
    allocator: std.mem.Allocator,
    max_response_size: usize,

    // Cancellation flag (checked by worker)
    cancelled: bool = false,

    // Output (filled by worker)
    result_status: u16 = 0,
    result_status_text: []const u8 = "",
    result_body: []const u8 = "",
    result_error: ?[]const u8 = null,
    success: bool = false,

    // libuv work request
    work: uv.uv_work_t = undefined,

    fn deinitInput(self: *FetchWorkData) void {
        self.allocator.free(self.url);
        for (self.headers.items) |header| {
            // header.name is a static string, only free value
            self.allocator.free(header.value);
        }
        self.headers.deinit(self.allocator);
        if (self.body) |b| {
            self.allocator.free(b);
        }
    }
};

// ============================================================================
// libuv Worker Functions
// ============================================================================

/// Worker function - runs in thread pool, does HTTP request
/// Uses Zig 0.15 std.http.Client.fetch() API with Writer.Allocating
fn fetchWorker(req: [*c]uv.uv_work_t) callconv(.c) void {
    const work_data: *FetchWorkData = @ptrCast(@alignCast(req.*.data));

    // Check if cancelled before starting
    if (work_data.cancelled) {
        work_data.success = false;
        work_data.result_error = work_data.allocator.dupe(u8, "Request cancelled") catch null;
        return;
    }

    debug_log.log("[FETCH] Worker starting for id={d}, url={s}", .{ work_data.fetch_id, work_data.url });

    // Create HTTP client
    var client = std.http.Client{ .allocator = work_data.allocator };
    defer client.deinit();

    // Create allocating writer for capturing response body (Zig 0.15 pattern)
    var allocating_writer: std.Io.Writer.Allocating = .init(work_data.allocator);
    defer allocating_writer.deinit();

    // Perform fetch request using Zig 0.15 API
    const result = client.fetch(.{
        .location = .{ .url = work_data.url },
        .method = work_data.method,
        .payload = work_data.body,
        .extra_headers = work_data.headers.items,
        .response_writer = &allocating_writer.writer,
    }) catch |err| {
        work_data.success = false;
        work_data.result_error = std.fmt.allocPrint(work_data.allocator, "Fetch failed: {}", .{err}) catch null;
        work_data.result_status = 0;
        work_data.result_status_text = "";
        work_data.result_body = "";
        return;
    };

    // Check if cancelled after request completed
    if (work_data.cancelled) {
        work_data.success = false;
        work_data.result_error = work_data.allocator.dupe(u8, "Request cancelled") catch null;
        return;
    }

    // Check response size limit
    const response_body = allocating_writer.written();
    if (response_body.len > work_data.max_response_size) {
        work_data.success = false;
        work_data.result_error = std.fmt.allocPrint(
            work_data.allocator,
            "Response too large: {d} bytes exceeds limit of {d} bytes",
            .{ response_body.len, work_data.max_response_size },
        ) catch null;
        work_data.result_status = 0;
        work_data.result_status_text = "";
        work_data.result_body = "";
        return;
    }

    // Get status
    const status: u16 = @intFromEnum(result.status);
    work_data.result_status = status;
    work_data.result_status_text = work_data.allocator.dupe(u8, getStatusText(result.status)) catch "";

    // Copy response body from allocating writer
    // Note: This is a necessary copy because allocating_writer.deinit() will free
    // the original buffer, but we need result_body to survive for the completion callback.
    // The copy is owned by work_data and transferred to FetchResult.
    work_data.result_body = work_data.allocator.dupe(u8, response_body) catch "";
    work_data.success = true;
    work_data.result_error = null;

    debug_log.log("[FETCH] Worker completed id={d}, status={d}, body_size={d}", .{
        work_data.fetch_id,
        status,
        response_body.len,
    });
}

/// Completion callback - runs on main thread after worker completes
fn fetchComplete(req: [*c]uv.uv_work_t, status: c_int) callconv(.c) void {
    const work_data: *FetchWorkData = @ptrCast(@alignCast(req.*.data));

    debug_log.log("[FETCH] Complete callback for id={d}, uv_status={d}", .{ work_data.fetch_id, status });

    // Unregister from in-flight tracker
    if (in_flight_initialized) {
        in_flight.unregister(work_data.fetch_id);
    }

    // Handle libuv errors (e.g., UV_ECANCELED)
    if (status != 0) {
        // Use existing error from worker if available, otherwise create new one
        // This avoids leaking the error string allocated in fetchWorker
        const error_msg = work_data.result_error orelse
            (work_data.allocator.dupe(u8, "Request cancelled or failed") catch null);

        // Free any result strings that may have been allocated before cancellation
        if (work_data.result_status_text.len > 0) {
            work_data.allocator.free(work_data.result_status_text);
        }
        if (work_data.result_body.len > 0) {
            work_data.allocator.free(work_data.result_body);
        }

        var result = FetchResult{
            .fetch_id = work_data.fetch_id,
            .success = false,
            .status = 0,
            .status_text = "",
            .body = "",
            .error_msg = error_msg,
            .allocator = work_data.allocator,
        };
        if (fetch_queue_initialized) {
            _ = fetch_queue.enqueue(result);
        } else {
            // Queue not available (shutdown), clean up result
            result.deinit();
        }
    } else {
        // Enqueue result to be processed by main thread
        var result = FetchResult{
            .fetch_id = work_data.fetch_id,
            .success = work_data.success,
            .status = work_data.result_status,
            .status_text = work_data.result_status_text,
            .body = work_data.result_body,
            .error_msg = work_data.result_error,
            .allocator = work_data.allocator,
        };

        if (fetch_queue_initialized) {
            // Note: If enqueue fails, the result will be tracked and
            // Promise will be rejected in processQueue
            _ = fetch_queue.enqueue(result);
        } else {
            // Queue not available (shutdown), clean up result
            result.deinit();
        }
    }

    // Clean up work data input (result strings moved to queue)
    work_data.deinitInput();
    work_data.allocator.destroy(work_data);
}

// ============================================================================
// Process Queue (Called from Main Thread)
// ============================================================================

/// Process fetch result queue and call JavaScript callbacks
/// MUST be called from main thread (where JSI runtime was created)
pub fn processQueue(allocator: std.mem.Allocator) void {
    if (!fetch_initialized or !fetch_queue_initialized) return;

    const rt = fetch_runtime orelse return;

    // Get all pending results from queue (thread-safe)
    const dequeued = fetch_queue.dequeueAll(allocator) catch return;
    var pending = dequeued.results;
    var failed_ids = dequeued.failed_ids;

    defer {
        for (pending.items) |*result| {
            result.deinit();
        }
        pending.deinit(allocator);
        failed_ids.deinit(allocator);
    }

    // Process failed enqueues first (reject those Promises)
    for (failed_ids.items) |failed_id| {
        rejectPromise(rt, failed_id, "Internal error: failed to queue result (out of memory)");
    }

    if (pending.items.len == 0) return;

    debug_log.log("[FETCH] processQueue: {d} results to process", .{pending.items.len});

    // Process each result
    for (pending.items) |*result| {
        deliverResult(rt, result);
    }

    // CRITICAL: Drain microtask queue after delivering results
    // When deliverResult calls __handleFetchCallback, it invokes resolve(response)
    // which schedules the Promise's .then() callback as a microtask.
    // Hermes requires explicit draining of the microtask queue for Promise
    // continuation callbacks to execute. Without this, .then() never fires.
    // See: facebook/react-native#33006, realm/realm-js#6768
    _ = c.hermes_drain_microtasks(rt, -1);

    debug_log.log("[FETCH] processQueue: microtasks drained", .{});
}

/// Deliver a single result to JavaScript
fn deliverResult(rt: *c.OVHermesRuntime, result: *FetchResult) void {
    debug_log.log("[FETCH] deliverResult: starting for id={d}", .{result.fetch_id});

    // Get global object
    const global = c.hermes_get_global_object(rt);
    if (global == null) {
        debug_log.log("[FETCH] deliverResult: FAILED - global object is null", .{});
        return;
    }
    defer c.hermes_object_destroy(global);

    // Get __handleFetchCallback function
    const callback_fn = c.hermes_object_get_property(rt, global, "__handleFetchCallback");
    if (callback_fn == null) {
        debug_log.log("[FETCH] deliverResult: FAILED - __handleFetchCallback not found on global", .{});
        return;
    }
    defer c.hermes_value_destroy(callback_fn);

    // Verify it's a function
    if (!c.hermes_value_is_function(rt, callback_fn)) {
        debug_log.log("[FETCH] deliverResult: FAILED - __handleFetchCallback is not a function", .{});
        return;
    }
    debug_log.log("[FETCH] deliverResult: found __handleFetchCallback function", .{});

    // Create result object for JavaScript
    const result_obj = c.hermes_value_create_object(rt);
    if (result_obj == null) return;
    defer c.hermes_value_destroy(result_obj);

    // Set result properties
    const success_val = c.hermes_value_create_boolean(rt, result.success);
    if (success_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "success", v);
        c.hermes_value_destroy(v);
    }

    const status_val = c.hermes_value_create_number(rt, @floatFromInt(result.status));
    if (status_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "status", v);
        c.hermes_value_destroy(v);
    }

    const status_text_val = c.hermes_value_create_string(rt, result.status_text.ptr, result.status_text.len);
    if (status_text_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "statusText", v);
        c.hermes_value_destroy(v);
    }

    const body_val = c.hermes_value_create_string(rt, result.body.ptr, result.body.len);
    if (body_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "body", v);
        c.hermes_value_destroy(v);
    }

    if (result.error_msg) |err| {
        const err_val = c.hermes_value_create_string(rt, err.ptr, err.len);
        if (err_val) |v| {
            c.hermes_value_set_property(rt, result_obj, "error", v);
            c.hermes_value_destroy(v);
        }
    } else {
        const null_val = c.hermes_value_create_null(rt);
        if (null_val) |v| {
            c.hermes_value_set_property(rt, result_obj, "error", v);
            c.hermes_value_destroy(v);
        }
    }

    // Create fetch ID argument
    const id_arg = c.hermes_value_create_number(rt, @floatFromInt(result.fetch_id));
    if (id_arg == null) return;
    defer c.hermes_value_destroy(id_arg);

    // Call __handleFetchCallback(id, result)
    var args = [_]?*c.OVHermesValue{ id_arg, result_obj };
    const call_result = c.hermes_call_function(rt, callback_fn, &args, 2);

    if (call_result != null) {
        c.hermes_value_destroy(call_result);
    }

    debug_log.log("[FETCH] Callback executed for id={d}", .{result.fetch_id});
}

/// Reject a Promise directly (for error cases where we can't enqueue)
fn rejectPromise(rt: *c.OVHermesRuntime, fetch_id: usize, error_msg: []const u8) void {
    const global = c.hermes_get_global_object(rt);
    if (global == null) return;
    defer c.hermes_object_destroy(global);

    const callback_fn = c.hermes_object_get_property(rt, global, "__handleFetchCallback");
    if (callback_fn == null) return;
    defer c.hermes_value_destroy(callback_fn);

    if (!c.hermes_value_is_function(rt, callback_fn)) return;

    // Create error result
    const result_obj = c.hermes_value_create_object(rt);
    if (result_obj == null) return;
    defer c.hermes_value_destroy(result_obj);

    const success_val = c.hermes_value_create_boolean(rt, false);
    if (success_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "success", v);
        c.hermes_value_destroy(v);
    }

    const err_val = c.hermes_value_create_string(rt, error_msg.ptr, error_msg.len);
    if (err_val) |v| {
        c.hermes_value_set_property(rt, result_obj, "error", v);
        c.hermes_value_destroy(v);
    }

    const id_arg = c.hermes_value_create_number(rt, @floatFromInt(fetch_id));
    if (id_arg == null) return;
    defer c.hermes_value_destroy(id_arg);

    var args = [_]?*c.OVHermesValue{ id_arg, result_obj };
    const call_result = c.hermes_call_function(rt, callback_fn, &args, 2);
    if (call_result != null) {
        c.hermes_value_destroy(call_result);
    }

    debug_log.log("[FETCH] Rejected Promise for id={d}: {s}", .{ fetch_id, error_msg });
}

// ============================================================================
// Native Fetch Function
// ============================================================================

/// __nativeFetch(id, url, options) - Start async HTTP request
/// Called from JavaScript, returns immediately
/// Result delivered via __handleFetchCallback when complete
pub export fn nativeFetchAsync(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 2) {
        c.hermes_throw_error(runtime, "__nativeFetch requires at least 2 arguments (id, url)");
        return null;
    }

    if (!fetch_initialized) {
        c.hermes_throw_error(runtime, "Fetch system not initialized");
        return null;
    }

    const loop = event_loop.getLoop() orelse {
        c.hermes_throw_error(runtime, "Event loop not available");
        return null;
    };

    // Check if shutting down
    if (in_flight_initialized and in_flight.shutting_down) {
        c.hermes_throw_error(runtime, "Fetch system is shutting down");
        return null;
    }

    // Arg 0: fetch ID (JavaScript-provided)
    const id_value = args[0] orelse {
        c.hermes_throw_error(runtime, "Invalid fetch ID");
        return null;
    };
    const fetch_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    // Arg 1: URL string
    const url_value = args[1] orelse {
        c.hermes_throw_error(runtime, "Invalid URL argument");
        return null;
    };
    var url_len: usize = 0;
    const url_ptr = c.hermes_value_get_string(runtime, url_value, &url_len);
    if (url_ptr == null or url_len == 0) {
        c.hermes_throw_error(runtime, "Failed to get URL string");
        return null;
    }

    // Copy URL string
    const url = fetch_allocator.dupe(u8, url_ptr[0..url_len]) catch {
        c.hermes_throw_error(runtime, "Failed to allocate URL");
        return null;
    };

    // Parse options (arg 2, optional)
    var method: std.http.Method = .GET;
    var request_body: ?[]const u8 = null;
    var extra_headers: std.ArrayList(std.http.Header) = .empty;
    var max_response_size: usize = MAX_RESPONSE_SIZE;

    if (arg_count >= 3) {
        const opts_val = args[2];
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
                    request_body = fetch_allocator.dupe(u8, body_ptr[0..body_len]) catch null;
                }
            }
            if (body_prop != null) c.hermes_value_destroy(body_prop);

            // Note: timeout option intentionally not implemented
            // Zig's std.http.Client doesn't support request timeouts
            // Would require async cancellation or lower-level socket control

            // Get maxResponseSize (optional)
            const max_size_prop = c.hermes_value_get_property(runtime, opts_val, "maxResponseSize");
            if (max_size_prop != null and c.hermes_value_is_number(max_size_prop)) {
                max_response_size = @intFromFloat(c.hermes_value_get_number(max_size_prop));
            }
            if (max_size_prop != null) c.hermes_value_destroy(max_size_prop);

            // Get headers - check known header names
            // LIMITATION: Hermes doesn't expose object property enumeration to C API,
            // so we can only check a predefined list of common headers.
            // Headers not in this list will be silently ignored.
            // To add support for a new header, add it to header_names below.
            const headers_prop = c.hermes_value_get_property(runtime, opts_val, "headers");
            if (headers_prop != null and c.hermes_value_is_object(headers_prop)) {
                const header_names = [_][]const u8{
                    "Content-Type",
                    "Accept",
                    "Authorization",
                    "User-Agent",
                    "X-API-Key",
                    "X-Request-ID",
                    "Cache-Control",
                    "If-None-Match",
                    "If-Modified-Since",
                    "Cookie",
                    "Origin",
                    "Referer",
                    "X-Requested-With",
                    "X-Custom-Header",
                    "X-Auth-Token",
                    "Bearer",
                    "Api-Key",
                    "X-Correlation-ID",
                    "X-Trace-ID",
                    "Accept-Language",
                    "Accept-Encoding",
                };

                for (header_names) |header_name| {
                    const header_val = c.hermes_value_get_property(runtime, headers_prop, header_name.ptr);
                    if (header_val != null and c.hermes_value_is_string(header_val)) {
                        var header_len: usize = 0;
                        const header_ptr = c.hermes_value_get_string(runtime, header_val, &header_len);
                        if (header_ptr != null and header_len > 0) {
                            const header_value = fetch_allocator.dupe(u8, header_ptr[0..header_len]) catch {
                                c.hermes_value_destroy(header_val);
                                continue;
                            };
                            extra_headers.append(fetch_allocator, .{
                                .name = header_name,
                                .value = header_value,
                            }) catch {
                                fetch_allocator.free(header_value);
                            };
                        }
                    }
                    if (header_val != null) c.hermes_value_destroy(header_val);
                }
            }
            if (headers_prop != null) c.hermes_value_destroy(headers_prop);
        }
    }

    debug_log.log("[FETCH] Starting async request id={d}, url={s}, method={s}", .{
        fetch_id,
        url,
        @tagName(method),
    });

    // Allocate work data
    const work_data = fetch_allocator.create(FetchWorkData) catch {
        fetch_allocator.free(url);
        if (request_body) |b| fetch_allocator.free(b);
        for (extra_headers.items) |h| fetch_allocator.free(h.value);
        extra_headers.deinit(fetch_allocator);
        c.hermes_throw_error(runtime, "Failed to allocate work data");
        return null;
    };

    work_data.* = FetchWorkData{
        .fetch_id = fetch_id,
        .url = url,
        .method = method,
        .headers = extra_headers,
        .body = request_body,
        .allocator = fetch_allocator,
        .max_response_size = max_response_size,
        .cancelled = false,
    };
    work_data.work.data = work_data;

    // Register in-flight request
    if (in_flight_initialized) {
        in_flight.register(fetch_id, work_data) catch |err| {
            work_data.deinitInput();
            fetch_allocator.destroy(work_data);
            switch (err) {
                error.ShuttingDown => c.hermes_throw_error(runtime, "Fetch system is shutting down"),
                error.TooManyRequests => c.hermes_throw_error(runtime, "Too many concurrent fetch requests"),
                else => c.hermes_throw_error(runtime, "Failed to register fetch request"),
            }
            return null;
        };
    }

    // Queue work to libuv thread pool
    const queue_result = uv.uv_queue_work(
        @ptrCast(loop),
        &work_data.work,
        fetchWorker,
        fetchComplete,
    );

    if (queue_result != 0) {
        // Clean up on failure
        if (in_flight_initialized) {
            in_flight.unregister(fetch_id);
        }
        work_data.deinitInput();
        fetch_allocator.destroy(work_data);
        c.hermes_throw_error(runtime, "Failed to queue fetch work");
        return null;
    }

    // Return undefined - result will be delivered via callback
    return c.hermes_value_create_undefined(runtime);
}

/// __abortFetch(id) - Cancel an in-flight fetch request
pub export fn abortFetchAsync(
    runtime: ?*c.OVHermesRuntime,
    context: ?*anyopaque,
    args: [*c]?*c.OVHermesValue,
    arg_count: usize,
) callconv(.c) ?*c.OVHermesValue {
    _ = context;

    if (arg_count < 1) {
        c.hermes_throw_error(runtime, "__abortFetch requires 1 argument (id)");
        return null;
    }

    if (!in_flight_initialized) {
        return c.hermes_value_create_boolean(runtime, false);
    }

    const id_value = args[0] orelse {
        return c.hermes_value_create_boolean(runtime, false);
    };
    const fetch_id = @as(usize, @intFromFloat(c.hermes_value_get_number(id_value)));

    const cancelled = in_flight.cancel(fetch_id);
    debug_log.log("[FETCH] Abort request for id={d}, found={}", .{ fetch_id, cancelled });

    return c.hermes_value_create_boolean(runtime, cancelled);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn parseMethod(method_str: []const u8) std.http.Method {
    if (std.ascii.eqlIgnoreCase(method_str, "GET")) return .GET;
    if (std.ascii.eqlIgnoreCase(method_str, "POST")) return .POST;
    if (std.ascii.eqlIgnoreCase(method_str, "PUT")) return .PUT;
    if (std.ascii.eqlIgnoreCase(method_str, "DELETE")) return .DELETE;
    if (std.ascii.eqlIgnoreCase(method_str, "PATCH")) return .PATCH;
    if (std.ascii.eqlIgnoreCase(method_str, "HEAD")) return .HEAD;
    if (std.ascii.eqlIgnoreCase(method_str, "OPTIONS")) return .OPTIONS;
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
// Initialization
// ============================================================================

/// Initialize fetch system
pub fn init(allocator: std.mem.Allocator, runtime: *c.OVHermesRuntime) void {
    fetch_allocator = allocator;
    fetch_runtime = runtime;
    fetch_initialized = true;

    if (!fetch_queue_initialized) {
        fetch_queue = FetchQueue.init(allocator);
        fetch_queue_initialized = true;
    }

    if (!in_flight_initialized) {
        in_flight = InFlightTracker.init(allocator);
        in_flight_initialized = true;
    }
}

/// Deinitialize fetch system - cancels all in-flight requests
pub fn deinit() void {
    if (!fetch_initialized) return;

    // Mark as shutting down and clean up tracker
    // NOTE: We intentionally do NOT free in-flight work_data here because:
    // 1. Worker threads may still be using it (race condition -> crash)
    // 2. The process is exiting anyway, OS will reclaim all memory
    // 3. Trying to wait for workers would block shutdown indefinitely
    if (in_flight_initialized) {
        in_flight.cancelAll(); // Sets cancelled flag for workers to check
        in_flight.deinit();
        in_flight_initialized = false;
    }

    if (fetch_queue_initialized) {
        fetch_queue.deinit();
        fetch_queue_initialized = false;
    }

    fetch_initialized = false;
    fetch_runtime = null;
}

/// Clear pending requests (for hot reload)
/// Unlike deinit(), this allows new requests after clearing
pub fn clearAll() void {
    if (!fetch_initialized or !fetch_queue_initialized) return;

    // Cancel all in-flight requests
    if (in_flight_initialized) {
        in_flight.cancelAll();
        // Reset shutdown flag - clearAll is for hot reload, not shutdown
        // This allows new requests after reloading plugins
        in_flight.mutex.lock();
        in_flight.shutting_down = false;
        in_flight.mutex.unlock();
    }

    // Clear the queue - any pending results will be dropped
    fetch_queue.mutex.lock();
    defer fetch_queue.mutex.unlock();

    for (fetch_queue.pending_results.items) |*result| {
        result.deinit();
    }
    fetch_queue.pending_results.clearRetainingCapacity();
    fetch_queue.failed_ids.clearRetainingCapacity();
}

/// Get count of in-flight requests (for debugging/monitoring)
pub fn getInFlightCount() usize {
    if (!in_flight_initialized) return 0;
    return in_flight.count();
}

/// Register fetch API functions with runtime
pub fn register(runtime: *c.OVHermesRuntime, ctx: *FetchContext) void {
    // Initialize fetch system
    init(ctx.allocator, runtime);

    // Register native fetch function (prefixed with __ for runtime.js wrapper)
    c.hermes_register_host_function(
        runtime,
        "__nativeFetch",
        nativeFetchAsync,
        null,
    );

    // Register abort function for cancellation support
    c.hermes_register_host_function(
        runtime,
        "__abortFetch",
        abortFetchAsync,
        null,
    );
}
