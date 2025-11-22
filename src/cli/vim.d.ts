// Vimcraft TypeScript Type Definitions
// Version: 0.6.0 - Neovim-Compatible API with CommonJS Module System
// Based on Neovim 0.12.0 API analysis
// Updated: 65 vim.opt options with JavaScript camelCase naming
// Phase 4: CommonJS require(), module.exports, Event Emitter

// ============================================================================
// Type Aliases & Utility Types
// ============================================================================

/** Buffer handle (0 = current buffer, positive integers for specific buffers) */
export type Buffer = number;

/** Window handle (0 = current window, positive integers for specific windows) */
export type Window = number;

/** Tabpage handle (0 = current tabpage, positive integers for specific tabpages) */
export type Tabpage = number;

/** Namespace ID for highlights, extmarks, diagnostics */
export type Namespace = number;

/** Autocommand ID returned by nvim_create_autocmd */
export type AutocmdID = number;

/** User command ID */
export type CommandID = number;

/**
 * RGB color representation
 */
export interface Color {
  r: number;
  g: number;
  b: number;
}

// ============================================================================
// Highlight System
// ============================================================================

/**
 * Highlight group styling options
 */
export interface HighlightOpts {
  /** Background color (hex string like '#ff0000' or null) */
  bg?: string | null;
  /** Foreground color (hex string like '#00ff00' or null) */
  fg?: string | null;
  /** Special color for undercurl/underline */
  sp?: string | null;
  /** Color blend value (0-100) */
  blend?: number;
  /** Bold text */
  bold?: boolean;
  /** Italic text */
  italic?: boolean;
  /** Underlined text */
  underline?: boolean;
  /** Undercurl decoration */
  undercurl?: boolean;
  /** Underdouble decoration */
  underdouble?: boolean;
  /** Underdotted decoration */
  underdotted?: boolean;
  /** Underdashed decoration */
  underdashed?: boolean;
  /** Strikethrough text */
  strikethrough?: boolean;
  /** Reverse/inverse colors */
  reverse?: boolean;
  /** Standout mode */
  standout?: boolean;
  /** Highlight priority (0-10000, default: varies by type) */
  priority?: number;
  /** Link to another highlight group */
  link?: string;
}

/**
 * Common highlight group names (not exhaustive)
 * These are standard Vim/Neovim highlight groups
 */
export type HighlightGroup =
  // === Editor UI ===
  | 'Normal' | 'NormalFloat' | 'NormalNC'
  | 'CursorLine' | 'CursorColumn' | 'ColorColumn'
  | 'LineNr' | 'CursorLineNr' | 'SignColumn'
  | 'FoldColumn' | 'Folded' | 'VertSplit'
  | 'StatusLine' | 'StatusLineNC'
  | 'TabLine' | 'TabLineFill' | 'TabLineSel'
  | 'WinSeparator' | 'WinBar' | 'WinBarNC'
  | 'Pmenu' | 'PmenuSel' | 'PmenuSbar' | 'PmenuThumb'

  // === Syntax Highlighting ===
  | 'Comment' | 'Constant' | 'String' | 'Character'
  | 'Number' | 'Boolean' | 'Float'
  | 'Identifier' | 'Function'
  | 'Statement' | 'Conditional' | 'Repeat' | 'Label' | 'Operator' | 'Keyword' | 'Exception'
  | 'PreProc' | 'Include' | 'Define' | 'Macro' | 'PreCondit'
  | 'Type' | 'StorageClass' | 'Structure' | 'Typedef'
  | 'Special' | 'SpecialChar' | 'Tag' | 'Delimiter' | 'SpecialComment' | 'Debug'
  | 'Underlined' | 'Ignore' | 'Error' | 'Todo'

  // === Diagnostics (LSP) ===
  | 'DiagnosticError' | 'DiagnosticWarn' | 'DiagnosticInfo' | 'DiagnosticHint'
  | 'DiagnosticUnderlineError' | 'DiagnosticUnderlineWarn'
  | 'DiagnosticUnderlineInfo' | 'DiagnosticUnderlineHint'
  | 'DiagnosticSignError' | 'DiagnosticSignWarn' | 'DiagnosticSignInfo' | 'DiagnosticSignHint'

  // === Search ===
  | 'Search' | 'IncSearch' | 'CurSearch' | 'Substitute'

  // === Diff ===
  | 'DiffAdd' | 'DiffChange' | 'DiffDelete' | 'DiffText'

  // === Misc ===
  | 'Visual' | 'VisualNOS' | 'MatchParen' | 'Conceal'
  | 'Directory' | 'Title' | 'Question' | 'MoreMsg' | 'ModeMsg'
  | 'NonText' | 'SpecialKey' | 'Whitespace' | 'EndOfBuffer'

  // Allow any string for custom highlight groups
  | string;

