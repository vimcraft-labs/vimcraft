/// AI Memory Blocks
///
/// Dynamic memory blocks with temperature-based context budget management.
/// This is THE DIFFERENTIATOR - unlike static CLAUDE.md, mem blocks are:
///   - Dynamic: temperature controls inclusion
///   - Learned: LLM can self-edit via mem_append
///   - File-synced: AI.md auto-loads and watches for changes
///
/// Storage Schema (LMDB):
///   mem:block:{name}  → {content, temperature, source, file?, lastSync?}
///   mem:meta          → {budget, version}
///
const std = @import("std");
const Allocator = std.mem.Allocator;
const lmdb = @import("storage/lmdb.zig");
const provider = @import("providers/provider.zig");

pub const MemError = error{
    BlockNotFound,
    InvalidTemperature,
    InvalidBlockName,
    SerializationFailed,
    FileNotFound,
    FileReadError,
    StorageError,
    OutOfMemory,
} || lmdb.LmdbError || std.mem.Allocator.Error;

/// Block source type
pub const BlockSource = enum {
    manual, // User/LLM set directly
    learned, // LLM observed and learned
    file, // Synced from file (AI.md)
    auto, // Auto-generated (repo, context)

    pub fn toString(self: BlockSource) []const u8 {
        return switch (self) {
            .manual => "manual",
            .learned => "learned",
            .file => "file",
            .auto => "auto",
        };
    }

    pub fn fromString(s: []const u8) ?BlockSource {
        const map = std.StaticStringMap(BlockSource).initComptime(.{
            .{ "manual", .manual },
            .{ "learned", .learned },
            .{ "file", .file },
            .{ "auto", .auto },
        });
        return map.get(s);
    }
};

/// Memory block metadata
pub const Block = struct {
    name: []const u8,
    content: []const u8,
    temperature: f32, // 0.0 - 1.0, controls context inclusion
    source: BlockSource,
    file_path: ?[]const u8, // For file-synced blocks
    last_sync: ?i64, // Unix timestamp of last file sync
    tokens: u32, // Estimated token count

    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.content);
        if (self.file_path) |fp| self.allocator.free(fp);
    }

    /// Clone with new allocator
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        return .{
            .name = try allocator.dupe(u8, self.name),
            .content = try allocator.dupe(u8, self.content),
            .temperature = self.temperature,
            .source = self.source,
            .file_path = if (self.file_path) |fp| try allocator.dupe(u8, fp) else null,
            .last_sync = self.last_sync,
            .tokens = self.tokens,
            .allocator = allocator,
        };
    }
};

