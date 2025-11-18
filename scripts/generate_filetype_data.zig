const std = @import("std");

/// Extract filetype detection data from Neovim's filetype.lua and generate Zig code.
/// Parses extension and filename mappings for compile-time initialization.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Note: We write diagnostics to stderr and generated code to stdout
    // The stderr output will be visible in build logs
    // The stdout will be captured by build.zig and written to filetype_data.zig

    // Read Neovim's filetype.lua
    const file_path = "vendor/neovim/runtime/lua/vim/filetype.lua";
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("❌ Error: Cannot open {s}: {}\n", .{ file_path, err });
        std.debug.print("   Make sure vendor/neovim submodule is initialized\n", .{});
        return err;
    };
    defer file.close();

    std.debug.print("📖 Reading Neovim filetype data from: {s}\n", .{file_path});

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    // Parse extension mappings
    var extension_map = std.StringHashMap([]const u8).init(allocator);
    defer extension_map.deinit();

    try parseExtensions(content, &extension_map, allocator);
    std.debug.print("✓ Extracted {} extension mappings\n", .{extension_map.count()});

    // Parse filename mappings
    var filename_map = std.StringHashMap([]const u8).init(allocator);
    defer filename_map.deinit();

    try parseFilenames(content, &filename_map, allocator);
    std.debug.print("✓ Extracted {} filename mappings\n", .{filename_map.count()});

    std.debug.print("⚙️  Generating Zig code...\n", .{});

    // Generate Zig code to stdout (captured by build.zig)
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    try generateZigCode(&extension_map, &filename_map, &stdout_writer.interface, allocator);
    try stdout_writer.end();

    std.debug.print("\n✅ Generated filetype_data.zig\n", .{});
    std.debug.print("   Total mappings: {}\n", .{extension_map.count() + filename_map.count()});
    std.debug.print("   Extensions: {}\n", .{extension_map.count()});
    std.debug.print("   Filenames: {}\n", .{filename_map.count()});
    std.debug.print("🚀 Compile-time data ready! Zero runtime overhead!\n", .{});
}

/// Parse extension mappings from "local extension = { ... }" table
fn parseExtensions(content: []const u8, map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) !void {
    const marker = "local extension = {";
    const start_idx = std.mem.indexOf(u8, content, marker) orelse return;
    const block_start = start_idx + marker.len;

    // Find closing brace
    const block_end = std.mem.indexOfPos(u8, content, block_start, "\n}") orelse return;
    const block = content[block_start..block_end];

    // Parse lines like: rs = 'rust',
    var lines = std.mem.splitScalar(u8, block, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "--")) continue; // Skip comments

        // Look for pattern: word = 'word',
        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
        const key_raw = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
        const value_part = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

        // Skip if not a simple string assignment
        if (!std.mem.startsWith(u8, value_part, "'")) continue;

        // Extract value between single quotes (e.g., 'rust' -> rust)
        const quote_end = std.mem.indexOfPos(u8, value_part, 1, "'") orelse continue;
        const value = value_part[1..quote_end]; // Extract text between quotes

        // Skip function-based assignments (detect.*)
        if (std.mem.indexOf(u8, value_part, "detect.") != null) continue;

        // Create key with leading dot
        const key = try std.fmt.allocPrint(allocator, ".{s}", .{key_raw});
        const value_copy = try allocator.dupe(u8, value);

        try map.put(key, value_copy);
    }
}