// ============================================================================
// Editor Options
// ============================================================================

/**
 * Status line display mode (vim.opt.lastStatus)
 * Controls when the status line is shown
 *
 * @example
 * vim.opt.lastStatus = LastStatus.Never;  // Hide status line
 * vim.opt.lastStatus = LastStatus.Always; // Always show (default)
 */
export enum LastStatus {
  /** Never show status line (laststatus=0) */
  Never = 0,
  /** Only if there are multiple windows (laststatus=1, currently behaves like Always) */
  OnlyIfMultipleWindows = 1,
  /** Always show status line (laststatus=2, default) */
  Always = 2,
  /** Global status line - always show only in last window (laststatus=3, currently behaves like Always) */
  Global = 3,
}

/**
 * Editor options (vim.opt)
 * All option names use camelCase for JavaScript/TypeScript convention
 */
export interface VimOptions {
  // === Display Options ===
  number?: boolean;
  relativeNumber?: boolean;
  cursorLine?: boolean;
  cursorColumn?: boolean;
  signColumn?: 'yes' | 'no' | 'auto' | 'number';
  colorColumn?: string;
  scrollOff?: number;
  sideScrollOff?: number;
  lastStatus?: LastStatus | 0 | 1 | 2 | 3;
  showCmd?: boolean;
  showMode?: boolean;
  ruler?: boolean;
  wrap?: boolean;
  lineBreak?: boolean;
  list?: boolean;
  listChars?: string;
  concealLevel?: 0 | 1 | 2 | 3;
  spell?: boolean;
  foldColumn?: string;
  termGuiColors?: boolean;
  background?: 'light' | 'dark';
  showMatch?: boolean;

  // === Editing Options ===
  tabStop?: number;
  shiftWidth?: number;
  expandTab?: boolean;
  smartIndent?: boolean;
  autoIndent?: boolean;
  textWidth?: number;
  softTabStop?: number;
  smartTab?: boolean;
  backspace?: string;
  formatOptions?: string;
  completeOpt?: string;
  virtualEdit?: string;
  modifiable?: boolean;
  readOnly?: boolean;

  // === Search Options ===
  ignoreCase?: boolean;
  smartCase?: boolean;
  hlSearch?: boolean;
  incSearch?: boolean;
  wrapScan?: boolean;

  // === Behavior Options ===
  mouse?: string;
  clipboard?: string;
  undoLevels?: number;
  timeout?: boolean;
  timeoutLen?: number;
  updateTime?: number;
  hidden?: boolean;
  backup?: boolean;
  writeBackup?: boolean;
  swapFile?: boolean;
  undoFile?: boolean;
  undoDir?: string;
  splitRight?: boolean;
  splitBelow?: boolean;
  autoRead?: boolean;
  autoWrite?: boolean;
  confirm?: boolean;

  // === UI Options ===
  cmdHeight?: number;
  pumHeight?: number;
  winBlend?: number;
  pumBlend?: number;
  showTabLine?: 0 | 1 | 2;
  wildMenu?: boolean;
  wildMode?: string;
}

// ============================================================================
// Keymap System
// ============================================================================

/**
 * Key mapping modes
 */
export type MapMode =
  | 'n'   // Normal mode
  | 'i'   // Insert mode
  | 'v'   // Visual mode
  | 'x'   // Visual block mode
  | 's'   // Select mode
  | 'o'   // Operator-pending mode
  | 'c'   // Command-line mode
  | 't'   // Terminal mode
  | ''    // All modes
  | string;

/**
 * Key mapping options
 */
export interface KeymapOpts {
  /** Don't use default mappings */
  noremap?: boolean;
  /** Silent mapping (don't echo) */
  silent?: boolean;
  /** Expression mapping (evaluated) */
  expr?: boolean;
  /** Unique mapping (error if already exists) */
  unique?: boolean;
  /** Buffer number (0 = current, true = current) */
  buffer?: boolean | number;
  /** Nowait for this mapping */
  nowait?: boolean;
  /** Script-local remapping */
  script?: boolean;
  /** Replace keycodes */
  replace_keycodes?: boolean;
  /** Description of the mapping (for which-key, etc.) */
  desc?: string;
  /** Callback function instead of rhs string */
  callback?: () => void;
}

/**
 * Keymap interface (vim.keymap)
 */
export interface Keymap {
  /**
   * Set a key mapping
   * @param mode - Mode(s) where mapping applies
   * @param lhs - Left-hand side (key to map)
   * @param rhs - Right-hand side (action, keys, or callback)
   * @param opts - Mapping options
   *
   * @example
   * vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
   * vim.keymap.set('i', 'jk', '<Esc>', { noremap: true });
   * vim.keymap.set('n', '<leader>d', () => { console.log('delete'); });
   */
  set(mode: MapMode | MapMode[], lhs: string, rhs: string | (() => void), opts?: KeymapOpts): void;