/// AI Memory Manager
pub const Memory = struct {
    db: lmdb.Env,
    allocator: Allocator,
    budget: u32, // Max tokens for all mem blocks

    const Self = @This();
    const BLOCK_PREFIX = "mem:block:";
    const META_KEY = "mem:meta";
    const DEFAULT_BUDGET: u32 = 4000;

    /// Initialize memory manager
    pub fn init(allocator: Allocator, db_path: []const u8) !Self {
        var db = try lmdb.Env.init(allocator, db_path, 64); // 64MB for mem blocks

        // Load or set default budget
        var budget: u32 = DEFAULT_BUDGET;
        if (db.get(META_KEY)) |meta_json| {
            defer allocator.free(meta_json);
            if (parseMetaJson(allocator, meta_json)) |meta| {
                budget = meta.budget;
            } else |_| {}
        } else |_| {}

        return .{
            .db = db,
            .allocator = allocator,
            .budget = budget,
        };
    }

    pub fn deinit(self: *Self) void {
        self.db.deinit();
    }

    // =========================================================================
    // Block Operations
    // =========================================================================

    /// Get a block by name
    pub fn get(self: *Self, name: []const u8) !Block {
        const key = try self.blockKey(name);
        defer self.allocator.free(key);

        const json = self.db.get(key) catch |err| {
            if (err == lmdb.LmdbError.NotFound) return MemError.BlockNotFound;
            return MemError.StorageError;
        };
        defer self.allocator.free(json);

        return parseBlockJson(self.allocator, name, json) catch MemError.SerializationFailed;
    }

    /// Get block content only (convenience)
    pub fn getContent(self: *Self, name: []const u8) ![]const u8 {
        var block = try self.get(name);
        const content = try self.allocator.dupe(u8, block.content);
        block.deinit();
        return content;
    }

    /// Set a block's content
    pub fn set(self: *Self, name: []const u8, content: []const u8) !void {
        // Check if block exists to preserve metadata
        var existing_temp: f32 = 0.5; // Default temperature
        var existing_source = BlockSource.manual;
        var existing_file: ?[]const u8 = null;

        if (self.get(name)) |existing| {
            existing_temp = existing.temperature;
            existing_source = existing.source;
            if (existing.file_path) |fp| {
                existing_file = try self.allocator.dupe(u8, fp);
            }
            var mut_existing = existing;
            mut_existing.deinit();
        } else |_| {}
        defer if (existing_file) |ef| self.allocator.free(ef);

        const block = Block{
            .name = name,
            .content = content,
            .temperature = existing_temp,
            .source = existing_source,
            .file_path = existing_file,
            .last_sync = if (existing_file != null) std.time.timestamp() else null,
            .tokens = estimateTokens(content),
            .allocator = self.allocator,
        };

        try self.saveBlock(&block);
    }

    /// Append content to a block
    pub fn append(self: *Self, name: []const u8, content: []const u8) !void {
        var existing = self.get(name) catch |err| {
            if (err == MemError.BlockNotFound) {
                // Create new block with appended content
                return self.set(name, content);
            }
            return err;
        };
        defer existing.deinit();

        // Append with newline separator
        const new_content = try std.fmt.allocPrint(
            self.allocator,
            "{s}\n{s}",
            .{ existing.content, content },
        );
        defer self.allocator.free(new_content);

        const block = Block{
            .name = name,
            .content = new_content,
            .temperature = existing.temperature,
            .source = if (existing.source == .manual) .learned else existing.source,
            .file_path = existing.file_path,
            .last_sync = existing.last_sync,
            .tokens = estimateTokens(new_content),
            .allocator = self.allocator,
        };

        try self.saveBlock(&block);
    }

    /// Delete a block
    pub fn delete(self: *Self, name: []const u8) !void {
        const key = try self.blockKey(name);
        defer self.allocator.free(key);

        self.db.delete(key) catch |err| {
            if (err == lmdb.LmdbError.NotFound) return MemError.BlockNotFound;
            return MemError.StorageError;
        };
    }

    /// List all block names
    pub fn list(self: *Self) !std.ArrayList([]const u8) {
        var names: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (names.items) |n| self.allocator.free(n);
            names.deinit(self.allocator);
        }

        var iter = try self.db.iteratePrefix(BLOCK_PREFIX);
        defer iter.deinit();

        while (iter.next()) |entry| {
            // Extract name from key (after prefix)
            if (entry.key.len > BLOCK_PREFIX.len) {
                const name = entry.key[BLOCK_PREFIX.len..];
                try names.append(self.allocator, try self.allocator.dupe(u8, name));
            }
        }

        return names;
    }

    // =========================================================================
    // Temperature System
    // =========================================================================

    /// Get block temperature
    pub fn temperature(self: *Self, name: []const u8) !f32 {
        const block = try self.get(name);
        defer {
            var b = block;
            b.deinit();
        }
        return block.temperature;
    }

    /// Set block temperature
    pub fn setTemperature(self: *Self, name: []const u8, temp: f32) !void {
        if (temp < 0.0 or temp > 1.0) return MemError.InvalidTemperature;

        var block = try self.get(name);
        defer block.deinit();

        const updated = Block{
            .name = name,
            .content = block.content,
            .temperature = temp,
            .source = block.source,
            .file_path = block.file_path,
            .last_sync = block.last_sync,
            .tokens = block.tokens,
            .allocator = self.allocator,
        };

        try self.saveBlock(&updated);
    }

    // =========================================================================
    // File Sync (AI.md)
    // =========================================================================

    /// Load file content into a block
    pub fn loadFile(self: *Self, name: []const u8, path: []const u8) !void {
        const content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch {
            // Also try absolute path
            const abs_content = std.fs.openFileAbsolute(path, .{}) catch return MemError.FileNotFound;
            defer abs_content.close();
            return self.loadFileFromHandle(name, path, abs_content);
        };
        defer self.allocator.free(content);

        const block = Block{
            .name = name,
            .content = content,
            .temperature = 0.7, // Default for file-synced blocks
            .source = .file,
            .file_path = path,
            .last_sync = std.time.timestamp(),
            .tokens = estimateTokens(content),
            .allocator = self.allocator,
        };

        try self.saveBlock(&block);
    }

    fn loadFileFromHandle(self: *Self, name: []const u8, path: []const u8, file: std.fs.File) !void {
        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return MemError.FileReadError;
        defer self.allocator.free(content);

        const block = Block{
            .name = name,
            .content = content,
            .temperature = 0.7,
            .source = .file,
            .file_path = path,
            .last_sync = std.time.timestamp(),
            .tokens = estimateTokens(content),
            .allocator = self.allocator,
        };

        try self.saveBlock(&block);
    }

    /// Refresh a file-synced block from disk
    pub fn refresh(self: *Self, name: []const u8) !void {
        var block = try self.get(name);
        defer block.deinit();

        if (block.file_path) |path| {
            try self.loadFile(name, path);
        }
        // For non-file blocks, refresh is a no-op (could trigger auto-generation)
    }

    // =========================================================================
    // Token Management
    // =========================================================================

    /// Get token count for a block (or total if name is null)
    pub fn tokens(self: *Self, name: ?[]const u8) !u32 {
        if (name) |n| {
            const block = try self.get(n);
            defer {
                var b = block;
                b.deinit();
            }
            return block.tokens;
        }

        // Total tokens across all blocks
        var total: u32 = 0;
        var names = try self.list();
        defer {
            for (names.items) |n| self.allocator.free(n);
            names.deinit(self.allocator);
        }

        for (names.items) |n| {
            if (self.get(n)) |block| {
                total += block.tokens;
                var b = block;
                b.deinit();
            } else |_| {}
        }

        return total;
    }

    /// Get token budget
    pub fn getBudget(self: *Self) u32 {
        return self.budget;
    }

    /// Set token budget
    pub fn setBudget(self: *Self, new_budget: u32) !void {
        self.budget = new_budget;
        try self.saveMeta();
    }

    /// Get effective tokens for context (applying temperature)
    pub fn effectiveTokens(self: *Self, name: []const u8) !u32 {
        const block = try self.get(name);
        defer {
            var b = block;
            b.deinit();
        }
        return @intFromFloat(@as(f32, @floatFromInt(block.tokens)) * block.temperature);
    }

    /// Build context string with temperature-weighted content
    /// Returns blocks sorted by temperature (high first), respecting budget
    pub fn buildContext(self: *Self) ![]const u8 {
        var blocks: std.ArrayList(Block) = .empty;
        defer {
            for (blocks.items) |*b| b.deinit();
            blocks.deinit(self.allocator);
        }

        // Collect all blocks
        var names = try self.list();
        defer {
            for (names.items) |n| self.allocator.free(n);
            names.deinit(self.allocator);
        }

        for (names.items) |n| {
            if (self.get(n)) |block| {
                try blocks.append(self.allocator, block);
            } else |_| {}
        }

        // Sort by temperature (highest first)
        std.mem.sort(Block, blocks.items, {}, struct {
            fn lessThan(_: void, a: Block, b: Block) bool {
                return a.temperature > b.temperature; // Descending
            }
        }.lessThan);

        // Build context respecting budget
        var context: std.ArrayList(u8) = .empty;
        errdefer context.deinit(self.allocator);

        var used_tokens: u32 = 0;

        for (blocks.items) |block| {
            const effective = @as(u32, @intFromFloat(@as(f32, @floatFromInt(block.tokens)) * block.temperature));

            if (used_tokens + effective > self.budget) {
                // Over budget - skip low-priority blocks entirely
                if (block.temperature < 0.5) continue;
                // High-priority block over budget: include it but stop after
                // (ensures at least one high-temp block even if over budget)
            }

            try context.appendSlice(self.allocator, "[");
            try context.appendSlice(self.allocator, block.name);
            try context.appendSlice(self.allocator, "]\n");
            try context.appendSlice(self.allocator, block.content);
            try context.appendSlice(self.allocator, "\n\n");

            used_tokens += effective;

            // If we went over budget with a high-priority block, stop adding more
            if (used_tokens > self.budget) break;
        }

        return context.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    fn blockKey(self: *Self, name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ BLOCK_PREFIX, name });
    }

    fn saveBlock(self: *Self, block: *const Block) !void {
        const key = try self.blockKey(block.name);
        defer self.allocator.free(key);

        const json = try serializeBlock(self.allocator, block);
        defer self.allocator.free(json);

        self.db.put(key, json) catch return MemError.StorageError;
    }

    fn saveMeta(self: *Self) !void {
        const json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"budget\":{d},\"version\":1}}",
            .{self.budget},
        );
        defer self.allocator.free(json);
        self.db.put(META_KEY, json) catch return MemError.StorageError;
    }
};

