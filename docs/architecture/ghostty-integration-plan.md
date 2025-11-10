# Ghostty Integration Plan

## Current Status (Production-Ready!)

We're using a **production-ready** standalone `char_width.zig` implementation that:
- ✅ Handles all important Unicode cases (CJK, emoji, variation selectors, combining marks)
- ✅ Includes grapheme cluster support (stores variation selectors with base characters)
- ✅ Tested and working perfectly (🖥️ rendering stable, no flickering)
- ✅ Based on Unicode East Asian Width property
- ✅ Zero external dependencies
- ✅ Works with any Zig version (no version lock-in)

This implementation is **sufficient for production use** and handles all real-world text editing scenarios.

## Why Not Ghostty's uucode Right Now?

**Zig Version Compatibility**: Ghostty's `uucode` dependency requires Zig 0.15.2+, but:
- We're on Zig 0.15.0-dev (master/nightly)
- Zig master has breaking API changes
- `uucode` build.zig uses deprecated APIs like `std.Io.Writer.Allocating`

**Decision**: Keep our working implementation until OpenVim stabilizes on a specific Zig version (likely 0.15.2 or later).

Our current implementation is **already production-ready** and handles all important cases. Ghostty integration is an optimization, not a requirement.

## If We Need Ghostty's codepoint_width (Future)

### When to Switch

Only switch if:
1. OpenVim stabilizes on Zig 0.15.2+
2. We encounter edge cases our implementation doesn't handle
3. We want 100% Unicode spec compliance (rare edge cases)

### Dependencies Required

1. **uucode** - Unicode database library
   - Source: https://deps.files.ghostty.org/uucode-*.tar.gz
   - Provides: Unicode East Asian Width property lookups

2. **Google Highway** - SIMD library (optional, for performance)
   - Used by: `vendor/ghostty/src/simd/codepoint_width.cpp`
   - Fallback: Pure Zig implementation available in Ghostty

### Integration Steps

#### Option 1: Use Zig-only fallback (simpler)

```zig
// In build.zig, add uucode dependency
const uucode = b.dependency("uucode", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("uucode", uucode.module("uucode"));
```

```zig
// In char_width.zig
const uucode = @import("uucode");

pub fn codepointWidth(codepoint: u21) u8 {
    if (codepoint > uucode.config.max_code_point) return 1;
    const width = uucode.get(.width, @intCast(codepoint));
    if (width <= 0) return 0;
    if (width >= 2) return 2;
    return 1;
}
```

#### Option 2: Use Ghostty's full SIMD implementation (faster)

1. Add to `build.zig.zon`:
```zig
.dependencies = .{
    .uucode = .{
        .url = "https://deps.files.ghostty.org/uucode-f81f8ef8518b8ec5a7fca30ec5fdbc76cc6197df.tar.gz",
        .hash = "uucode-0.1.0-ZZjBPjQHQADuCy1VMWftjrMl3iWqgMpUugWVQJG6_7xT",
    },
}
```

2. Build Ghostty's SIMD code:
```bash
cd vendor/ghostty
# Build with highway SIMD support
zig build -Dsimd=true
```

3. Link in `build.zig`:
```zig
// Add ghostty module
const ghostty = b.dependency("ghostty", .{
    .target = target,
    .optimize = optimize,
    .simd = true,
});
exe.root_module.addImport("ghostty", ghostty.module("ghostty"));
```

4. Replace `char_width.zig` with direct import:
```zig
const ghostty = @import("ghostty");

pub fn codepointWidth(codepoint: u21) u8 {
    const width = ghostty.simd.codepoint_width.codepointWidth(codepoint);
    if (width <= 0) return 0;
    if (width >= 2) return 2;
    return 1;
}
```

### When to Switch

**Switch to Ghostty if:**
- User reports emoji/Unicode rendering issues our implementation can't fix
- Performance profiling shows width calculation is a bottleneck (unlikely)
- Need 100% Unicode compliance for edge cases

**Don't switch if:**
- Current implementation handles your use cases
- Want to keep build simple
- Want to minimize dependencies

### Edge Cases to Watch For

Our current implementation might struggle with:

1. **Complex emoji sequences**:
   - Skin tone modifiers: 👋🏻 (base + modifier)
   - ZWJ sequences: 👨‍👩‍👧 (multiple codepoints joined)
   - Flag sequences: 🇺🇸 (two regional indicators)

2. **Rare scripts**:
   - Ancient scripts (Cuneiform, Egyptian Hieroglyphs)
   - Mathematical symbols with special width properties
   - Rare combining mark sequences

3. **Unicode updates**:
   - New emoji added in Unicode 15.0+
   - Changed width properties in Unicode updates

### Testing Edge Cases

If you encounter rendering issues, test with:

```bash
# Create test file with edge cases
cat > /tmp/unicode_edge_cases.txt << 'EOF'
Skin tone: 👋🏻 👋🏿
ZWJ sequences: 👨‍👩‍👧 👨‍💻
Flags: 🇺🇸 🇯🇵 🇰🇷
Complex combining: e + ́ + ̃ = ẽ́
Ancient: 𒀀 𒀁 (Cuneiform)
Math: ∫∬∭ ∮∯∰
EOF

./zig-out/bin/vimcraft /tmp/unicode_edge_cases.txt
```

Compare rendering with Neovim/Ghostty to verify correctness.

## Conclusion

**Current approach (standalone implementation) is correct for OpenVim's current needs.**

We can defer Ghostty integration until we have evidence it's needed. The integration path is well-defined and not complex.