  /**
   * Delete a key mapping
   * @param mode - Mode(s) where mapping exists
   * @param lhs - Left-hand side (key to delete)
   * @param opts - Options (currently only buffer)
   *
   * @example
   * vim.keymap.del('n', '<leader>w');
   * vim.keymap.del('i', 'jk', { buffer: true });
   */
  del(mode: MapMode | MapMode[], lhs: string, opts?: { buffer?: boolean | number }): void;
}

// ============================================================================
// Autocommands & Events
// ============================================================================

/**
 * Autocommand events
 */
export type AutocmdEvent =
  // File events
  | 'BufAdd' | 'BufDelete' | 'BufEnter' | 'BufFilePost' | 'BufFilePre'
  | 'BufHidden' | 'BufLeave' | 'BufNew' | 'BufNewFile'
  | 'BufRead' | 'BufReadPost' | 'BufReadPre' | 'BufReadCmd'
  | 'BufUnload' | 'BufWinEnter' | 'BufWinLeave'
  | 'BufWrite' | 'BufWritePre' | 'BufWritePost' | 'BufWriteCmd'
  | 'FileType' | 'FileChangedShell' | 'FileChangedShellPost'
  | 'FileReadPre' | 'FileReadPost' | 'FileWritePre' | 'FileWritePost'

  // Window/UI events
  | 'WinEnter' | 'WinLeave' | 'WinNew' | 'WinClosed'
  | 'TabEnter' | 'TabLeave' | 'TabNew' | 'TabClosed'
  | 'CmdwinEnter' | 'CmdwinLeave'

  // Mode events
  | 'InsertEnter' | 'InsertLeave' | 'InsertChange'
  | 'ModeChanged'
  | 'CmdlineEnter' | 'CmdlineLeave' | 'CmdlineChanged'

  // Text change events
  | 'TextChanged' | 'TextChangedI' | 'TextChangedP' | 'TextYankPost'

  // Cursor events
  | 'CursorMoved' | 'CursorMovedI' | 'CursorHold' | 'CursorHoldI'

  // Startup/shutdown
  | 'VimEnter' | 'VimLeave' | 'VimLeavePre' | 'VimResume' | 'VimSuspend'

  // LSP events
  | 'LspAttach' | 'LspDetach' | 'LspTokenUpdate'

  // Misc events
  | 'ColorScheme' | 'OptionSet' | 'User' | 'FocusGained' | 'FocusLost'
  | string;

/**
 * Autocommand callback arguments
 * Matches Neovim's autocmd callback args structure exactly
 */
export interface AutocmdCallbackArgs {
  /** Autocommand ID */
  id: number;
  /** Event name that triggered the autocommand */
  event: string;
  /** Augroup ID (null if not in a group) */
  group: number | null;
  /** Pattern that matched (currently same as file) */
  match: string;
  /** Buffer number */
  buf: number;
  /** File name (empty string if no file) */
  file: string;
  /** Additional event-specific data (null if none) */
  data: any;
}

/**
 * Autocommand options
 */
export interface AutocmdOpts {
  /** Augroup name or ID */
  group?: string | number;
  /** File pattern(s) to match */
  pattern?: string | string[];
  /** Buffer number (0 = current) */
  buffer?: number;
  /** Callback function */
  callback?: (args: AutocmdCallbackArgs) => void | boolean;
  /** Vim command string (alternative to callback) */
  command?: string;
  /** Description */
  desc?: string;
  /** Run once then delete */
  once?: boolean;
  /** Nested autocommands allowed */
  nested?: boolean;
}

/**
 * Augroup options
 */
export interface AugroupOpts {
  /** Clear existing autocommands in group */
  clear?: boolean;
}

// ============================================================================
// User Commands
// ============================================================================

/**
 * User command attributes
 */
export interface UserCommandOpts {
  /** Number of arguments ('0', '1', '*', '?', '+') */
  nargs?: '0' | '1' | '*' | '?' | '+' | number;
  /** Completion type */
  complete?: 'file' | 'dir' | 'buffer' | 'custom' | string;
  /** Custom completion function */
  complete_function?: (arg_lead: string, cmd_line: string, cursor_pos: number) => string[];
  /** Range allowed */
  range?: boolean | '%' | number;
  /** Count allowed */
  count?: boolean | number;
  /** Buffer-local command */
  buffer?: boolean | number;
  /** Bang allowed */
  bang?: boolean;
  /** Bar allowed */
  bar?: boolean;
  /** Register allowed */
  register?: boolean;
  /** Force replacement */
  force?: boolean;
  /** Description */
  desc?: string;
}

