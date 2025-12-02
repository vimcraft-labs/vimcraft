/// Tree-sitter Query Predicates and Directives
///
/// Processes query predicates like `#eq?`, `#anyOf?`, `#match?` and
/// directives like `#set! injection.language "lua"` for language injections.
///
/// Architecture:
/// - Predicate: Conditional test (returns bool) - e.g., #eq? @capture "value"
/// - Directive: Metadata setter (modifies state) - e.g., #set! injection.language "lua"
/// - Metadata: HashMap storing directive values per match
///
/// Supported Predicates:
/// - #eq? @capture "string"       - Exact string match
/// - #anyOf? @capture "a" "b" "c" - Match any of listed strings
/// - #match? @capture "regex"     - Regex match (Vim-style, simplified)
/// - #contains? @capture "substr" - Substring check
///
/// Supported Directives:
/// - #set! injection.language "lang"    - Set static injection language
/// - #set! injection.combined           - Merge multiple ranges into one parse
/// - #set! injection.includeChildren    - Include child nodes in injection
/// - #set! injection.self               - Use parent's language (recursive)
/// - #offset! @capture start end        - Adjust capture range (for trimming quotes, etc.)
///
/// Usage:
///   const metadata = Metadata.init(allocator);
///   defer metadata.deinit();
///
///   processMatchPredicates(query, match, source, &metadata);
///
///   if (metadata.get("injection.language")) |lang| {
///       // Use lang for injection
///   }

const std = @import("std");
const c_api = @import("c_api.zig");
const c = c_api.c;
const Query = @import("query.zig").Query;

/// Metadata collected from directives
/// Stores key-value pairs from #set! directives
pub const Metadata = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Metadata {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Metadata) void {
        // Free owned values
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn get(self: *const Metadata, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn put(self: *Metadata, key: []const u8, value: []const u8) !void {
        // Remove old value if exists
        if (self.map.get(key)) |old| {
            self.allocator.free(old);
        }
        // Store copy of value
        const value_copy = try self.allocator.dupe(u8, value);
        try self.map.put(key, value_copy);
    }

    pub fn contains(self: *const Metadata, key: []const u8) bool {
        return self.map.contains(key);
    }

    pub fn clear(self: *Metadata) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.clearRetainingCapacity();
    }
};

/// Offset adjustment from #offset! directive
pub const OffsetAdjustment = struct {
    startRow: i32 = 0,
    startCol: i32 = 0,
    endRow: i32 = 0,
    endCol: i32 = 0,
};

/// Process all predicates for a query match
/// Evaluates predicates and populates metadata from directives
///
/// Parameters:
/// - query: Compiled query (for capture names and predicate data)
/// - match: Current query match
/// - source: Full source text (for capture text extraction)
/// - metadata: Output metadata map (populated by directives)
///
/// Returns:
/// - true if all predicates pass (match should be used)
/// - false if any predicate fails (match should be skipped)
pub fn processMatchPredicates(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    metadata: *Metadata,
) bool {
    const pattern_idx = match.pattern_index;

    // Get predicates for this pattern
    var predicate_count: u32 = 0;
    const predicates_ptr = c.ts_query_predicates_for_pattern(
        query.query,
        pattern_idx,
        &predicate_count,
    );

    if (predicate_count == 0 or predicates_ptr == null) {
        return true; // No predicates = match passes
    }

    const predicates = predicates_ptr[0..predicate_count];

    // Process predicates in groups (separated by Done steps)
    var i: usize = 0;
    while (i < predicates.len) {
        const result = processPredicateGroup(query, match, source, predicates, &i, metadata);
        if (!result) {
            return false; // Predicate failed
        }
    }

    return true;
}

