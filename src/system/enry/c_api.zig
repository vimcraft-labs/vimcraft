/// C API bindings for go-enry (GitHub Linguist language detection)
/// Interfaces with libenry.dylib C shared library
const std = @import("std");

/// Errors that can occur when interfacing with go-enry
pub const EnryError = error{
    /// Integer overflow when converting between Zig and Go sizes
    IntegerOverflow,
    /// Invalid input (null pointer with non-zero length)
    InvalidInput,
    /// Allocation failure when copying Go string to Zig
    OutOfMemory,
};

/// Go string type (pointer + length)
pub const GoString = extern struct {
    p: [*c]const u8, // Pointer to string data
    n: isize, // Length of string (Go uses ptrdiff_t which maps to isize)
};

/// Go slice type (pointer + length + capacity)
pub const GoSlice = extern struct {
    data: ?*anyopaque, // Pointer to slice data
    len: i64, // Length (Go uses GoInt which is i64 on 64-bit)
    cap: i64, // Capacity
};

/// Return type for functions that return (language, safe bool)
pub const LanguageResult = extern struct {
    r0: GoString, // language name
    r1: u8, // safe (bool: 1 = unique match, 0 = ambiguous)
};

/// Detect programming language from filename and content
/// Uses all strategies: extension, filename, shebang, modeline, heuristics, classifier
pub extern "c" fn GetLanguage(filename: GoString, content: GoSlice) GoString;

/// Detect language by content inspection (regexp heuristics)
pub extern "c" fn GetLanguageByContent(filename: GoString, content: GoSlice) LanguageResult;

/// Detect language by file extension
pub extern "c" fn GetLanguageByExtension(filename: GoString) LanguageResult;

/// Detect language by exact filename match (e.g., "Makefile", ".gitignore")
pub extern "c" fn GetLanguageByFilename(filename: GoString) LanguageResult;

/// Detect language by shebang line (e.g., "#!/usr/bin/env python")
pub extern "c" fn GetLanguageByShebang(content: GoSlice) LanguageResult;

/// Detect language by modeline (Vim/Emacs)
pub extern "c" fn GetLanguageByModeline(content: GoSlice) LanguageResult;

/// Helper: Create GoString from Zig slice
/// Returns error if string length exceeds isize bounds
pub fn makeGoString(s: []const u8) EnryError!GoString {
    // Validate length fits in isize (Go's string length type)
    if (s.len > std.math.maxInt(isize)) {
        return EnryError.IntegerOverflow;
    }

    return GoString{
        .p = s.ptr,
        .n = @intCast(s.len),
    };
}

/// Helper: Create GoSlice from Zig slice
/// Returns error if slice length exceeds i64 bounds
pub fn makeGoSlice(s: []const u8) EnryError!GoSlice {
    // Validate length fits in i64 (Go's slice length type)
    if (s.len > std.math.maxInt(i64)) {
        return EnryError.IntegerOverflow;
    }

    return GoSlice{
        .data = if (s.len > 0) @constCast(@ptrCast(s.ptr)) else null,
        .len = @intCast(s.len),
        .cap = @intCast(s.len),
    };
}

/// Helper: Extract Zig string from GoString (allocates copy)
/// Returns:
/// - String if Go returned non-empty string (caller must free)
/// - null if Go returned empty string (no language detected)
/// - error.OutOfMemory if allocation fails
/// - error.IntegerOverflow if length exceeds usize bounds
/// - error.InvalidInput if pointer is null but length is non-zero
pub fn goStringToZig(allocator: std.mem.Allocator, gs: GoString) EnryError!?[]const u8 {
    // Empty string means "no language detected" (valid result)
    if (gs.n <= 0) return null;

    // Validate pointer is not null
    if (gs.p == null) {
        return EnryError.InvalidInput;
    }

    // Validate length fits in usize
    if (gs.n < 0 or gs.n > std.math.maxInt(usize)) {
        return EnryError.IntegerOverflow;
    }

    const len: usize = @intCast(gs.n);

    // Allocate and copy (propagate allocation errors)
    const str = allocator.alloc(u8, len) catch return EnryError.OutOfMemory;
    @memcpy(str, gs.p[0..len]);

    return str;
}

/// Helper: Extract Zig string slice from GoString (zero-copy, but UNSAFE)
///
/// SAFETY: This does NOT allocate - returned slice points directly to Go-managed memory.
/// The slice is only valid until:
/// 1. Next call to any go-enry function (may trigger GC)
/// 2. Go runtime decides to collect the string
///
/// Use goStringToZig() for safe allocated copy.
///
/// Returns:
/// - Slice pointing to Go memory (no ownership transfer)
/// - null if Go returned empty string
/// - error.IntegerOverflow if length exceeds usize bounds
/// - error.InvalidInput if pointer is null but length is non-zero
pub fn goStringToSlice(gs: GoString) EnryError!?[]const u8 {
    if (gs.n <= 0) return null;

    // Validate pointer is not null
    if (gs.p == null) {
        return EnryError.InvalidInput;
    }

    // Validate length fits in usize
    if (gs.n < 0 or gs.n > std.math.maxInt(usize)) {
        return EnryError.IntegerOverflow;
    }

    const len: usize = @intCast(gs.n);
    return gs.p[0..len];
}