/**
 * User command callback arguments
 */
export interface UserCommandCallbackArgs {
  /** Command name */
  name: string;
  /** Command arguments string */
  args: string;
  /** Arguments array (split by whitespace) */
  fargs: string[];
  /** Bang (!) was used */
  bang: boolean;
  /** Line range */
  line1: number;
  line2: number;
  /** Range was specified */
  range: number;
  /** Count was specified */
  count: number;
  /** Register name (if any) */
  reg: string;
  /** Modifiers string */
  mods: string;
  /** Smods table (parsed modifiers) */
  smods: Record<string, any>;
}

// ============================================================================
// Diagnostic System
// ============================================================================

/**
 * Diagnostic severity levels
 */
export enum DiagnosticSeverity {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  HINT = 4,
}

/**
 * Diagnostic structure
 */
export interface Diagnostic {
  /** Buffer number */
  bufnr?: number;
  /** Line number (0-indexed) */
  lnum: number;
  /** End line number (0-indexed, optional) */
  end_lnum?: number;
  /** Column number (0-indexed) */
  col: number;
  /** End column number (0-indexed, optional) */
  end_col?: number;
  /** Severity level */
  severity: DiagnosticSeverity | number;
  /** Diagnostic message */
  message: string;
  /** Source of diagnostic (e.g., 'eslint', 'typescript') */
  source?: string;
  /** Error code */
  code?: string | number;
  /** User data */
  user_data?: any;
}

/**
 * Diagnostic configuration
 */
export interface DiagnosticConfig {
  /** Underline diagnostics */
  underline?: boolean;
  /** Virtual text configuration */
  virtual_text?: boolean | {
    spacing?: number;
    prefix?: string;
    source?: boolean | 'always' | 'if_many';
    format?: (diagnostic: Diagnostic) => string;
  };
  /** Signs in sign column */
  signs?: boolean | {
    text?: Record<string, string>;
    priority?: number;
  };
  /** Update diagnostics in insert mode */
  update_in_insert?: boolean;
  /** Severity sort order */
  severity_sort?: boolean | {
    reverse?: boolean;
  };
  /** Float window configuration */
  float?: boolean | {
    source?: boolean | 'always' | 'if_many';
    border?: string;
    header?: string;
    prefix?: string | ((diagnostic: Diagnostic, i: number, total: number) => string);
  };
}

/**
 * Diagnostic interface (vim.diagnostic)
 */
export interface DiagnosticAPI {
  /**
   * Set diagnostics for a namespace
   */
  set(namespace: Namespace, bufnr: Buffer, diagnostics: Diagnostic[], opts?: any): void;

  /**
   * Get diagnostics
   */
  get(bufnr?: Buffer, opts?: { namespace?: Namespace; lnum?: number; severity?: DiagnosticSeverity }): Diagnostic[];

  /**
   * Configure diagnostics
   */
  config(opts: DiagnosticConfig, namespace?: Namespace): void;

  /**
   * Show diagnostics in floating window
   */
  open_float(opts?: any): void;

  /**
   * Jump to next diagnostic
   */
  goto_next(opts?: any): void;

  /**
   * Jump to previous diagnostic
   */
  goto_prev(opts?: any): void;

  /**
   * Enable diagnostics
   */
  enable(bufnr?: Buffer, namespace?: Namespace): void;

  /**
   * Disable diagnostics
   */
  disable(bufnr?: Buffer, namespace?: Namespace): void;
}

// ============================================================================
// Core API (vim.api.nvim_*)
// ============================================================================

/**
 * Core Neovim API interface (vim.api)
 * Contains all nvim_* functions
 */
export interface API {
  // === Buffer Functions ===

  /** Get current buffer */
  nvim_get_current_buf(): Buffer;

  /** Set current buffer */
  nvim_set_current_buf(buffer: Buffer): void;

  /** Get buffer lines */
  nvim_buf_get_lines(buffer: Buffer, start: number, end: number, strict_indexing: boolean): string[];

  /** Set buffer lines */
  nvim_buf_set_lines(buffer: Buffer, start: number, end: number, strict_indexing: boolean, replacement: string[]): void;

  /** Get buffer line count */
  nvim_buf_line_count(buffer: Buffer): number;

  /** Get buffer name */
  nvim_buf_get_name(buffer: Buffer): string;

  /** Set buffer name */
  nvim_buf_set_name(buffer: Buffer, name: string): void;

  /** Check if buffer is valid */
  nvim_buf_is_valid(buffer: Buffer): boolean;

  /** Delete buffer */
  nvim_buf_delete(buffer: Buffer, opts: { force?: boolean; unload?: boolean }): void;

  // === Window Functions ===

  /** Get current window */
  nvim_get_current_win(): Window;

  /** Set current window */
  nvim_set_current_win(window: Window): void;