/// Process a single predicate group (until Done step)
fn processPredicateGroup(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    predicates: []const c.TSQueryPredicateStep,
    index: *usize,
    metadata: *Metadata,
) bool {
    const start_idx = index.*;

    // Find end of this predicate (Done step or end of array)
    var end_idx = start_idx;
    while (end_idx < predicates.len and predicates[end_idx].type != c.TSQueryPredicateStepTypeDone) {
        end_idx += 1;
    }

    // Skip Done step for next iteration
    if (end_idx < predicates.len) {
        index.* = end_idx + 1;
    } else {
        index.* = end_idx;
    }

    if (start_idx >= end_idx) {
        return true; // Empty predicate
    }

    // Get predicate name (first step should be a string)
    const first_step = predicates[start_idx];
    if (first_step.type != c.TSQueryPredicateStepTypeString) {
        return true; // Invalid predicate format
    }

    const name = getStepString(query, first_step);

    // Route to appropriate handler
    if (std.mem.eql(u8, name, "eq?")) {
        return handleEqPredicate(query, match, source, predicates[start_idx..end_idx]);
    } else if (std.mem.eql(u8, name, "any-of?") or std.mem.eql(u8, name, "anyOf?")) {
        return handleAnyOfPredicate(query, match, source, predicates[start_idx..end_idx]);
    } else if (std.mem.eql(u8, name, "match?")) {
        return handleMatchPredicate(query, match, source, predicates[start_idx..end_idx]);
    } else if (std.mem.eql(u8, name, "contains?")) {
        return handleContainsPredicate(query, match, source, predicates[start_idx..end_idx]);
    } else if (std.mem.eql(u8, name, "set!")) {
        handleSetDirective(query, predicates[start_idx..end_idx], metadata);
        return true;
    } else if (std.mem.eql(u8, name, "offset!")) {
        // offset! is handled separately when extracting ranges
        return true;
    } else if (std.mem.eql(u8, name, "lua-match?")) {
        // lua-match? uses Lua patterns, we approximate with contains
        return handleContainsPredicate(query, match, source, predicates[start_idx..end_idx]);
    }

    // Unknown predicate - pass by default
    return true;
}

/// Get string value from predicate step
fn getStepString(query: *const Query, step: c.TSQueryPredicateStep) []const u8 {
    if (step.type != c.TSQueryPredicateStepTypeString) {
        return "";
    }
    var length: u32 = 0;
    const str_ptr = c.ts_query_string_value_for_id(query.query, step.value_id, &length);
    if (str_ptr == null or length == 0) {
        return "";
    }
    return str_ptr[0..length];
}

/// Get capture text from source
fn getCaptureText(match: *const c.TSQueryMatch, capture_idx: u32, source: []const u8) ?[]const u8 {
    if (capture_idx >= match.capture_count) {
        return null;
    }
    const capture = match.captures[capture_idx];
    const start = c.ts_node_start_byte(capture.node);
    const end = c.ts_node_end_byte(capture.node);

    if (start >= source.len or end > source.len or start >= end) {
        return null;
    }
    return source[start..end];
}

/// Find capture index by name in match
fn findCaptureByName(query: *const Query, match: *const c.TSQueryMatch, name: []const u8) ?u32 {
    for (0..match.capture_count) |i| {
        const idx: u32 = @intCast(i);
        const capture_name = query.getCaptureName(match.captures[i].index);
        if (std.mem.eql(u8, capture_name, name)) {
            return idx;
        }
    }
    return null;
}

// ============================================================================
// Predicate Handlers
// ============================================================================

/// Handle #eq? @capture "value"
/// Returns true if capture text exactly equals value
fn handleEqPredicate(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    steps: []const c.TSQueryPredicateStep,
) bool {
    // Format: "eq?" @capture "value" OR "eq?" @capture1 @capture2
    if (steps.len < 3) return true;

    const second_step = steps[1];
    const third_step = steps[2];

    if (second_step.type == c.TSQueryPredicateStepTypeCapture) {
        const capture_text = getCaptureText(match, second_step.value_id, source) orelse return true;

        if (third_step.type == c.TSQueryPredicateStepTypeString) {
            // Compare capture to string
            const expected = getStepString(query, third_step);
            return std.mem.eql(u8, capture_text, expected);
        } else if (third_step.type == c.TSQueryPredicateStepTypeCapture) {
            // Compare two captures
            const other_text = getCaptureText(match, third_step.value_id, source) orelse return true;
            return std.mem.eql(u8, capture_text, other_text);
        }
    }

    return true;
}