/// Parse filename mappings from "local filename = { ... }" table
fn parseFilenames(content: []const u8, map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) !void {
    const marker = "local filename = {";
    const start_idx = std.mem.indexOf(u8, content, marker) orelse return;
    const block_start = start_idx + marker.len;

    // Find closing brace
    const block_end = std.mem.indexOfPos(u8, content, block_start, "\n}") orelse return;
    const block = content[block_start..block_end];

    // Parse lines like: ['Makefile'] = 'make',
    var lines = std.mem.splitScalar(u8, block, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "--")) continue; // Skip comments

        // Look for pattern: ['filename'] = 'filetype',
        if (!std.mem.startsWith(u8, trimmed, "['")) continue;

        const key_end = std.mem.indexOf(u8, trimmed, "']") orelse continue;
        const key = trimmed[2..key_end];

        const eq_pos = std.mem.indexOfPos(u8, trimmed, key_end, "=") orelse continue;
        const value_part = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

        // Extract value between single quotes
        if (!std.mem.startsWith(u8, value_part, "'")) continue;
        const quote_end = std.mem.indexOfPos(u8, value_part, 1, "'") orelse continue;
        const value = value_part[1..quote_end];

        // Skip function-based assignments
        if (std.mem.indexOf(u8, value_part, "detect.") != null) continue;

        const key_copy = try allocator.dupe(u8, key);
        const value_copy = try allocator.dupe(u8, value);

        try map.put(key_copy, value_copy);
    }
}

/// Generate Zig code with compile-time initialized maps
fn generateZigCode(
    extension_map: *std.StringHashMap([]const u8),
    filename_map: *std.StringHashMap([]const u8),
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    // Header
    try writer.writeAll(
        \\//! AUTO-GENERATED from Neovim runtime/lua/vim/filetype.lua
        \\//! DO NOT EDIT MANUALLY - Run `zig build` to regenerate
        \\//!
        \\//! This file contains comprehensive filetype detection data extracted from Neovim.
        \\//! All data is initialized at compile-time for zero runtime overhead.
        \\
        \\const std = @import("std");
        \\
        \\/// Extension to filetype mapping (e.g., ".rs" -> "rust")
        \\/// Compile-time initialized for O(1) lookup with zero runtime cost
        \\pub const extension_map = std.StaticStringMap([]const u8).initComptime(.{
        \\
    );

    // Sort extensions for deterministic output
    // Allocate array for sorting
    const Entry = struct { []const u8, []const u8 };
    const extensions = try allocator.alloc(Entry, extension_map.count());
    defer allocator.free(extensions);

    var ext_it = extension_map.iterator();
    var i: usize = 0;
    while (ext_it.next()) |entry| : (i += 1) {
        extensions[i] = .{ entry.key_ptr.*, entry.value_ptr.* };
    }

    std.mem.sort(Entry, extensions, {}, struct {
        fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, lhs[0], rhs[0]);
        }
    }.lessThan);

    // Write extension mappings
    for (extensions) |entry| {
        try writer.print("    .{{ \"{s}\", \"{s}\" }},\n", .{ entry[0], entry[1] });
    }

    try writer.writeAll(
        \\});
        \\
        \\/// Exact filename to filetype mapping (e.g., "Makefile" -> "make")
        \\/// Compile-time initialized for O(1) lookup with zero runtime cost
        \\pub const filename_map = std.StaticStringMap([]const u8).initComptime(.{
        \\
    );

    // Sort filenames for deterministic output
    const filenames = try allocator.alloc(Entry, filename_map.count());
    defer allocator.free(filenames);

    var file_it = filename_map.iterator();
    var j: usize = 0;
    while (file_it.next()) |entry| : (j += 1) {
        filenames[j] = .{ entry.key_ptr.*, entry.value_ptr.* };
    }

    std.mem.sort(Entry, filenames, {}, struct {
        fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
            return std.mem.lessThan(u8, lhs[0], rhs[0]);
        }
    }.lessThan);

    // Write filename mappings
    for (filenames) |entry| {
        try writer.print("    .{{ \"{s}\", \"{s}\" }},\n", .{ entry[0], entry[1] });
    }

    try writer.writeAll(
        \\});
        \\
        \\/// Statistics for debugging
        \\pub const stats = struct {
        \\
    );

    try writer.print("    pub const extension_count = {};\n", .{extension_map.count()});
    try writer.print("    pub const filename_count = {};\n", .{filename_map.count()});
    try writer.writeAll(
        \\    pub const total_mappings = extension_count + filename_count;
        \\};
        \\
    );
}