  /** Get window buffer */
  nvim_win_get_buf(window: Window): Buffer;

  /** Set window buffer */
  nvim_win_set_buf(window: Window, buffer: Buffer): void;

  /** Get window cursor position [row, col] (1-indexed, 0-indexed) */
  nvim_win_get_cursor(window: Window): [number, number];

  /** Set window cursor position [row, col] (1-indexed, 0-indexed) */
  nvim_win_set_cursor(window: Window, pos: [number, number]): void;

  /** Get window height */
  nvim_win_get_height(window: Window): number;

  /** Set window height */
  nvim_win_set_height(window: Window, height: number): void;

  /** Get window width */
  nvim_win_get_width(window: Window): number;

  /** Set window width */
  nvim_win_set_width(window: Window, width: number): void;

  /** Check if window is valid */
  nvim_win_is_valid(window: Window): boolean;

  /** Close window */
  nvim_win_close(window: Window, force: boolean): void;

  // === Tabpage Functions ===

  /** Get current tabpage */
  nvim_get_current_tabpage(): Tabpage;

  /** Set current tabpage */
  nvim_set_current_tabpage(tabpage: Tabpage): void;

  /** List all tabpages */
  nvim_list_tabpages(): Tabpage[];

  // === Option Functions ===

  /** Get option value */
  nvim_get_option(name: string): any;

  /** Set option value */
  nvim_set_option(name: string, value: any): void;

  /** Get buffer option value */
  nvim_buf_get_option(buffer: Buffer, name: string): any;

  /** Set buffer option value */
  nvim_buf_set_option(buffer: Buffer, name: string, value: any): void;

  /** Get window option value */
  nvim_win_get_option(window: Window, name: string): any;

  /** Set window option value */
  nvim_win_set_option(window: Window, name: string, value: any): void;

  // === Variable Functions ===

  /** Get global variable */
  nvim_get_var(name: string): any;

  /** Set global variable */
  nvim_set_var(name: string, value: any): void;

  /** Delete global variable */
  nvim_del_var(name: string): void;

  /** Get buffer variable */
  nvim_buf_get_var(buffer: Buffer, name: string): any;

  /** Set buffer variable */
  nvim_buf_set_var(buffer: Buffer, name: string, value: any): void;

  // === Keymap Functions ===

  /** Set global keymap */
  nvim_set_keymap(mode: string, lhs: string, rhs: string, opts: any): void;

  /** Delete global keymap */
  nvim_del_keymap(mode: string, lhs: string): void;

  /** Get keymaps */
  nvim_get_keymap(mode: string): any[];

  /** Set buffer keymap */
  nvim_buf_set_keymap(buffer: Buffer, mode: string, lhs: string, rhs: string, opts: any): void;

  /** Delete buffer keymap */
  nvim_buf_del_keymap(buffer: Buffer, mode: string, lhs: string): void;

  // === Highlight Functions ===

  /** Set highlight group */
  nvim_set_hl(namespace: Namespace, name: string, val: HighlightOpts): void;

  /** Get highlight group */
  nvim_get_hl(namespace: Namespace, opts: { name?: string; id?: number; link?: boolean }): Record<string, any>;

  /** Set buffer highlight (extmark-based) */
  nvim_buf_add_highlight(buffer: Buffer, ns_id: Namespace, hl_group: string, line: number, col_start: number, col_end: number): number;

  /** Clear namespace highlights */
  nvim_buf_clear_namespace(buffer: Buffer, ns_id: Namespace, line_start: number, line_end: number): void;

  // === Autocommand Functions ===

  /** Create autocommand */
  nvim_create_autocmd(event: AutocmdEvent | AutocmdEvent[], opts: AutocmdOpts): AutocmdID;

  /** Delete autocommand by ID */
  nvim_del_autocmd(id: AutocmdID): void;

  /** Create augroup */
  nvim_create_augroup(name: string, opts: AugroupOpts): number;

  /** Clear autocmds in augroup */
  nvim_clear_autocmds(opts: { group?: string | number; event?: string | string[]; buffer?: number }): void;

  // === User Command Functions ===

  /** Create user command */
  nvim_create_user_command(name: string, command: string | ((args: UserCommandCallbackArgs) => void), opts: UserCommandOpts): void;

  /** Delete user command */
  nvim_del_user_command(name: string): void;

  /** Create buffer-local user command */
  nvim_buf_create_user_command(buffer: Buffer, name: string, command: string | ((args: UserCommandCallbackArgs) => void), opts: UserCommandOpts): void;

  /** Delete buffer-local user command */
  nvim_buf_del_user_command(buffer: Buffer, name: string): void;

  // === Command Execution ===

  /** Execute Ex command */
  nvim_command(command: string): void;