/// Handle #any-of? @capture "a" "b" "c"
/// Returns true if capture text matches any of the listed values
fn handleAnyOfPredicate(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    steps: []const c.TSQueryPredicateStep,
) bool {
    // Format: "any-of?" @capture "val1" "val2" ...
    if (steps.len < 3) return true;

    const capture_step = steps[1];
    if (capture_step.type != c.TSQueryPredicateStepTypeCapture) return true;

    const capture_text = getCaptureText(match, capture_step.value_id, source) orelse return true;

    // Check each value
    for (steps[2..]) |step| {
        if (step.type == c.TSQueryPredicateStepTypeString) {
            const value = getStepString(query, step);
            if (std.mem.eql(u8, capture_text, value)) {
                return true;
            }
        }
    }

    return false;
}

/// Handle #match? @capture "regex"
/// Returns true if capture text matches regex pattern
fn handleMatchPredicate(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    steps: []const c.TSQueryPredicateStep,
) bool {
    // Format: "match?" @capture "pattern"
    if (steps.len < 3) return true;

    const capture_step = steps[1];
    const pattern_step = steps[2];

    if (capture_step.type != c.TSQueryPredicateStepTypeCapture) return true;
    if (pattern_step.type != c.TSQueryPredicateStepTypeString) return true;

    const capture_text = getCaptureText(match, capture_step.value_id, source) orelse return true;
    const pattern = getStepString(query, pattern_step);

    // Simplified regex matching: check if pattern is contained
    // Full regex support would require a regex library
    // For now, handle common cases:
    // - "^..." -> starts with
    // - "...$" -> ends with
    // - Literal text -> contains
    if (pattern.len == 0) return true;

    if (pattern[0] == '^' and pattern.len > 1) {
        // Starts with
        const suffix = pattern[1..];
        if (suffix.len > 0 and suffix[suffix.len - 1] == '$') {
            // Exact match: ^...$
            return std.mem.eql(u8, capture_text, suffix[0 .. suffix.len - 1]);
        }
        return std.mem.startsWith(u8, capture_text, suffix);
    } else if (pattern[pattern.len - 1] == '$') {
        // Ends with
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.endsWith(u8, capture_text, prefix);
    }

    // Default: contains
    return std.mem.indexOf(u8, capture_text, pattern) != null;
}

/// Handle #contains? @capture "substring"
/// Returns true if capture text contains substring
fn handleContainsPredicate(
    query: *const Query,
    match: *const c.TSQueryMatch,
    source: []const u8,
    steps: []const c.TSQueryPredicateStep,
) bool {
    // Format: "contains?" @capture "substring"
    if (steps.len < 3) return true;

    const capture_step = steps[1];
    const substr_step = steps[2];

    if (capture_step.type != c.TSQueryPredicateStepTypeCapture) return true;
    if (substr_step.type != c.TSQueryPredicateStepTypeString) return true;

    const capture_text = getCaptureText(match, capture_step.value_id, source) orelse return true;
    const substring = getStepString(query, substr_step);

    return std.mem.indexOf(u8, capture_text, substring) != null;
}

// ============================================================================
// Directive Handlers
// ============================================================================

/// Handle #set! key value
/// Stores metadata for injection processing
fn handleSetDirective(
    query: *const Query,
    steps: []const c.TSQueryPredicateStep,
    metadata: *Metadata,
) void {
    // Format: "set!" "key" "value" OR "set!" "key" (flag with no value)
    if (steps.len < 2) return;

    const key_step = steps[1];
    if (key_step.type != c.TSQueryPredicateStepTypeString) return;

    const key = getStepString(query, key_step);
    if (key.len == 0) return;

    if (steps.len >= 3 and steps[2].type == c.TSQueryPredicateStepTypeString) {
        // Key with value
        const value = getStepString(query, steps[2]);
        metadata.put(key, value) catch return;
    } else {
        // Flag (key with no value) - store empty string
        metadata.put(key, "") catch return;
    }
}

