/// LMDB Zig Bindings
/// Lightning Memory-Mapped Database for high-performance key-value storage
///
/// Key Design (DynamoDB-style patterns):
///   pattern:{id}           → JSON document
///   idx:tag:{tag}:{id}     → "" (secondary index)
///   edge:{from}:{rel}:{to} → metadata JSON
///   redge:{to}:{rel}:{from}→ "" (reverse index)
const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("lmdb.h");
});

pub const LmdbError = error{
    EnvCreate,
    EnvSetMapSize,
    EnvOpen,
    TxnBegin,
    TxnCommit,
    DbiOpen,
    Put,
    Get,
    Del,
    CursorOpen,
    CursorGet,
    NotFound,
    OutOfMemory,
    KeyTooLong,
};

/// Maximum key length (LMDB limit)
pub const MAX_KEY_LENGTH = 511;

/// LMDB Environment wrapper
pub const Env = struct {
    env: ?*c.MDB_env,
    dbi: c.MDB_dbi,
    allocator: Allocator,

    const Self = @This();

    /// Initialize LMDB environment
    pub fn init(allocator: Allocator, path: []const u8, max_size_mb: usize) !Self {
        var env: ?*c.MDB_env = null;

        // Create environment
        if (c.mdb_env_create(&env) != 0) {
            return LmdbError.EnvCreate;
        }
        errdefer _ = c.mdb_env_close(env);

        // Set max size
        const map_size = max_size_mb * 1024 * 1024;
        if (c.mdb_env_set_mapsize(env, map_size) != 0) {
            return LmdbError.EnvSetMapSize;
        }

        // Create directory if needed
        std.fs.makeDirAbsolute(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return LmdbError.EnvOpen,
        };

        // Open environment
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        if (c.mdb_env_open(env, path_z.ptr, 0, 0o644) != 0) {
            return LmdbError.EnvOpen;
        }

        // Open default database
        var txn: ?*c.MDB_txn = null;
        if (c.mdb_txn_begin(env, null, 0, &txn) != 0) {
            return LmdbError.TxnBegin;
        }

        var dbi: c.MDB_dbi = 0;
        if (c.mdb_dbi_open(txn, null, 0, &dbi) != 0) {
            _ = c.mdb_txn_abort(txn);
            return LmdbError.DbiOpen;
        }

        if (c.mdb_txn_commit(txn) != 0) {
            return LmdbError.TxnCommit;
        }

        return .{
            .env = env,
            .dbi = dbi,
            .allocator = allocator,
        };
    }

    /// Close environment
    pub fn deinit(self: *Self) void {
        if (self.env) |env| {
            c.mdb_dbi_close(env, self.dbi);
            c.mdb_env_close(env);
            self.env = null;
        }
    }

    // =========================================================================
    // Transaction API - Use for atomic batch operations
    // =========================================================================

    /// Begin a new transaction for batch operations
    pub fn beginTransaction(self: *Self) !Transaction {
        var txn: ?*c.MDB_txn = null;
        if (c.mdb_txn_begin(self.env, null, 0, &txn) != 0) {
            return LmdbError.TxnBegin;
        }
        return .{
            .txn = txn,
            .dbi = self.dbi,
            .committed = false,
        };
    }

    /// Begin a read-only transaction
    pub fn beginReadTransaction(self: *Self) !ReadTransaction {
        var txn: ?*c.MDB_txn = null;
        if (c.mdb_txn_begin(self.env, null, c.MDB_RDONLY, &txn) != 0) {
            return LmdbError.TxnBegin;
        }
        return .{
            .txn = txn,
            .dbi = self.dbi,
        };
    }

    // =========================================================================
    // Simple API - Each operation is its own transaction
    // =========================================================================

    /// Put a key-value pair (single transaction)
    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        if (key.len > MAX_KEY_LENGTH) return LmdbError.KeyTooLong;

        var txn = try self.beginTransaction();
        errdefer txn.abort();
        try txn.put(key, value);
        try txn.commit();
    }

    /// Get a value by key (returns owned slice)
    pub fn get(self: *Self, key: []const u8) ![]const u8 {
        var txn = try self.beginReadTransaction();
        defer txn.abort();
        return txn.getOwned(self.allocator, key);
    }

    /// Delete a key
    pub fn delete(self: *Self, key: []const u8) !void {
        var txn = try self.beginTransaction();
        errdefer txn.abort();
        try txn.delete(key);
        try txn.commit();
    }

    /// Check if key exists
    pub fn exists(self: *Self, key: []const u8) bool {
        var txn = self.beginReadTransaction() catch return false;
        defer txn.abort();
        return txn.exists(key);
    }

    /// Iterate over keys with a given prefix
    pub fn iteratePrefix(self: *Self, prefix: []const u8) !PrefixIterator {
        return PrefixIterator.init(self, prefix);
    }
};