  /** Execute Lua code */
  nvim_exec_lua(code: string, args: any[]): any;

  // === Namespace Functions ===

  /** Create namespace */
  nvim_create_namespace(name: string): Namespace;

  /** Get namespaces */
  nvim_get_namespaces(): Record<string, Namespace>;

  // === Misc Functions ===

  /** Call Vimscript function */
  nvim_call_function(fname: string, args: any[]): any;

  /** Evaluate Vimscript expression */
  nvim_eval(expr: string): any;

  /** Get mode */
  nvim_get_mode(): { mode: string; blocking: boolean };

  /** Notify user */
  nvim_notify(msg: string, log_level: number, opts: any): void;

  /** Echo message */
  nvim_echo(chunks: Array<[string, string?]>, history: boolean, opts: any): void;

  /** Get runtime files */
  nvim_get_runtime_file(name: string, all: boolean): string[];
}

// ============================================================================
// Function Bridge (vim.fn)
// ============================================================================

/**
 * Vimscript function bridge (vim.fn)
 * Allows calling built-in Vimscript functions
 */
export interface VimFunctions {
  /** Expand wildcards and special keywords */
  expand(expr: string): string;

  /** Get character at cursor */
  getchar(): number;

  /** Get character from position */
  getcharpos(expr: string): [number, number, number, number];

  /** Check if file exists */
  filereadable(file: string): boolean;

  /** Get file type */
  getftype(fname: string): string;

  /** Simplify file path */
  simplify(path: string): string;

  /** Join path components */
  join(list: string[], sep: string): string;

  /** Split string */
  split(string: string, pattern: string): string[];

  // Allow calling any function by name
  [key: string]: (...args: any[]) => any;
}

// ============================================================================
// Runtime APIs (Global)
// ============================================================================

/**
 * File system API (Node.js-style, async-first)
 * @future Phase 5+
 */
export interface FileSystem {
  readFile(path: string): Promise<ArrayBuffer>;
  readTextFile(path: string): Promise<string>;
  writeFile(path: string, data: string | ArrayBuffer): Promise<void>;
  stat(path: string): Promise<{
    size: number;
    mtime: Date;
    isDirectory: boolean;
    isFile: boolean;
  }>;
  exists(path: string): Promise<boolean>;
  readDir(path: string): Promise<string[]>;
  watch(path: string, callback: (event: 'create' | 'modify' | 'delete', filename: string) => void): {
    close(): void;
  };
}

/**
 * HTTP Response interface (Browser-compatible)
 */
export interface FetchResponse {
  ok: boolean;
  status: number;
  statusText: string;
  headers: {
    get(name: string): string | null;
  };
  text(): Promise<string>;
  json(): Promise<any>;
  arrayBuffer(): Promise<ArrayBuffer>;
}

/**
 * Process API (Node.js-style)
 * @future Phase 5+
 */
export interface Process {
  cwd(): string;
  env: Record<string, string>;
  platform: 'darwin' | 'linux' | 'windows';
  spawn(command: string, args?: string[], options?: {
    cwd?: string;
    env?: Record<string, string>;
  }): Promise<{
    stdout: string;
    stderr: string;
    code: number;
  }>;
}

// ============================================================================
// LSP - Future
// ============================================================================

/**
 * LSP client interface (vim.lsp)
 * FUTURE: Phase 5+
 */
export interface LSP {
  // Placeholder for future implementation
  [key: string]: any;
}

// ============================================================================
// TreeSitter - Future
// ============================================================================

/**
 * Tree-sitter interface (vim.treesitter)
 * FUTURE: Phase 5+
 */
export interface TreeSitter {
  // Placeholder for future implementation
  [key: string]: any;
}

// ============================================================================
// Main Vim Interface
// ============================================================================

/**
 * Main vim global interface
 * Entry point for all Vimcraft configuration and API access
 */
export interface Vim {
  /**
   * Core API (nvim_* functions)
   * Full Neovim-compatible API
   */
  api: API;

  /**
   * Editor options
   * @example
   * vim.opt.cursorLine = true;
   * vim.opt.number = true;
   */
  opt: VimOptions;

  /**
   * Buffer-local options (Neovim equivalent: vim.opt_local)
   * @example
   * vim.optLocal.number = true;
   */
  optLocal?: VimOptions;

  /**
   * Global options (Neovim equivalent: vim.opt_global)
   * @example
   * vim.optGlobal.cursorLine = true;
   */
  optGlobal?: VimOptions;

  /**
   * Key mapping interface
   * @example
   * vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
   */
  keymap: Keymap;