/// Get offset adjustment from predicates for a pattern
/// Returns adjustment values from #offset! directive
pub fn getOffsetAdjustment(
    query: *const Query,
    pattern_idx: u32,
    capture_name: []const u8,
) OffsetAdjustment {
    var adjustment = OffsetAdjustment{};

    var predicate_count: u32 = 0;
    const predicates_ptr = c.ts_query_predicates_for_pattern(
        query.query,
        pattern_idx,
        &predicate_count,
    );

    if (predicate_count == 0 or predicates_ptr == null) {
        return adjustment;
    }

    const predicates = predicates_ptr[0..predicate_count];

    // Find #offset! directive
    var i: usize = 0;
    while (i < predicates.len) {
        if (predicates[i].type == c.TSQueryPredicateStepTypeString) {
            const name = getStepString(query, predicates[i]);
            if (std.mem.eql(u8, name, "offset!")) {
                // Format: "offset!" @capture start_row start_col end_row end_col
                if (i + 5 < predicates.len) {
                    const capture_step = predicates[i + 1];
                    if (capture_step.type == c.TSQueryPredicateStepTypeCapture) {
                        const cap_name = query.getCaptureName(capture_step.value_id);
                        if (std.mem.eql(u8, cap_name, capture_name)) {
                            // Parse offset values
                            adjustment.startRow = parseIntStep(query, predicates[i + 2]);
                            adjustment.startCol = parseIntStep(query, predicates[i + 3]);
                            adjustment.endRow = parseIntStep(query, predicates[i + 4]);
                            adjustment.endCol = parseIntStep(query, predicates[i + 5]);
                            return adjustment;
                        }
                    }
                }
            }
        }
        i += 1;
    }

    return adjustment;
}

fn parseIntStep(query: *const Query, step: c.TSQueryPredicateStep) i32 {
    if (step.type != c.TSQueryPredicateStepTypeString) return 0;
    const str = getStepString(query, step);
    return std.fmt.parseInt(i32, str, 10) catch 0;
}

/// Get conceal value from predicates for a pattern
/// Returns the conceal replacement string (empty = hide, null = no conceal)
/// Extracts value from #set! conceal "..." directive
pub fn getConcealForPattern(
    query: *const Query,
    pattern_idx: u32,
) ?[]const u8 {
    var predicate_count: u32 = 0;
    const predicates_ptr = c.ts_query_predicates_for_pattern(
        query.query,
        pattern_idx,
        &predicate_count,
    );

    if (predicate_count == 0 or predicates_ptr == null) {
        return null;
    }

    const predicates = predicates_ptr[0..predicate_count];

    // Find #set! conceal directive
    var i: usize = 0;
    while (i < predicates.len) {
        if (predicates[i].type == c.TSQueryPredicateStepTypeString) {
            const name = getStepString(query, predicates[i]);
            if (std.mem.eql(u8, name, "set!")) {
                // Format: "set!" "conceal" "value" OR "set!" "conceal" (empty = hide)
                if (i + 1 < predicates.len) {
                    const key_step = predicates[i + 1];
                    if (key_step.type == c.TSQueryPredicateStepTypeString) {
                        const key = getStepString(query, key_step);
                        if (std.mem.eql(u8, key, "conceal")) {
                            // Check if there's a value
                            if (i + 2 < predicates.len and predicates[i + 2].type == c.TSQueryPredicateStepTypeString) {
                                return getStepString(query, predicates[i + 2]);
                            }
                            // No value = empty string (hide completely)
                            return "";
                        }
                    }
                }
            }
        }
        i += 1;
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "Metadata: basic operations" {
    const allocator = std.testing.allocator;

    var metadata = Metadata.init(allocator);
    defer metadata.deinit();

    // Initially empty
    try std.testing.expect(metadata.get("key") == null);
    try std.testing.expect(!metadata.contains("key"));

    // Put value
    try metadata.put("injection.language", "javascript");
    try std.testing.expect(metadata.contains("injection.language"));
    try std.testing.expectEqualStrings("javascript", metadata.get("injection.language").?);

    // Update value
    try metadata.put("injection.language", "lua");
    try std.testing.expectEqualStrings("lua", metadata.get("injection.language").?);

    // Clear
    metadata.clear();
    try std.testing.expect(!metadata.contains("injection.language"));
}

test "Metadata: multiple keys" {
    const allocator = std.testing.allocator;

    var metadata = Metadata.init(allocator);
    defer metadata.deinit();

    try metadata.put("injection.language", "python");
    try metadata.put("injection.combined", "");
    try metadata.put("injection.includeChildren", "");

    try std.testing.expectEqualStrings("python", metadata.get("injection.language").?);
    try std.testing.expect(metadata.contains("injection.combined"));
    try std.testing.expect(metadata.contains("injection.includeChildren"));
}