// =============================================================================
// Token Estimation
// =============================================================================

/// Estimate tokens for text (heuristic: ~4 chars per token for English)
pub fn estimateTokens(text: []const u8) u32 {
    // Use provider's estimation if available
    return provider.estimateTokens(text);
}

// =============================================================================
// JSON Serialization
// =============================================================================

fn serializeBlock(allocator: Allocator, block: *const Block) ![]const u8 {
    var json: std.ArrayList(u8) = .empty;
    errdefer json.deinit(allocator);

    const writer = json.writer(allocator);
    try writer.writeAll("{");

    // Content (escaped using std.json.fmt)
    try writer.print("\"content\":{any}", .{std.json.fmt(block.content, .{})});

    // Temperature
    try writer.print(",\"temperature\":{d:.2}", .{block.temperature});

    // Source
    try writer.print(",\"source\":\"{s}\"", .{block.source.toString()});

    // Tokens
    try writer.print(",\"tokens\":{d}", .{block.tokens});

    // File path (optional)
    if (block.file_path) |fp| {
        try writer.print(",\"file_path\":{any}", .{std.json.fmt(fp, .{})});
    }

    // Last sync (optional)
    if (block.last_sync) |ls| {
        try writer.print(",\"last_sync\":{d}", .{ls});
    }

    try writer.writeAll("}");
    return json.toOwnedSlice(allocator);
}