  /**
   * Register event listener for autocommand events
   * Callback receives Neovim-compatible args object
   * @param event - Event name (e.g., 'BufRead', 'InsertEnter')
   * @param callback - Callback function that receives event args
   * @example
   * vim.on('BufWritePre', (args) => {
   *   console.log('Saving file:', args.file);
   *   console.log('Buffer:', args.buf, 'Event:', args.event);
   * });
   */
  on(event: AutocmdEvent, callback: (args: AutocmdCallbackArgs) => void): void;

  /**
   * Remove event listener for autocommand events
   * Currently removes ALL listeners for the event
   * @param event - Event name
   * @param callback - Callback to remove (currently unused, removes all)
   * @example
   * vim.off('BufWritePre', callback);
   */
  off(event: AutocmdEvent, callback: (args: AutocmdCallbackArgs) => void): void;

  /**
   * Remove all listeners for an event
   * @param event - Event name
   * @example
   * vim.removeAllListeners('BufWritePre');
   */
  removeAllListeners(event: AutocmdEvent): void;

  /**
   * Get listener count for an event
   * @param event - Event name
   * @returns Number of listeners
   * @example
   * const count = vim.listenerCount('BufWritePre');
   */
  listenerCount(event: AutocmdEvent): number;

  /**
   * Emit an event (for testing/advanced use)
   * @param event - Event name
   * @param args - Event arguments
   * @example
   * vim.emit('User', { event: 'MyCustomEvent', data: {...} });
   */
  emit(event: AutocmdEvent, args: AutocmdCallbackArgs): void;

  /**
   * Vimscript function bridge
   * @example
   * const path = vim.fn.expand('%:p');
   */
  fn: VimFunctions;

  /**
   * Diagnostic system
   */
  diagnostic: DiagnosticAPI;

  // Note: vim.loop is not needed - use global fs, fetch, process instead

  /**
   * LSP client
   * FUTURE: Phase 5+
   */
  lsp?: LSP;

  /**
   * Tree-sitter integration
   * FUTURE: Phase 5+
   */
  treesitter?: TreeSitter;

  /**
   * Execute Ex command
   * @param cmd - Command to execute
   * @example
   * vim.cmd('set number');
   */
  cmd(cmd: string): void;

  /**
   * Define syntax highlighting for a group
   * Ergonomic wrapper for vim.api.nvim_set_hl
   * @param name - Highlight group name
   * @param opts - Styling options
   * @example
   * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
   */
  highlight(name: HighlightGroup, opts: HighlightOpts): void;

  /**
   * Create namespace
   * @param name - Namespace name
   * @returns Namespace ID
   */
  create_namespace?(name: string): Namespace;

  /**
   * Schedule function to run later
   * @param fn - Function to schedule
   */
  schedule?(fn: () => void): void;

  // Note: vim.defer_fn is not needed - use standard setTimeout() instead

  // === Variable Scopes ===

  /**
   * Global variables (g:)
   * @example
   * vim.g.mapleader = ' ';
   */
  g: Record<string, any>;

  /**
   * Buffer-local variables (b:)
   * @example
   * vim.b.my_var = 42;
   */
  b: Record<string, any>;

  /**
   * Buffer-local options (bo:)
   * Neovim equivalent: vim.bo
   * @example
   * vim.bo.filetype = 'rust';
   * const ft = vim.bo.filetype; // Get filetype
   */
  bo: {
    /** Detected filetype (e.g., 'rust', 'javascript', 'python') */
    filetype?: string;
    // More buffer options can be added here in the future
    [key: string]: any;
  };

  /**
   * Window-local variables (w:)
   */
  w: Record<string, any>;

  /**
   * Tabpage-local variables (t:)
   */
  t: Record<string, any>;

  /**
   * Vim variables (v:) - mostly read-only
   */
  v: Record<string, any>;

  /**
   * Environment variables
   * @example
   * const home = vim.env.HOME;
   */
  env: Record<string, string>;
}

// ============================================================================
// Console Interface
// ============================================================================

/**
 * Console interface for debugging
 */
export interface Console {
  /**
   * Log messages to Chrome DevTools console
   * Supports multiple arguments of any type
   */
  log(...args: any[]): void;

  /**
   * Log error messages
   */
  error(...args: any[]): void;

  /**
   * Log warning messages
   */
  warn(...args: any[]): void;

  /**
   * Log info messages
   */
  info(...args: any[]): void;
}

// ============================================================================
// CommonJS Module System
// ============================================================================

/**
 * CommonJS module object
 * Contains the module's exports and metadata
 */
export interface Module {
  /**
   * Module exports (what require() returns)
   * Can be assigned directly: module.exports = {...}
   * Or augmented: module.exports.foo = bar
   */
  exports: any;

  /**
   * Module identifier (absolute path)
   * @readonly
   */
  id?: string;

  /**
   * Module filename (absolute path)
   * @readonly
   */
  filename?: string;

  /**
   * Whether module is loaded
   * @readonly
   */
  loaded?: boolean;