/// Read-write transaction for batch operations
pub const Transaction = struct {
    txn: ?*c.MDB_txn,
    dbi: c.MDB_dbi,
    committed: bool,

    const Self = @This();

    /// Put a key-value pair within this transaction
    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        if (key.len > MAX_KEY_LENGTH) return LmdbError.KeyTooLong;

        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var v = c.MDB_val{
            .mv_size = value.len,
            .mv_data = @constCast(@ptrCast(value.ptr)),
        };

        if (c.mdb_put(self.txn, self.dbi, &k, &v, 0) != 0) {
            return LmdbError.Put;
        }
    }

    /// Delete a key within this transaction
    pub fn delete(self: *Self, key: []const u8) !void {
        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };

        const rc = c.mdb_del(self.txn, self.dbi, &k, null);
        if (rc == c.MDB_NOTFOUND) {
            return LmdbError.NotFound;
        }
        if (rc != 0) {
            return LmdbError.Del;
        }
    }

    /// Delete a key if it exists (no error if missing)
    pub fn deleteIfExists(self: *Self, key: []const u8) !void {
        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };

        const rc = c.mdb_del(self.txn, self.dbi, &k, null);
        if (rc != 0 and rc != c.MDB_NOTFOUND) {
            return LmdbError.Del;
        }
    }

    /// Commit the transaction (all or nothing)
    pub fn commit(self: *Self) !void {
        if (self.committed) return;
        if (c.mdb_txn_commit(self.txn) != 0) {
            return LmdbError.TxnCommit;
        }
        self.committed = true;
        self.txn = null;
    }

    /// Abort the transaction (rollback all changes)
    pub fn abort(self: *Self) void {
        if (self.committed) return;
        if (self.txn) |txn| {
            _ = c.mdb_txn_abort(txn);
            self.txn = null;
        }
    }
};

/// Read-only transaction
pub const ReadTransaction = struct {
    txn: ?*c.MDB_txn,
    dbi: c.MDB_dbi,

    const Self = @This();

    /// Get a value (returns slice pointing to mmap - valid until abort)
    pub fn get(self: *Self, key: []const u8) ![]const u8 {
        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var v: c.MDB_val = undefined;

        const rc = c.mdb_get(self.txn, self.dbi, &k, &v);
        if (rc == c.MDB_NOTFOUND) {
            return LmdbError.NotFound;
        }
        if (rc != 0) {
            return LmdbError.Get;
        }

        const data: [*]const u8 = @ptrCast(v.mv_data);
        return data[0..v.mv_size];
    }

    /// Get a value (returns owned copy)
    pub fn getOwned(self: *Self, allocator: Allocator, key: []const u8) ![]const u8 {
        const data = try self.get(key);
        return allocator.dupe(u8, data) catch return LmdbError.OutOfMemory;
    }

    /// Check if key exists
    pub fn exists(self: *Self, key: []const u8) bool {
        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var v: c.MDB_val = undefined;
        return c.mdb_get(self.txn, self.dbi, &k, &v) == 0;
    }

    /// Abort/close the read transaction
    pub fn abort(self: *Self) void {
        if (self.txn) |txn| {
            _ = c.mdb_txn_abort(txn);
            self.txn = null;
        }
    }

    /// Create a cursor for iteration within this transaction
    pub fn cursor(self: *Self) !Cursor {
        var cur: ?*c.MDB_cursor = null;
        if (c.mdb_cursor_open(self.txn, self.dbi, &cur) != 0) {
            return LmdbError.CursorOpen;
        }
        return .{ .cursor = cur };
    }
};

/// Cursor for iteration
pub const Cursor = struct {
    cursor: ?*c.MDB_cursor,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    /// Position at or after the given key
    pub fn seek(self: *Cursor, key: []const u8) ?Entry {
        var k = c.MDB_val{
            .mv_size = key.len,
            .mv_data = @constCast(@ptrCast(key.ptr)),
        };
        var v: c.MDB_val = undefined;

        if (c.mdb_cursor_get(self.cursor, &k, &v, c.MDB_SET_RANGE) != 0) {
            return null;
        }

        const key_data: [*]const u8 = @ptrCast(k.mv_data);
        const value_data: [*]const u8 = @ptrCast(v.mv_data);
        return .{
            .key = key_data[0..k.mv_size],
            .value = value_data[0..v.mv_size],
        };
    }

    /// Move to next entry
    pub fn next(self: *Cursor) ?Entry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;

        if (c.mdb_cursor_get(self.cursor, &k, &v, c.MDB_NEXT) != 0) {
            return null;
        }

        const key_data: [*]const u8 = @ptrCast(k.mv_data);
        const value_data: [*]const u8 = @ptrCast(v.mv_data);
        return .{
            .key = key_data[0..k.mv_size],
            .value = value_data[0..v.mv_size],
        };
    }

    pub fn deinit(self: *Cursor) void {
        if (self.cursor) |cur| {
            c.mdb_cursor_close(cur);
            self.cursor = null;
        }
    }
};

