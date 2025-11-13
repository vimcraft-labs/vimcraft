# Neovim Configuration Interface & Architecture Analysis

**Document Purpose**: Comprehensive guide to Neovim's Lua API and configuration architecture for informing Vimcraft's design.

**Status**: Complete analysis of Neovim 0.12.0 (master branch as of Nov 2024)

---

## Table of Contents

1. [Configuration Interface Reference](#configuration-interface-reference)
2. [Architecture Overview](#architecture-overview)
3. [Feature Gap Analysis](#feature-gap-analysis)
4. [Design Recommendations for Vimcraft](#design-recommendations-for-vimcraft)
5. [Implementation Priority Roadmap](#implementation-priority-roadmap)
6. [Code Examples & Patterns](#code-examples--patterns)

---

## Configuration Interface Reference

### 1. Options Interface (`vim.o`, `vim.opt`, `vim.bo`, `vim.wo`)

#### Quick Reference
```lua
-- Read global option (gets effective value)
vim.o.number = true              -- Gets local or global

-- Set global option (sets effective value)
vim.o.shiftwidth = 4

-- Get/set global value only (ignores local)
vim.go.number = true             -- `:setglobal`

-- Buffer-scoped options (default: current buffer)
vim.bo.readonly = true           -- Set for current buffer
vim.bo[5].autoindent = true      -- Set for buffer 5

-- Window-scoped options (default: current window)
vim.wo.number = true             -- Set for current window
vim.wo[7].wrap = false           -- Set for window 7
vim.wo[7][0].spell = false       -- Set for window 7, current buffer

-- Advanced option interface (more ergonomic for lists/maps)
vim.opt.wildignore:append('*.pyc')
vim.opt.wildignore:remove({'*.o', '*.a'})
vim.opt.wildignore:prepend('node_modules')
vim.opt_local.number = true      -- `:setlocal`
vim.opt_global.number = true     -- `:setglobal`
```

#### Implementation Details

**File**: `/runtime/lua/vim/_options.lua` (933 lines)

**Key Mechanisms**:
- **Metatables**: Each accessor (`vim.o`, `vim.bo`, etc.) uses `__index` and `__newindex` to intercept access
- **API Bridge**: All option access goes through `nvim_get_option_value()` and `nvim_set_option_value()` C functions
- **Type Handling**: Options have metatypes: `boolean`, `number`, `string`, `array`, `set`, `map`
- **Option Objects**: `vim.opt.*` returns immutable Option objects with methods: `:get()`, `:append()`, `:remove()`, `:prepend()`
- **Operators**: Supports `+`, `-`, `^` operators for option manipulation

**Key Functions**:
- `nvim_get_option_value(name, opts)` - Get option value
- `nvim_set_option_value(name, value, opts)` - Set option value
- `nvim_get_all_options_info()` - Get metadata for all options
- `nvim_get_option_info2(name, opts)` - Get metadata for specific option

**Option Categories**:
- **Global-only**: `cmdheight`, `columns`, `lines`, `tabstop`, etc.
- **Buffer-scoped**: `buflisted`, `buftype`, `fileencoding`, `autoindent`, etc.
- **Window-scoped**: `number`, `wrap`, `spell`, `foldmarker`, etc.

---

### 2. API Interface (`vim.api.*`)

#### Function Categories

**Buffer Operations**:
```lua
vim.api.nvim_create_buf(listed, scratch)  -- Create new buffer
vim.api.nvim_list_bufs()                   -- List all buffers
vim.api.nvim_get_current_buf()             -- Get current buffer
vim.api.nvim_buf_is_valid(bufnr)
vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_get_lines(bufnr, start, end, strict_indexing)
vim.api.nvim_buf_set_lines(bufnr, start, end, strict_indexing, replacement)
vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, opts)
vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, replacement)
vim.api.nvim_buf_get_offset(bufnr, lnum)
vim.api.nvim_buf_call(bufnr, fun)
vim.api.nvim_buf_set_name(bufnr, name)
vim.api.nvim_buf_get_name(bufnr)
vim.api.nvim_buf_delete(bufnr, opts)  -- Unload buffer
```

**Window Operations**:
```lua
vim.api.nvim_create_win(bufnr, enter, config)
vim.api.nvim_list_wins()
vim.api.nvim_get_current_win()
vim.api.nvim_win_get_cursor(winid)          -- [row, col] (1-indexed)
vim.api.nvim_win_set_cursor(winid, pos)
vim.api.nvim_win_get_width(winid)
vim.api.nvim_win_set_width(winid, width)
vim.api.nvim_win_get_height(winid)
vim.api.nvim_win_set_height(winid, height)
vim.api.nvim_win_is_valid(winid)
vim.api.nvim_win_close(winid, force)
vim.api.nvim_win_hide(winid)
vim.api.nvim_set_current_win(winid)
```

**Text Selection & Registers**:
```lua
vim.api.nvim_put(lines, type, after, follow)   -- Paste
vim.api.nvim_get_current_line()
vim.api.nvim_set_current_line(line)
vim.api.nvim_feedkeys(keys, mode, escape_ks)
vim.api.nvim_input(keys)
vim.api.nvim_input_mouse(button, action, modifier, grid, row, col)
```

**Search & Replace**:
```lua
vim.api.nvim_exec2(src, opts)  -- Execute Vimscript
vim.api.nvim_command(cmd)       -- Execute single command (deprecated, use nvim_cmd)
vim.api.nvim_cmd(command_dict, opts)
```

**Highlighting & Namespaces**:
```lua
vim.api.nvim_create_namespace(name)  -- Create extmark namespace
vim.api.nvim_set_hl(ns, name, val)   -- Set highlight group
vim.api.nvim_get_hl(ns, opts)        -- Get highlight definition
vim.api.nvim_buf_set_extmark(bufnr, ns, line, col, opts)
vim.api.nvim_buf_get_extmarks(bufnr, ns, start, end, opts)
vim.api.nvim_buf_del_extmark(bufnr, ns, id)
vim.api.nvim_buf_clear_namespace(bufnr, ns, line_start, line_end)
```

**Key Mappings**:
```lua
vim.api.nvim_set_keymap(mode, lhs, rhs, opts)
vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
vim.api.nvim_del_keymap(mode, lhs)
vim.api.nvim_buf_del_keymap(bufnr, mode, lhs)
vim.api.nvim_get_keymap(mode)
vim.api.nvim_buf_get_keymap(bufnr, mode)
```

**Autocommands**:
```lua
vim.api.nvim_create_autocmd(event, opts)
vim.api.nvim_create_augroup(name, opts)
vim.api.nvim_get_autocmds(opts)
vim.api.nvim_del_autocmd(id)
vim.api.nvim_del_augroup_by_name(name)
vim.api.nvim_del_augroup_by_id(id)
vim.api.nvim_exec_autocmds(event, opts)
```

**User Commands**:
```lua
vim.api.nvim_create_user_command(name, command, opts)
vim.api.nvim_del_user_command(name)
vim.api.nvim_get_commands(opts)
```

**Variables & Environment**:
```lua
vim.api.nvim_get_var(name)
vim.api.nvim_set_var(name, value)
vim.api.nvim_del_var(name)
vim.api.nvim_get_vvar(name)      -- |v:| variables (read-only mostly)
vim.api.nvim_get_env()
```

**UI & Messages**:
```lua
vim.api.nvim_echo(chunks, history, opts)
vim.api.nvim_notify(msg, log_level, opts)
vim.api.nvim_err_writeln(str)
vim.api.nvim_out_write(str)
```

**Miscellaneous**:
```lua
vim.api.nvim_get_mode()          -- Current mode: {mode='n', blocking=false}
vim.api.nvim_get_current_buf()
vim.api.nvim_get_current_win()
vim.api.nvim_get_current_tabpage()
vim.api.nvim_replace_termcodes(str, from_part, do_lt, special)
```

#### Implementation Details

**File**: `/src/nvim/api/vim.c` (78KB - largest API file)

**Core Pattern**:
1. All API functions use `Object_to_*` converters (types.c)
2. Functions register with `nvim_*` naming convention
3. All 1-based Vim indexing converted to 0-based for Lua (via API)
4. Functions validate arguments before executing
5. Return `nil` on error (wrapped by error handling)

**Error Handling**:
- Function returns `(result, error)` tuple at C level
- Lua wrapper converts to exception on error
- Error messages use consistent format

---

### 3. Variable Accessors (`vim.g`, `vim.b`, `vim.w`, `vim.t`, `vim.v`, `vim.env`)

```lua
-- Global variables (|g:|)
vim.g.mapleader = ' '
vim.g.foo = { nested = 'table' }
vim.g.foo = nil  -- Delete variable

-- Buffer variables (|b:|) - default: current buffer
vim.b.filetype = 'lua'
vim.b[5].marker = 'custom'  -- Set for buffer 5

-- Window variables (|w:|) - default: current window
vim.w.myvar = 42
vim.w[7].custom = true  -- Set for window 7

-- Tabpage variables (|t:|) - default: current tabpage
vim.t.tab_local = 'value'

-- Built-in variables (|v:|) - mostly read-only
print(vim.v.version)
print(vim.v.maxcol)
print(vim.v.errors)

-- Environment variables (matches shell environment)
vim.env.TERM = 'xterm-256color'
vim.env.PATH = vim.env.PATH .. ':/custom/path'
```

#### Implementation Details

**File**: `/runtime/lua/vim/_editor.lua` lines 413-438

**Mechanism**:
- Creates dictionary accessors using metatable `__index` and `__newindex`
- Single-parameter accessor (`vim.g`, `vim.b`, `vim.w`, `vim.t`)
- Can be indexed with integer for specific scope (`vim.b[5]`, `vim.w[7]`)
- Returns copy of value (marshalling behavior)

**Important Note**: Setting nested fields doesn't work directly:
```lua
-- This does NOT work (modifies copy, not original):
vim.g.my_dict.field = 'value'

-- Do this instead:
local d = vim.g.my_dict
d.field = 'value'
vim.g.my_dict = d
```

---

### 4. Keymap Interface (`vim.keymap.set`, `vim.keymap.del`)

```lua
-- Basic mapping
vim.keymap.set('n', 'x', function() print('hello') end)

-- Multiple modes
vim.keymap.set({'n', 'v'}, '<leader>y', '"+y')

-- Buffer-local
vim.keymap.set('n', '<leader>q', vim.lsp.buf.hover, { buffer = true })
vim.keymap.set('n', 'x', function() end, { buffer = 5 })  -- Buffer 5

-- Expression mapping
vim.keymap.set('i', '<Tab>', function()
  return vim.fn.pumvisible() == 1 and '<C-n>' or '<Tab>'
end, { expr = true })

-- Remap mode control
vim.keymap.set('n', 'x', 'dd', { remap = true })  -- Allows recursion
vim.keymap.set('n', 'x', 'dd', { noremap = true })  -- Default

-- Delete mapping
vim.keymap.del('n', 'x')
vim.keymap.del({'n', 'i'}, '<Tab>', { buffer = true })
```

#### Implementation Details

**File**: `/runtime/lua/vim/keymap.lua` (133 lines)

**Key Points**:
- `remap` option (defaults to false, opposite of `noremap`)
- `expr` option enables expression mapping
- `callback` option for Lua functions (replaces `rhs`)
- `buffer` option for buffer-local mappings
- Can map to `<Plug>` mappings
- Lua functions receive no arguments

---

### 5. Command Interface (`vim.cmd`, `vim.cmd.<command>`)

```lua
-- Execute Vimscript string
vim.cmd('echo "hello"')
vim.cmd('set number')

-- Multiline Vimscript
vim.cmd([[
  augroup MyGroup
    autocmd!
    autocmd BufRead * call SomeFunc()
  augroup END
]])

-- Ex command with arguments (dict syntax)
vim.cmd.write('myfile.txt')
vim.cmd.echo('"hello"')
vim.cmd.resize({ '+5' })
vim.cmd.resize({ '+5', mods = { vertical = true } })

-- Full dict form
vim.cmd({
  cmd = 'split',
  args = { 'newfile.lua' },
  mods = { vertical = true },
  bang = true
})
```

#### Implementation Details

**File**: `/runtime/lua/vim/_editor.lua` lines 328-407

**Key Mechanisms**:
- `vim.cmd()` with string executes via `nvim_exec2()` (multiline Vimscript)
- `vim.cmd()` with table executes single command via `nvim_cmd()`
- `vim.cmd.<command>()` creates command wrapper dynamically
- Converts Lua calling convention to Vimscript format
- Up to 20 positional arguments supported

---

### 6. Function Interface (`vim.fn.*`)

```lua
-- Call Vimscript functions
local cwd = vim.fn.getcwd()
local input = vim.fn.input('Enter value: ')
local lines = vim.fn.readfile('/path/to/file')

-- Call user-defined functions
local result = vim.fn.MyCustomFunction(arg1, arg2)

-- Call autoload functions
local result = vim.fn['plugin#function'](args)

-- Direct conversion between Vim types and Lua
local list = vim.fn.split('a,b,c', ',')  -- Returns {a, b, c}
local dict = vim.fn.json_decode('{"key": "value"}')  -- Returns table

-- Note: vim.fn keys are lazy-generated
-- Call a function once to cache it
_ = vim.fn.getcwd()
```

#### Implementation Details

**File**: `/runtime/lua/vim/_editor.lua` lines 301-321

**Behavior**:
- Uses metatable `__index` to dynamically wrap Vimscript functions
- Type conversion handled by Lua converter (types.c)
- `vim.NIL` used for Vimscript `v:null`
- Empty lists and dicts both map to empty `{}`
- Cannot be called with certain fast API callbacks

---

### 7. Highlight Interface (`vim.hl`)

```lua
-- Get highlight definition
local hl = vim.api.nvim_get_hl(0, { name = 'Normal' })
-- Returns: { foreground = 16777215, background = 0, ... }

-- Set highlight group
vim.api.nvim_set_hl(0, 'MyHighlight', {
  fg = '#ffffff',
  bg = 'red',
  bold = true,
  underline = true,
  italic = true,
  reverse = false,
  strikethrough = false,
  undercurl = false,
  link = 'Normal'  -- Link to another group
})

-- Highlight range of text
local ns = vim.api.nvim_create_namespace('mynamespace')
vim.hl.range(bufnr, ns, 'Error', {1, 0}, {1, 5}, {
  regtype = 'v',   -- charwise
  inclusive = false,
  priority = vim.hl.priorities.user,
  timeout = 300
})

-- On-yank highlight
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank({ higroup = 'Visual', timeout = 300 })
  end
})
```

#### Implementation Details

**File**: `/runtime/lua/vim/hl.lua` (204 lines)

**Key Concepts**:
- **Namespaces**: Groups of highlights with separate priority
- **Priorities**: Determine order of display (higher = on top)
  - `syntax`: 50
  - `treesitter`: 100
  - `semantic_tokens`: 125
  - `diagnostics`: 150
  - `user`: 200
- **Extmarks**: Low-level mechanism for associating highlights with text
- **Color Format**: Hex strings, names, or 24-bit RGB

---

### 8. Autocommand Interface (`vim.api.nvim_create_autocmd`)

```lua
-- Basic autocommand
vim.api.nvim_create_autocmd('BufRead', {
  callback = function(args)
    print('Buffer ' .. args.buf .. ' was read')
  end
})

-- With pattern matching
vim.api.nvim_create_autocmd('BufRead', {
  pattern = '*.lua',
  callback = function(args)
    vim.bo[args.buf].filetype = 'lua'
  end
})

-- With autogroup
vim.api.nvim_create_augroup('MyGroup', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = 'MyGroup',
  pattern = 'lua',
  callback = function(args)
    vim.bo[args.buf].shiftwidth = 2
  end
})

-- Command instead of callback
vim.api.nvim_create_autocmd('BufWrite', {
  pattern = '*.lua',
  command = 'lua vim.lsp.buf.format()'
})

-- Once-only
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function() print('started') end
})

-- Multiple events
vim.api.nvim_create_autocmd({'BufNew', 'BufRead'}, {
  callback = function() end
})
```

#### Events Supported
- `BufNew`, `BufRead`, `BufWrite`, `BufWritePre`, `BufWritePost`
- `FileType`, `Syntax`
- `VimEnter`, `VimLeave`
- `WinEnter`, `WinLeave`, `WinNew`, `WinClosed`
- `CmdlineEnter`, `CmdlineLeave`
- `TextChanged`, `TextChangedI`
- `InsertEnter`, `InsertLeave`
- `CursorMoved`, `CursorMovedI`
- `SessionLoadPost`, `SourcePre`
- And ~50+ more...

---

### 9. User Command Interface (`vim.api.nvim_create_user_command`)

```lua
-- Simple command
vim.api.nvim_create_user_command('MyCommand', function(opts)
  print('Command called with args: ' .. opts.args)
end, { nargs = '*' })

-- With completion
vim.api.nvim_create_user_command('MyCommand', function(opts)
  -- ...
end, {
  nargs = 1,
  complete = function(argLead, cmdline, cursorpos)
    return { 'option1', 'option2' }
  end
})

-- Command with bang support
vim.api.nvim_create_user_command('Reload', function(opts)
  if opts.bang then
    print('Force reload')
  else
    print('Normal reload')
  end
end, { bang = true })

-- Range command
vim.api.nvim_create_user_command('Comment', function(opts)
  print('Lines ' .. opts.line1 .. ' to ' .. opts.line2)
end, { range = '%' })
```

#### Options
- `nargs`: Number of arguments (0, 1, ?, *, +)
- `complete`: Custom completion function
- `bang`: Allow `!` suffix
- `range`: Allow range (true, 1, '%', default)
- `bar`: Allow chaining with |
- `register`: Allow `"a` style registers
- `buffer`: Buffer-local command (bufnr)

---

### 10. Diagnostic Interface (`vim.diagnostic`)

```lua
-- Set diagnostics
vim.diagnostic.set(namespace, bufnr, {
  {
    lnum = 0,        -- 0-indexed line
    col = 0,
    end_lnum = 0,
    end_col = 5,
    message = 'Error message',
    severity = vim.diagnostic.severity.ERROR,
    source = 'mylinter',
    code = 'E001'
  }
})

-- Get diagnostics
local diags = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })

-- Configure diagnostic display
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true
})

-- Jump to diagnostic
vim.diagnostic.jump({ float = true })  -- Jump to next with float

-- Show diagnostic at cursor
vim.diagnostic.open_float()
```

**Severity Levels**:
- `vim.diagnostic.severity.ERROR` (1)
- `vim.diagnostic.severity.WARN` (2)
- `vim.diagnostic.severity.INFO` (3)
- `vim.diagnostic.severity.HINT` (4)

---

### 11. LSP Interface (`vim.lsp`)

The LSP interface is extensive (~1700 lines across multiple files):

```lua
-- Start LSP client
local client_id = vim.lsp.start({
  name = 'mylsp',
  cmd = { 'my-lsp-server' },
  root_dir = vim.fs.dirname(vim.fs.find({'package.json'})[1]),
})

-- Attach to buffer
vim.lsp.buf_attach_client(bufnr, client_id)

-- Buffer commands (called on current buffer)
vim.lsp.buf.hover()
vim.lsp.buf.definition()
vim.lsp.buf.references()
vim.lsp.buf.rename('new_name')
vim.lsp.buf.format()
vim.lsp.buf.code_action()
vim.lsp.buf.signature_help()

-- Show diagnostics in floating window
vim.diagnostic.open_float()
vim.diagnostic.setqflist()

-- Semantic tokens (for better syntax highlighting)
vim.lsp.semantic_tokens.start(bufnr, client_id)
```

**Architecture**:
- Single global LSP client manager
- Per-buffer client attachment
- RPC protocol over stdio/socket
- Type checking via |vim._meta|

---

### 12. Treesitter Interface (`vim.treesitter`)

```lua
-- Get/parse tree for buffer
local parser = vim.treesitter.get_parser(bufnr, 'lua')
local tree = parser:parse()
local root = tree:root()

-- Query for nodes
local query = vim.treesitter.query.get('lua', 'highlights')
for _, match, metadata in query:iter_matches(root, bufnr, 0, -1) do
  -- Process matches...
end

-- Get node at position
local node = vim.treesitter.get_node({ bufnr = bufnr, pos = {row, col} })

-- Text extraction
local text = vim.treesitter.get_node_text(node, bufnr)

-- Highlighting
vim.treesitter.start(bufnr, 'lua')  -- Enable highlighting
vim.treesitter.stop(bufnr)
```

**Key Components**:
- **Parsers**: Language-specific syntax tree parsers
- **Queries**: XPath-like syntax for tree traversal
- **Nodes**: Tree nodes with type, text, range info
- **Highlighter**: Per-buffer highlighter instance

---

### 13. Async/System Interface

```lua
-- Execute system command
local obj = vim.system({'ls', '-la'}, {
  text = true,
  capture_output = true
}, function(result)
  print(result.stdout)
end)

-- Wait synchronously
local result = obj:wait()
print(result.stdout, result.stderr, result.code)

-- Async execution wrapper
vim.schedule(function()
  -- Runs on main thread (safe for API calls)
end)

-- Deferred function call
local timer = vim.defer_fn(function()
  print('Called after 100ms')
end, 100)

-- Async task with coroutines (advanced)
local async = require('vim._async')
async.run(function()
  local result = async.await(1, vim.system, {'echo', 'hello'})
end)
```

---

## Architecture Overview

### Layer 1: C Core (src/nvim/)

The Neovim C core (~100K lines) provides:

1. **Buffer Management**
   - Text storage with line-based indexing
   - Mark tracking (a-z, A-Z)
   - Undo/redo tree
   - Multiple buffers in memory

2. **Window Management**
   - Viewport management
   - Cursor tracking per window
   - Window layout (splits, tabs)
   - Syntax highlighting engine

3. **Input Processing**
   - Terminal input handling
   - Keycode translation
   - Mode state machine (Normal/Insert/Visual/Command)
   - Mapping system

4. **Rendering**
   - ANSI terminal rendering
   - Line wrapping
   - Syntax coloring
   - Cursor positioning

5. **Vimscript Engine**
   - Expression evaluation
   - Function definition/calling
   - Variable scoping (g:/l:/a:/etc.)
   - Ex command parsing

6. **Lua Integration** (recent additions)
   - Lua 5.1 runtime embedded
   - Type converters for Vim<->Lua
   - API function registration
   - Error handling bridges

### Layer 2: API Bridge (src/nvim/api/)

**Size**: ~500KB total across all api/*.c files

**Files**:
- `vim.c` (78KB) - Main API functions
- `buffer.c` (45KB) - Buffer operations
- `window.c` (24KB) - Window operations
- `command.c` (44KB) - User commands
- `autocmd.c` (28KB) - Autocommands
- `extmark.c` (47KB) - Highlighting via extmarks
- `options.c` (11KB) - Option get/set
- `ui.c` (32KB) - UI integration
- Plus: tabpage.c, vimscript.c, etc.

**Key Patterns**:
1. All functions use `nvim_*` naming
2. Arguments validated before processing
3. Return `Object` type (union of: nil, bool, int, float, string, array, dict)
4. Error propagation via return structs
5. Buffer/window handles (integers) instead of pointers

### Layer 3: Lua Standard Library (runtime/lua/vim/)

**Size**: ~23,400 lines across 117 files

**Organization**:

```
vim/
├── _editor.lua          # Eager-loaded (paste, print, schedule_wrap)
├── _options.lua         # Option accessors (vim.o, vim.opt, etc.)
├── keymap.lua           # vim.keymap.set/del
├── diagnostic.lua       # Diagnostic system (~1000 lines)
├── hl.lua               # Highlight utilities
├── ui.lua               # UI hooks (select, input, open)
├── lsp.lua              # Language Server Protocol (~1700 lines)
├── treesitter.lua       # Tree-sitter integration (~350 lines)
├── fs.lua               # File system utilities
├── shared.lua           # Common utilities (~1700 lines)
├── iter.lua             # Iterator abstractions (~900 lines)
├── inspect.lua          # Pretty-printing
├── loader.lua           # Module loader with profiling
├── filetype.lua         # File type detection
├── pack.lua             # Package management
├── health.lua           # Health check system
├── _async.lua           # Async/await pattern
├── _system.lua          # System command execution
├── _watch.lua           # File watching
├── _defaults.lua        # Default settings (~35KB)
├── _meta/               # Type information for IDE support
│   ├── api.lua          # API type stubs
│   ├── builtin.lua      # Built-in type stubs
│   ├── options.lua      # Options type stubs
│   └── vimfn.lua        # Vimscript functions type stubs
└── lsp/                 # LSP subsystem
    ├── rpc.lua          # RPC protocol
    ├── buf.lua          # Buffer operations
    ├── client.lua       # Client management
    ├── handlers.lua     # Response handlers
    ├── diagnostic.lua   # LSP diagnostics
    ├── completion.lua   # Completion integration
    └── ~20 more...
```

### Layer 4: Init & Startup (src/nvim/main.c, runtime/init.lua)

**Startup Sequence**:
1. C code initializes Neovim core
2. Terminal setup (raw mode, signal handlers)
3. Lua 5.1 runtime initialized
4. `/runtime/lua/vim/_editor.lua` loaded (eager)
5. User config `~/.config/nvim/init.lua` executed
6. Plugins loaded
7. Main event loop starts

**File Locations**:
- `~/.config/nvim/init.lua` - User config entry point
- `~/.config/nvim/init.vim` - Legacy config
- `~/.config/nvim/plugin/` - Auto-loaded plugins
- `~/.config/nvim/ftplugin/` - File type plugins

### Design Patterns in Neovim

#### 1. Metatable Accessors
Used for `vim.o`, `vim.g`, `vim.fn`, `vim.cmd`:
```lua
local mt = {
  __index = function(t, k) return get_value(k) end,
  __newindex = function(t, k, v) set_value(k, v) end
}
return setmetatable({}, mt)
```

**Advantages**:
- Natural syntax (`vim.g.myvar = 5`)
- Lazy initialization
- Transparent C integration

#### 2. Namespace Isolation
Autocommands and diagnostics use numeric namespace IDs:
```lua
local ns = vim.api.nvim_create_namespace('plugin.name')
vim.api.nvim_set_hl(ns, 'group', {...})
```

**Advantages**:
- Multiple systems can coexist
- Easy cleanup/isolation
- Priority ordering

#### 3. Options Wrapper Objects
`vim.opt.*` returns objects with methods instead of raw values:
```lua
local opt = vim.opt.runtimepath
opt:append('/new/path')      -- Method form
opt = opt + '/new/path'       -- Operator form
```

**Advantages**:
- Ergonomic API for complex types
- Immutable operation semantics
- Type-aware conversions

#### 4. Lazy Module Loading
Modules declared in `_editor.lua`:
```lua
vim._submodules[k] = v  -- Mark for lazy loading
```

Then accessed via `__index` metatable which calls `require()` on first access.

**Advantages**:
- Fast startup (LSP, treesitter not loaded immediately)
- On-demand loading of heavy modules
- Transparent to users

#### 5. Type Metadata Layers
Three separate type definition systems:
- **Lua**: Full implementation code
- **Vimscript**: Type stubs via `:help`
- **Type Hints**: `_meta/*.lua` files for IDE support

#### 6. Configuration via Tables
Consistent pattern for passing options:
```lua
function do_something(opts)
  opts = opts or {}
  local foo = opts.foo or 'default'
  -- ...
end
```

All complex APIs use named options instead of positional args.

---

## Feature Gap Analysis

### Core Features (Phase 1-2): Status

| Feature | Vimcraft | Neovim | Priority |
|---------|---------|--------|----------|
| **Buffer Management** | | |
| Text storage | ✅ ArrayList | ✅ Gap buffer | HIGH |
| Multiple buffers | ✅ Partial | ✅ Full | HIGH |
| Line indexing | ✅ Yes | ✅ Yes | - |
| Marks (a-z) | ❌ No | ✅ Yes | MED |
| **Cursor & Movement** | | |
| Normal mode hjkl | ✅ Yes | ✅ Yes | - |
| Word motion (w/b/e) | ✅ Yes | ✅ Yes | - |
| Start/end (gg/G) | ✅ Yes | ✅ Yes | - |
| Line start/end (0/$) | ✅ Yes | ✅ Yes | - |
| Page scroll (Ctrl+D/U) | ✅ Yes | ✅ Yes | - |
| **Mode System** | | |
| Normal mode | ✅ Yes | ✅ Yes | - |
| Insert mode | ✅ Basic | ✅ Full | HIGH |
| Visual mode | ✅ Partial | ✅ Full | HIGH |
| Command mode | ❌ No | ✅ Yes | HIGH |
| **Text Editing** | | |
| Insert chars | ✅ Yes | ✅ Yes | - |
| Delete operator | ❌ No | ✅ Yes | HIGH |
| Change operator | ❌ No | ✅ Yes | HIGH |
| Yank/paste | ❌ No | ✅ Yes | HIGH |
| Undo/redo | ❌ No | ✅ Yes | HIGH |

### Plugin/Configuration Features: Status

| Feature | Vimcraft | Neovim | Priority |
|---------|---------|--------|----------|
| **Configuration** | | |
| vim.opt | ❌ No | ✅ Yes | VERY HIGH |
| vim.keymap | ❌ No | ✅ Yes | VERY HIGH |
| vim.api | ✅ Partial | ✅ Full | VERY HIGH |
| vim.cmd | ❌ No | ✅ Yes | HIGH |
| **Plugin System** | | |
| JavaScript execution | ✅ Hermes | ✅ Via Lua | HIGH |
| Config hot-reload | ✅ Yes | ❌ No | MED |
| Autocommands | ❌ No | ✅ Yes | HIGH |
| User commands | ❌ No | ✅ Yes | HIGH |
| **Integrations** | | |
| Syntax highlighting | ❌ No | ✅ TreeSitter | MED |
| LSP support | ❌ No | ✅ Full | MED |
| Diagnostics | ❌ No | ✅ Full | MED |

### Feature Estimation

**Phase 3 (Text Editing)**: 4-6 weeks
- Delete operators (d, x)
- Change operators (c)
- Yank/paste (y, p)
- Visual selection
- Undo/redo tree

**Phase 4 (Plugin System)**: 6-8 weeks
- Integrate Hermes into main binary
- Expose buffer/window API to JS
- Configuration loader
- Event system

**Phase 5 (Advanced Features)**: 8-12 weeks
- Autocommands
- User commands
- Search/replace
- Command mode
- Ex commands

**Phase 6+ (Ecosystem)**: 12+ weeks
- Syntax highlighting
- LSP integration
- Split windows
- Tab pages
- Plugin ecosystem

---

## Design Recommendations for Vimcraft

### 1. Configuration Architecture

**Recommendation**: Exactly mirror Neovim's approach but in Zig + JavaScript

**Structure**:
```
~/.config/vimcraft/
├── init.lua                    # Main config (compiled from init.js)
├── init.js                     # User-friendly entry point
├── plugin/
│   └── myplugin.js            # Auto-loaded plugins
├── ftplugin/
│   └── lua.js                 # File-type plugins
└── colors/
    └── mycolorscheme.js       # Color schemes
```

**Implementation**:
1. **Zig API Layer** (exposes editor to JavaScript)
   - `ov_api.set_keymap(mode, lhs, rhs, opts)`
   - `ov_api.create_autocmd(event, opts)`
   - `ov_api.set_option(name, value)`
   - `ov_api.create_user_command(name, callback, opts)`

2. **JavaScript API Layer** (user-facing)
   ```javascript
   // init.js
   const ov = require('vimcraft');
   ov.keymap.set('n', '<leader>x', () => {
     console.log('hello');
   });
   ov.option.number = true;
   ```

3. **Hot Reload Support**
   - File watcher on config directory
   - Reload on change (already in Vimcraft!)
   - Clear timers/intervals before reload

### 2. API Organization

**Recommendation**: Create typed module structure matching Neovim

**Core Modules** (Phase 1):
- `ov.api.*` - Core editor functions
- `ov.buf` - Buffer operations
- `ov.win` - Window operations
- `ov.keymap` - Key mapping

**Standard Library** (Phase 2+):
- `ov.opt` - Options interface
- `ov.cmd` - Command execution
- `ov.fn` - Vimscript function calls (if implementing VimScript)
- `ov.lsp` - Language server support
- `ov.treesitter` - Syntax tree support

### 3. Options System Design

**Create `ov.opt` matching `vim.opt` exactly**:

```zig
// src/config/options.zig
const OptionInfo = struct {
    name: []const u8,
    metatype: enum { boolean, number, string, array, set, map },
    scope: enum { global, buffer, window },
    default_value: Value,
};

const OptionsTable = std.StringHashMap(OptionInfo);
```

**JavaScript Interface**:
```javascript
ov.opt.number = true;           // Set
console.log(ov.opt.number);     // Get
ov.opt.wildignore:append('*.o'); // Method
ov.opt_local.wrap = false;      // Buffer-local
```

### 4. Autocommand Architecture

**Recommendation**: Implement event-driven architecture

```zig
// src/event/autocommand.zig
const AutoCommand = struct {
    id: u64,
    event: EventType,
    pattern: ?[]const u8 = null,
    callback: CallbackFn,
    group: ?u64 = null,
    once: bool = false,
};

const AutoGroupManager = struct {
    groups: std.StringHashMap(std.ArrayList(u64)),
    commands: std.ArrayList(AutoCommand),
};
```

**Events** (subset of Neovim's):
- `BufRead`, `BufWrite`, `BufWritePre`, `BufWritePost`
- `FileType`
- `VimEnter`, `VimLeave`
- `InsertEnter`, `InsertLeave`
- `CursorMoved`
- `TextChanged`

### 5. User Command System

**Recommendation**: Simple command registration with optional completion

```zig
// src/command/user_command.zig
const UserCommand = struct {
    name: []const u8,
    callback: CallbackFn,
    nargs: enum { zero, one, any, plus, question },
    complete: ?CompletionFn = null,
    bang: bool = false,
};
```

### 6. Highlight System

**Recommendation**: Use extmarks model from Neovim

```zig
// src/highlight/extmark.zig
const ExtMark = struct {
    bufnr: u32,
    ns_id: u32,
    line: u32,
    col: u32,
    end_line: u32,
    end_col: u32,
    hl_group: []const u8,
    priority: u32,
};
```

**Features to Implement**:
- Namespace isolation
- Priority ordering
- Timeout support
- Per-window scope

### 7. Type System (TypeScript Support)

**Recommendation**: Generate type definitions for IDE support

```typescript
// types/vimcraft.d.ts
declare namespace ov {
  namespace api {
    function nvim_get_current_buf(): number;
    function nvim_buf_get_lines(bufnr: number, start: number, end: number, strict: boolean): string[];
    // ... all API functions
  }
  
  namespace opt {
    let number: boolean;
    let shiftwidth: number;
    let wildignore: string[];
  }
  
  namespace keymap {
    function set(mode: string|string[], lhs: string, rhs: string|Function, opts?: KeymapOpts): void;
    function del(mode: string|string[], lhs: string, opts?: {buffer?: number}): void;
  }
}
```

### 8. Backward Compatibility Strategy

**Like Neovim**, use deprecation markers:
- Mark old APIs with `@deprecated` in comments
- Provide migration paths
- Support both old and new for 2-3 releases
- Clear deprecation warnings in logs

**Example**:
```javascript
// Deprecated
ov.map('n', 'x', 'dd');

// New way
ov.keymap.set('n', 'x', 'dd');
```

---

## Implementation Priority Roadmap

### Phase 3: Text Editing (Vimcraft Enhancement)
**Estimated**: 4-6 weeks | **Difficulty**: HIGH

**Critical Path**:
1. **Delete Operators** (1 week)
   - `x` - delete char
   - `d<motion>` - delete motion
   - `dd` - delete line
   - Implement pending command system (`PendingCommand` struct exists!)
   
2. **Change Operators** (1 week)
   - `c<motion>` - change motion
   - `cc` - change line
   - Transition to insert mode after change
   
3. **Yank/Paste** (1 week)
   - `y<motion>` - yank motion
   - `yy` - yank line
   - `p` - paste after
   - `P` - paste before
   - Registers (default: unnamed register)
   
4. **Visual Mode** (1 week)
   - `v` - character selection
   - `V` - line selection
   - `<C-v>` - block selection
   - Operators on selection (d, c, y)
   
5. **Undo/Redo** (1 week)
   - `u` - undo
   - `<C-r>` - redo
   - Transaction system (group changes)
   - Implement change tracking

### Phase 4: Plugin System (NEW)
**Estimated**: 6-8 weeks | **Difficulty**: VERY HIGH

**Critical Path**:
1. **API Foundation** (2 weeks)
   - Expose buffer/window/option APIs to JavaScript
   - Implement `ov.api.*` functions
   - Type converters (Zig ↔ JavaScript)
   - Error handling across boundary

2. **Configuration System** (2 weeks)
   - Options interface (`ov.opt.*`)
   - Keymap interface (`ov.keymap.set/del`)
   - Command execution (`ov.cmd`)
   - Hot reload mechanism (refine existing)

3. **Plugin Loader** (1 week)
   - Auto-load from `~/.config/vimcraft/plugin/`
   - File type plugins from `ftplugin/`
   - Plugin isolation (separate Hermes contexts? or shared?)

4. **Event System** (1 week)
   - Autocommands (`ov.autocmd.create`)
   - Event dispatcher
   - Buffer/window change events

### Phase 5: Advanced Features
**Estimated**: 8-12 weeks | **Difficulty**: HIGH

**Could Do Items** (pick 3-4):
1. **Search & Replace** (2 weeks)
   - `/pattern` - forward search
   - `?pattern` - backward search
   - `:s/old/new/g` - substitute
   - Incremental search display

2. **Command Mode** (2 weeks)
   - `:` entry
   - Ex commands (`:w`, `:q`, `:e`, `:set`)
   - Command history
   - Command completion

3. **Syntax Highlighting** (3 weeks)
   - Tree-sitter integration
   - Highlight group system
   - Color scheme support
   - Incremental highlighting

4. **Advanced Motion** (1 week)
   - `f` - find char on line
   - `t` - 'til char
   - `;` - repeat find
   - `/` - search as motion

---

## Code Examples & Patterns

### Example 1: Implementing `vim.opt` in Zig

```zig
// config/options.zig

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OptionType = enum { boolean, number, string, array, set, map };

pub const Option = struct {
    name: []const u8,
    value: OptionValue,
    option_type: OptionType,
    
    pub fn get(self: *const Option) OptionValue {
        return self.value;
    }
    
    pub fn set(self: *Option, value: OptionValue) !void {
        switch (self.option_type) {
            .boolean => {
                if (value != .boolean) return error.InvalidType;
                self.value = value;
            },
            .array => {
                if (value != .array) return error.InvalidType;
                self.value = value;
            },
            // ... handle other types
        }
    }
    
    pub fn append(self: *Option, value: OptionValue, allocator: Allocator) !void {
        switch (self.option_type) {
            .array => {
                var arr = try self.value.array.clone(allocator);
                try arr.append(value);
                self.value = .{ .array = arr };
            },
            else => return error.InvalidOperationForType,
        }
    }
};

pub const OptionValue = union(enum) {
    boolean: bool,
    number: i64,
    string: []const u8,
    array: std.ArrayList(OptionValue),
    set: std.StringHashMap(bool), // flags
    map: std.StringHashMap([]const u8),
};

pub const OptionsManager = struct {
    options: std.StringHashMap(Option),
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) OptionsManager {
        return .{
            .options = std.StringHashMap(Option).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn set(self: *OptionsManager, name: []const u8, value: OptionValue) !void {
        if (self.options.getPtr(name)) |opt| {
            try opt.set(value);
        } else {
            return error.UnknownOption;
        }
    }
    
    pub fn get(self: *OptionsManager, name: []const u8) !OptionValue {
        if (self.options.get(name)) |opt| {
            return opt.get();
        } else {
            return error.UnknownOption;
        }
    }
};
```

### Example 2: JavaScript Configuration Interface

```javascript
// config/vimcraft.js - User's init file

const ov = require('vimcraft');

// Options
ov.opt.number = true;
ov.opt.shiftwidth = 4;
ov.opt.expandtab = true;
ov.opt.wildignore = ['*.o', '*.a', '*.pyc'];

// Keymaps
ov.keymap.set('n', '<leader>w', () => {
  ov.api.nvim_buf_set_lines(0, -1, -1, false, ['']);
}, { noremap = true });

ov.keymap.set('i', '<Tab>', () => {
  return ov.fn.pumvisible() === 1 ? '<C-n>' : '<Tab>';
}, { expr = true });

// Autocommands
ov.autocmd.create('FileType', {
  pattern = 'lua',
  callback = (args) => {
    ov.buf[args.buf].shiftwidth = 2;
  }
});

// User commands
ov.command.create('Format', () => {
  ov.lsp.buf.format();
}, {});

// Plugin loading
require('./plugins/lsp-config');
require('./plugins/treesitter-config');
```

### Example 3: Autocommand System in Zig

```zig
// event/autocommand.zig

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EventType = enum {
    buf_read,
    buf_write,
    buf_write_pre,
    file_type,
    vim_enter,
    insert_enter,
    insert_leave,
    cursor_moved,
    text_changed,
    // ... more events
};

pub const AutoCommand = struct {
    id: u64,
    event: EventType,
    pattern: ?[]const u8,
    callback: *JSFunction, // Hermes function pointer
    group: ?[]const u8,
    once: bool,
};

pub const AutoCommandManager = struct {
    commands: std.ArrayList(AutoCommand),
    groups: std.StringHashMap(std.ArrayList(u64)),
    next_id: u64 = 1,
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) AutoCommandManager {
        return .{
            .commands = std.ArrayList(AutoCommand).init(allocator),
            .groups = std.StringHashMap(std.ArrayList(u64)).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn create(
        self: *AutoCommandManager,
        event: EventType,
        opts: struct {
            pattern: ?[]const u8 = null,
            callback: *JSFunction,
            group: ?[]const u8 = null,
            once: bool = false,
        },
    ) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        
        try self.commands.append(.{
            .id = id,
            .event = event,
            .pattern = opts.pattern,
            .callback = opts.callback,
            .group = opts.group,
            .once = opts.once,
        });
        
        // Add to group
        if (opts.group) |group_name| {
            var group_list = try self.groups.getOrPut(group_name);
            if (!group_list.found_existing) {
                group_list.value_ptr.* = std.ArrayList(u64).init(self.allocator);
            }
            try group_list.value_ptr.append(id);
        }
        
        return id;
    }
    
    pub fn fire(self: *AutoCommandManager, event: EventType, args: AnyType) !void {
        for (self.commands.items) |cmd| {
            if (cmd.event == event) {
                // Call JavaScript callback
                // TODO: Call Hermes function with args
                
                if (cmd.once) {
                    try self.delete(cmd.id);
                }
            }
        }
    }
    
    pub fn delete(self: *AutoCommandManager, id: u64) !void {
        const idx = for (self.commands.items, 0..) |cmd, i| {
            if (cmd.id == id) break i;
        } else return error.NotFound;
        
        _ = self.commands.orderedRemove(idx);
    }
    
    pub fn deleteByGroup(self: *AutoCommandManager, group_name: []const u8) !void {
        if (self.groups.get(group_name)) |group_ids| {
            for (group_ids.items) |id| {
                try self.delete(id);
            }
        }
    }
};
```

### Example 4: Neovim-Style API Wrapper

```zig
// api/buffer.zig

const std = @import("std");
const Buffer = @import("../buffer/buffer.zig").Buffer;

pub const BufferAPI = struct {
    buffers: std.ArrayList(*Buffer),
    allocator: std.mem.Allocator,
    
    pub fn nvim_buf_get_lines(
        self: *BufferAPI,
        bufnr: u32,
        start: i32,
        end: i32,
        strict: bool,
    ) !std.ArrayList([]const u8) {
        const buf = try self.getBuffer(bufnr);
        
        // Convert 0-indexed API indices to buffer indices
        const line_count = buf.lineCount();
        const start_line = if (start < 0) 
            @as(i32, @intCast(line_count)) + start 
        else 
            start;
        const end_line = if (end < 0) 
            @as(i32, @intCast(line_count)) + end 
        else 
            end;
        
        var result = std.ArrayList([]const u8).init(self.allocator);
        
        var i: i32 = start_line;
        while (i < end_line and i < @as(i32, @intCast(line_count))) : (i += 1) {
            if (i >= 0) {
                const line = try buf.getLine(@as(u32, @intCast(i)));
                try result.append(line);
            }
        }
        
        return result;
    }
    
    pub fn nvim_buf_set_lines(
        self: *BufferAPI,
        bufnr: u32,
        start: i32,
        end: i32,
        strict: bool,
        replacement: std.ArrayList([]const u8),
    ) !void {
        const buf = try self.getBuffer(bufnr);
        
        // Similar index normalization as above
        // Replace lines from start to end with replacement
        // Trigger change events
    }
    
    fn getBuffer(self: *BufferAPI, bufnr: u32) !*Buffer {
        if (bufnr == 0) {
            // Current buffer
            return self.buffers.items[self.current_buffer];
        } else if (bufnr > 0 and bufnr <= self.buffers.items.len) {
            return self.buffers.items[bufnr - 1];
        } else {
            return error.InvalidBuffer;
        }
    }
};
```

### Example 5: Hot-Reload Pattern

```zig
// event_loop/reload.zig

const std = @import("std");

pub const ReloadState = struct {
    allocator: std.mem.Allocator,
    config_path: []const u8,
    runtime: ?*HermesRuntime,
    file_watcher: ?FileWatcher,
    
    pub fn init(allocator: std.mem.Allocator, config_path: []const u8) !ReloadState {
        return .{
            .allocator = allocator,
            .config_path = try allocator.dupe(u8, config_path),
            .runtime = null,
            .file_watcher = null,
        };
    }
    
    pub fn setupWatcher(self: *ReloadState) !void {
        self.file_watcher = try FileWatcher.init(self.allocator);
        try self.file_watcher.?.watch(self.config_path, onFileChange);
    }
    
    pub fn reload(self: *ReloadState) !void {
        if (self.runtime) |runtime| {
            // 1. Clear all active timers/intervals
            jsi_api.clearAllTimers(runtime);
            
            // 2. Clear autocommands
            autocommand_manager.clear();
            
            // 3. Re-load configuration
            try jsi_api.loadConfig(runtime, self.config_path, self.allocator);
            
            // 4. Re-apply all settings
            // Trigger "SourcePre" event equivalent
        }
    }
};

fn onFileChange(path: []const u8, context: *anyopaque) void {
    const reload_state = @as(*ReloadState, @ptrCast(@alignCast(context)));
    reload_state.markForReload() catch {};
}
```

---

## Key Takeaways for Vimcraft

### Architectural Principles

1. **Layer Separation**
   - C core handles critical path (rendering, input, buffers)
   - Lua (JavaScript in our case) handles everything else
   - Clear API boundary with type conversion

2. **Metatable Magic**
   - Use JavaScript Proxy objects for `ov.opt.*` style access
   - Enables natural syntax: `ov.opt.number = true`
   - Defers to API calls transparently

3. **Namespace Isolation**
   - Every subsystem (highlights, diagnostics, autocmds) uses namespace IDs
   - Allows multiple systems to coexist peacefully
   - Easy cleanup on reload

4. **Option Handling is Complex**
   - Options have different scopes (global, buffer, window)
   - Options have different types (bool, number, string, array, set, map)
   - Type conversion from Lua to Vim and back

5. **Events Over Callbacks**
   - Use event system for plugin communication
   - Autocommands fire on well-defined events
   - Allows decoupling of systems

### What NOT to Do

1. ❌ Don't expose raw C pointers to JavaScript
   - Use handle-based IDs instead (bufnr, winid, ns_id)

2. ❌ Don't allow synchronous blocking JavaScript
   - All JS execution must yield control back to event loop
   - Use `vim.schedule()` pattern for deferral

3. ❌ Don't implement multiple competing systems for same feature
   - One keymap system, one autocommand system, etc.
   - Namespace them but keep central management

4. ❌ Don't let plugins corrupt editor state
   - Validate all JavaScript calls
   - Catch exceptions and report errors gracefully

5. ❌ Don't forget about backward compatibility
   - Old config files must continue working
   - Deprecate gradually with warnings

### Performance Considerations

1. **Option Access**: Implement caching where possible
   - Options frequently read (`.number`, `.shiftwidth`)
   - Cache with invalidation on set

2. **Highlight Rendering**: Use extmark system
   - Don't redraw entire buffer on each highlight
   - Use namespaces to isolate highlights

3. **Module Loading**: Lazy load heavy modules
   - Don't load LSP/treesitter until needed
   - Mark modules as `_submodules` in init

4. **Type Conversion**: Minimize Zig↔JavaScript marshalling
   - Only convert at API boundaries
   - Keep complex types in native storage

### Quality Assurance

1. **Type Metadata**: Generate from implementation
   - IDEs need type hints for autocomplete
   - `_meta/*.lua` style files for IDE support

2. **Deprecation**: Use consistent warning system
   - Mark old APIs with version when removed
   - Provide migration paths in docs

3. **Testing**: Create test harness
   - Unit tests for each subsystem
   - Integration tests for config loading
   - Regression tests for config files

---

## Conclusion

Neovim's configuration interface represents 15 years of editor evolution. It balances:

- **Simplicity**: Natural Lua syntax (`vim.opt.x = y`)
- **Power**: Full API for advanced users (`vim.api.*`)
- **Flexibility**: Multiple ways to do things (`vim.opt` vs `vim.o`)
- **Performance**: Lazy loading and efficient caching
- **Compatibility**: Vimscript bridge alongside Lua

For Vimcraft, the goal should be to replicate this design in Zig+JavaScript, preserving what works while adapting to different constraints. The Hermes bytecode approach provides an opportunity for even faster startup times than Neovim's Lua 5.1 interpreter.

Key success metrics:
1. Can existing Neovim configs run (with minimal changes)?
2. Can JavaScript developers write plugins intuitively?
3. Does configuration hot-reload work reliably?
4. Are IDE integrations (LSP, diagnostics) possible?
5. Is startup time < 100ms for cold start?