  /**
   * Parent module that required this module
   * @readonly
   */
  parent?: Module | null;

  /**
   * Modules required by this module
   * @readonly
   */
  children?: Module[];
}

// ============================================================================
// Global Declarations
// ============================================================================

declare global {
  /**
   * Global vim object - main API for configuring Vimcraft
   * Neovim-compatible interface
   */
  var vim: Vim;

  /**
   * Status line display mode constants
   * Use with vim.opt.laststatus
   * @example
   * vim.opt.laststatus = LastStatus.Never;  // Hide status line
   * vim.opt.laststatus = LastStatus.Always; // Always show (default)
   */
  var LastStatus: {
    /** Never show status line (laststatus=0) */
    readonly Never: 0;
    /** Only if there are multiple windows (laststatus=1) */
    readonly OnlyIfMultipleWindows: 1;
    /** Always show status line (laststatus=2, default) */
    readonly Always: 2;
    /** Global status line - always show only in last window (laststatus=3) */
    readonly Global: 3;
  };

  /**
   * Global console object - for debugging via Chrome DevTools
   */
  var console: Console;

  /**
   * CommonJS module object
   * Set module.exports to export values from your plugin
   *
   * @example
   * // Export an object with functions
   * module.exports = {
   *   setup: function() { ... },
   *   doSomething: function() { ... }
   * };
   *
   * @example
   * // Export a single function
   * module.exports = function myPlugin() { ... };
   */
  var module: Module;

  /**
   * CommonJS exports object (alias to module.exports)
   * You can augment it: exports.foo = bar
   * Or reassign module.exports: module.exports = {...}
   *
   * Note: Reassigning exports itself (exports = {...}) won't work!
   * Always use module.exports for full replacement.
   *
   * @example
   * // This works (augment)
   * exports.greet = function(name) { return 'Hello, ' + name; };
   *
   * @example
   * // This works (replace via module.exports)
   * module.exports = { greet: function(name) { ... } };
   *
   * @example
   * // This DOESN'T work (reassigning exports)
   * exports = { greet: function(name) { ... } }; // ❌ Wrong!
   */
  var exports: any;

  /**
   * CommonJS require function
   * Loads and executes a JavaScript module, returning its exports
   *
   * Supports 3 resolution modes:
   * 1. Relative paths: require('./utils.js') or require('../shared.js')
   * 2. Absolute paths: require('/abs/path/to/module.js')
   * 3. Plugin names: require('telescope') → searches plugin directories
   *
   * Plugin name resolution searches:
   * - ~/.config/vimcraft/plugins/<name>.js
   * - ~/.config/vimcraft/plugins/<name>/init.js
   * - ~/.local/share/vimcraft/plugins/<name>.js
   * - ~/.local/share/vimcraft/plugins/<name>/init.js
   *
   * Module caching:
   * - Modules are cached by absolute path after first load
   * - Second require() returns the cached exports (same object reference)
   * - Circular dependencies are detected and return undefined
   *
   * @param path - Module path (relative, absolute, or plugin name)
   * @returns The module's exports (whatever was assigned to module.exports)
   *
   * @example
   * // Require a plugin by name
   * const telescope = require('telescope');
   * telescope.setup();
   *
   * @example
   * // Require a local utility module
   * const utils = require('./utils.js');
   * utils.greet('Vimcraft');
   *
   * @example
   * // Require with absolute path
   * const plugin = require('/Users/me/.config/vimcraft/plugins/my-plugin.js');
   *
   * @example
   * // Module caching demonstration
   * const mod1 = require('./my-module.js');
   * const mod2 = require('./my-module.js');
   * console.log(mod1 === mod2); // true (same object)
   */
  function require(path: string): any;

  /**
   * Schedule a function to run after a delay
   */
  function setTimeout(callback: () => void, delay?: number): number;

  /**
   * Schedule a function to run repeatedly at intervals
   */
  function setInterval(callback: () => void, delay?: number): number;

  /**
   * Cancel a timeout created by setTimeout
   */
  function clearTimeout(id: number): void;

  /**
   * Cancel an interval created by setInterval
   */
  function clearInterval(id: number): void;

  // ============================================
  // Runtime APIs (Node.js/Browser-compatible)
  // ============================================

  /**
   * File system API (Node.js-style, async-first)
   * @future Phase 5+
   */
  var fs: FileSystem;

  /**
   * HTTP fetch API (Browser-compatible)
   * @future Phase 5+ (LSP)
   */
  function fetch(url: string, options?: {
    method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
    headers?: Record<string, string>;
    body?: string | ArrayBuffer;
  }): Promise<FetchResponse>;

  /**
   * Process API (Node.js-style)
   * @future Phase 5+
   */
  var process: Process;
}

export {};