/// Iterator for prefix scans (owns its transaction)
pub const PrefixIterator = struct {
    txn: ReadTransaction,
    cursor: Cursor,
    prefix: []const u8, // Owned copy
    allocator: Allocator,
    started: bool,
    exhausted: bool,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(env: *Env, prefix: []const u8) !PrefixIterator {
        // Own the prefix to avoid lifetime issues
        const prefix_copy = try env.allocator.dupe(u8, prefix);
        errdefer env.allocator.free(prefix_copy);

        var txn = try env.beginReadTransaction();
        errdefer txn.abort();

        var cursor = try txn.cursor();

        return .{
            .txn = txn,
            .cursor = cursor,
            .prefix = prefix_copy,
            .allocator = env.allocator,
            .started = false,
            .exhausted = false,
        };
    }

    pub fn next(self: *PrefixIterator) ?Entry {
        if (self.exhausted) return null;

        const entry = if (!self.started) blk: {
            self.started = true;
            break :blk self.cursor.seek(self.prefix);
        } else self.cursor.next();

        if (entry) |e| {
            // Check if key still starts with prefix
            if (e.key.len >= self.prefix.len and
                std.mem.startsWith(u8, e.key, self.prefix))
            {
                return e;
            }
        }

        self.exhausted = true;
        return null;
    }

    /// Collect all matching entries (caller owns returned slices)
    pub fn collectAll(self: *PrefixIterator) !std.ArrayList(Entry) {
        var results = std.ArrayList(Entry).init(self.allocator);
        errdefer results.deinit();

        while (self.next()) |entry| {
            try results.append(.{
                .key = try self.allocator.dupe(u8, entry.key),
                .value = try self.allocator.dupe(u8, entry.value),
            });
        }

        return results;
    }

    pub fn deinit(self: *PrefixIterator) void {
        self.cursor.deinit();
        self.txn.abort();
        self.allocator.free(self.prefix);
    }
};

// =============================================================================
// Key Escaping - Prevents parsing bugs when keys contain ':'
// =============================================================================

/// Escape a key component (replaces ':' with '\:' and '\' with '\\')
pub fn escapeKeyComponent(allocator: Allocator, component: []const u8) ![]const u8 {
    // Count escapes needed
    var escape_count: usize = 0;
    for (component) |ch| {
        if (ch == ':' or ch == '\\') escape_count += 1;
    }

    if (escape_count == 0) {
        return allocator.dupe(u8, component);
    }

    const result = try allocator.alloc(u8, component.len + escape_count);
    var i: usize = 0;
    for (component) |ch| {
        if (ch == ':' or ch == '\\') {
            result[i] = '\\';
            i += 1;
        }
        result[i] = ch;
        i += 1;
    }

    return result;
}

/// Unescape a key component
pub fn unescapeKeyComponent(allocator: Allocator, escaped: []const u8) ![]const u8 {
    // Count actual characters
    var len: usize = 0;
    var i: usize = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\' and i + 1 < escaped.len) {
            i += 1; // Skip the escaped char
        }
        len += 1;
    }

    if (len == escaped.len) {
        return allocator.dupe(u8, escaped);
    }

    const result = try allocator.alloc(u8, len);
    var j: usize = 0;
    i = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\' and i + 1 < escaped.len) {
            i += 1;
        }
        result[j] = escaped[i];
        j += 1;
    }

    return result;
}

// =============================================================================
// Tests
// =============================================================================

test "lmdb basic operations" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var env = try Env.init(allocator, path, 10);
    defer env.deinit();

    // Put and get
    try env.put("test:key", "test value");
    const value = try env.get("test:key");
    defer allocator.free(value);

    try std.testing.expectEqualStrings("test value", value);

    // Check exists
    try std.testing.expect(env.exists("test:key"));
    try std.testing.expect(!env.exists("nonexistent"));
}

test "lmdb transaction batch" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var env = try Env.init(allocator, path, 10);
    defer env.deinit();

    // Batch write in single transaction
    {
        var txn = try env.beginTransaction();
        errdefer txn.abort();

        try txn.put("batch:1", "value1");
        try txn.put("batch:2", "value2");
        try txn.put("batch:3", "value3");

        try txn.commit();
    }

    // Verify all written
    try std.testing.expect(env.exists("batch:1"));
    try std.testing.expect(env.exists("batch:2"));
    try std.testing.expect(env.exists("batch:3"));
}

test "lmdb transaction rollback" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var env = try Env.init(allocator, path, 10);
    defer env.deinit();

    // Write then abort
    {
        var txn = try env.beginTransaction();
        try txn.put("rollback:key", "value");
        txn.abort(); // Don't commit
    }

    // Should not exist
    try std.testing.expect(!env.exists("rollback:key"));
}

test "key escaping" {
    const allocator = std.testing.allocator;

    const escaped = try escapeKeyComponent(allocator, "foo:bar\\baz");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings("foo\\:bar\\\\baz", escaped);

    const unescaped = try unescapeKeyComponent(allocator, escaped);
    defer allocator.free(unescaped);
    try std.testing.expectEqualStrings("foo:bar\\baz", unescaped);
}