fn parseBlockJson(allocator: Allocator, name: []const u8, json_bytes: []const u8) !Block {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch
        return MemError.SerializationFailed;
    defer parsed.deinit();

    const root = parsed.value.object;

    const content = if (root.get("content")) |c| try allocator.dupe(u8, c.string) else try allocator.dupe(u8, "");
    errdefer allocator.free(content);

    const temp: f32 = if (root.get("temperature")) |t| @floatCast(t.float) else 0.5;

    const source: BlockSource = if (root.get("source")) |s|
        BlockSource.fromString(s.string) orelse .manual
    else
        .manual;

    const file_path: ?[]const u8 = if (root.get("file_path")) |fp|
        try allocator.dupe(u8, fp.string)
    else
        null;

    const last_sync: ?i64 = if (root.get("last_sync")) |ls| ls.integer else null;

    const tokens_val: u32 = if (root.get("tokens")) |t| @intCast(t.integer) else estimateTokens(content);

    return Block{
        .name = try allocator.dupe(u8, name),
        .content = content,
        .temperature = temp,
        .source = source,
        .file_path = file_path,
        .last_sync = last_sync,
        .tokens = tokens_val,
        .allocator = allocator,
    };
}

const MetaInfo = struct {
    budget: u32,
};

fn parseMetaJson(allocator: Allocator, json_bytes: []const u8) !MetaInfo {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch
        return MemError.SerializationFailed;
    defer parsed.deinit();

    const root = parsed.value.object;
    const budget: u32 = if (root.get("budget")) |b| @intCast(b.integer) else Memory.DEFAULT_BUDGET;

    return MetaInfo{ .budget = budget };
}

// =============================================================================
// Tests
// =============================================================================

test "memory block basic operations" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var mem = try Memory.init(allocator, path);
    defer mem.deinit();

    // Set a block
    try mem.set("persona", "You are a helpful assistant.");

    // Get the block
    var block = try mem.get("persona");
    defer block.deinit();

    try std.testing.expectEqualStrings("You are a helpful assistant.", block.content);
    try std.testing.expect(block.temperature == 0.5);
    try std.testing.expect(block.source == .manual);
}

test "memory block append" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var mem = try Memory.init(allocator, path);
    defer mem.deinit();

    // Set initial
    try mem.set("user", "Prefers TypeScript");

    // Append
    try mem.append("user", "Uses async/await");

    // Verify
    var block = try mem.get("user");
    defer block.deinit();

    try std.testing.expect(std.mem.indexOf(u8, block.content, "TypeScript") != null);
    try std.testing.expect(std.mem.indexOf(u8, block.content, "async/await") != null);
}

test "memory temperature" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var mem = try Memory.init(allocator, path);
    defer mem.deinit();

    try mem.set("context", "Current file content...");
    try mem.setTemperature("context", 1.0);

    const temp = try mem.temperature("context");
    try std.testing.expect(temp == 1.0);
}

test "memory list blocks" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var mem = try Memory.init(allocator, path);
    defer mem.deinit();

    try mem.set("persona", "Helper");
    try mem.set("user", "Preferences");
    try mem.set("project", "Vimcraft");

    var names = try mem.list();
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), names.items.len);
}

test "token estimation" {
    // "Hello, world!" = 13 chars ≈ 3-4 tokens
    const tokens = estimateTokens("Hello, world!");
    try std.testing.expect(tokens >= 2 and tokens <= 5);
}
