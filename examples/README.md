# Vimcraft Theme Examples

This directory contains example theme files demonstrating Vimcraft's syntax highlighting system.

## Available Themes

### 1. `default.js` - Neovim-style Theme (Direct API)

**164 highlight groups** | Gruvbox-inspired | Direct `vim.api.setHighlight()` calls

```bash
OPENVIM_CONFIG=examples/default.js ./zig-out/bin/vimcraft <file>
```

**Coverage**:
- 26 traditional Vim groups (Comment, String, Function, etc.)
- ~70 tree-sitter groups (@function, @variable, @markup.*, etc.)
- ~40 UI groups (ui.text, ui.cursor, diagnostic.*, etc.)

**Use this when**: You want explicit control over every highlight group.

---

### 2. `helix-gruvbox.js` - Helix-style Theme (Helper Function)

**96 scopes** | **25 palette colors** | Automatic scope mapping

```bash
OPENVIM_CONFIG=examples/helix-gruvbox.js ./zig-out/bin/vimcraft <file>
```

**Features**:
- **Palette-based colors**: Define colors once, reference everywhere
- **Helix scope naming**: Familiar dot-notation (`ui.text.focus`, `markup.heading.1`)
- **Automatic mapping**: Helix scopes → Neovim tree-sitter groups (no manual work!)
- **Scope fallback**: `ui.text.focus` automatically falls back to `ui.text`

**Scope Mapping Examples**:
```javascript
// Helix scope → Neovim groups (automatic)
"comment"        → ["@comment", "Comment"]
"function"       → ["@function", "Function"]
"keyword.control.return" → ["@keyword.return"]
"markup.heading.1" → ["@markup.heading.1"]
"ui.text"        → ["ui.text"]  // UI scopes kept as-is
```

**Use this when**: You prefer Helix-style theme authoring or want palette-based colors.

---

## Creating Your Own Theme

### Option A: Neovim-style (Direct API)

```javascript
// theme.js
vim.api.setHighlight(0, "Comment", {
  fg: "#928374",
  italic: true
});

vim.api.setHighlight(0, "@function", {
  fg: "#fabd2f",
  bold: true
});
```

**Pros**: Explicit, full control
**Cons**: Verbose, no palette support

---

### Option B: Helix-style (Helper Function)

```javascript
// theme.js
const palette = {
  red: "#fb4934",
  blue: "#83a598",
  fg: "#ebdbb2",
  bg: "#282828"
};

const theme = {
  "ui.text": { fg: "fg", bg: "bg" },
  "comment": { fg: "gray", modifiers: ["italic"] },
  "function": { fg: "blue", modifiers: ["bold"] },
  "keyword.control.return": { fg: "red", modifiers: ["bold"] }
};

helixTheme(palette, theme);
```

**Pros**: Concise, palette-based, automatic mapping
**Cons**: Requires `helixTheme()` helper (copy from `helix-gruvbox.js`)

---

## Highlight Options Reference

Both styles support the same options:

```javascript
{
  fg: "#ff0000",           // Foreground color (hex or terminal index)
  bg: "#000000",           // Background color
  sp: "#ff0000",           // Special color (for underline/undercurl)
  bold: true,              // Bold text
  italic: true,            // Italic text
  underline: true,         // Underline
  undercurl: true,         // Curly underline (for diagnostics)
  strikethrough: true,     // Strikethrough
  link: "Function"         // Link to another group (inherits its style)
}
```

---

## Helix Scope → Neovim Mapping

The `helixTheme()` helper automatically maps Helix scopes to Neovim groups:

| Helix Scope | Neovim Groups | Notes |
|-------------|---------------|-------|
| `comment` | `@comment`, `Comment` | Both tree-sitter and traditional |
| `function` | `@function`, `Function` | Both tree-sitter and traditional |
| `function.builtin` | `@function.builtin` | Tree-sitter only (no traditional equivalent) |
| `keyword.control.return` | `@keyword.return` | Specific tree-sitter group |
| `ui.text` | `ui.text` | UI groups pass through unchanged |
| `diagnostic.error` | `diagnostic.error` | Diagnostic groups pass through unchanged |
| `markup.heading.1` | `@markup.heading.1` | Markdown-specific |

**Full mapping**: See `mapScope()` function in `helix-gruvbox.js`

---

## Best Practices

1. **Start with a base**: Copy `default.js` or `helix-gruvbox.js` as starting point
2. **Test with real files**: Load files in different languages to see coverage
3. **Check fallbacks**: Unmapped scopes will use default terminal colors
4. **Use palette colors**: Easier to adjust theme-wide color scheme
5. **Group related scopes**: Keep UI, syntax, and diagnostic groups separate

---

## Color Format

Colors can be specified as:
- **Hex**: `"#ff0000"` (24-bit RGB)
- **Terminal indexed**: `"124"` (256-color palette)
- **Palette reference** (Helix-style only): `"red"` (resolves to palette color)

---

## Loading Themes

```bash
# Via environment variable
OPENVIM_CONFIG=examples/default.js ./zig-out/bin/vimcraft file.txt

# Or create ~/.config/vimcraft/init.js
# (will be loaded automatically in Phase 5)
```

---

## Contributing

To add a new theme:
1. Create `examples/your-theme.js`
2. Choose style (direct API or Helix helper)
3. Test with multiple file types
4. Submit PR with theme file + README entry

---

**See also**:
- [Neovim highlight groups](https://neovim.io/doc/user/syntax.html#highlight-groups)
- [Tree-sitter captures](https://tree-sitter.github.io/tree-sitter/syntax-highlighting#highlights)
- [Helix themes](https://github.com/helix-editor/helix/wiki/Themes)
