// OpenVim TypeScript Type Definitions
// Version: 0.1.0

/**
 * RGB color representation
 */
export interface Color {
  r: number;
  g: number;
  b: number;
}

/**
 * Highlight group styling options
 */
export interface HighlightOpts {
  /** Background color (hex string like '#ff0000' or null) */
  bg?: string | null;
  /** Foreground color (hex string like '#00ff00' or null) */
  fg?: string | null;
  /** Special color for UI elements */
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
}

/**
 * Editor options (vim.opt)
 * All option names use camelCase
 */
export interface VimOptions {
  // === Display Options ===

  /** Show line numbers */
  number?: boolean;
  /** Show relative line numbers */
  relativeNumber?: boolean;
  /** Highlight the screen line of the cursor */
  cursorLine?: boolean;
  /** Highlight the screen column of the cursor */
  cursorColumn?: boolean;
  /** Show sign column (for diagnostics, git, etc.) */
  signColumn?: 'yes' | 'no' | 'auto' | 'number';
  /** Color column at specific positions */
  colorColumn?: string;
  /** Number of columns to scroll horizontally */
  scrollOff?: number;
  /** Number of columns to keep to the left and right of the cursor */
  sidescrollOff?: number;
  /** Always show the status line */
  lastStatus?: 0 | 1 | 2 | 3;
  /** Show command in the last line */
  showCmd?: boolean;
  /** Show current mode in command line */
  showMode?: boolean;
  /** Wrap long lines */
  wrap?: boolean;
  /** Line break at word boundaries */
  lineBreak?: boolean;

  // === Indentation Options ===

  /** Number of spaces a <Tab> counts for */
  tabStop?: number;
  /** Number of spaces for each indent step */
  shiftWidth?: number;
  /** Use spaces instead of tabs */
  expandTab?: boolean;
  /** Smart autoindenting */
  smartIndent?: boolean;
  /** Copy indent from current line when starting a new line */
  autoIndent?: boolean;

  // === Search Options ===

  /** Ignore case in search patterns */
  ignoreCase?: boolean;
  /** Override ignoreCase if pattern contains uppercase */
  smartCase?: boolean;
  /** Highlight all matches of search pattern */
  hlSearch?: boolean;
  /** Show search matches as you type */
  incSearch?: boolean;

  // === Edit Options ===

  /** Enable mouse support */
  mouse?: 'a' | 'n' | 'v' | 'i' | 'c' | '';
  /** Time in ms to wait for a mapped sequence */
  timeoutLen?: number;
  /** Allow backspacing over everything in insert mode */
  backspace?: string;
  /** Characters that form pairs */
  matchPairs?: string;

  // === Window Options ===

  /** Splitting a window will put the new window below */
  splitBelow?: boolean;
  /** Splitting a window will put the new window right */
  splitRight?: boolean;

  // === File Options ===

  /** Automatically read file when changed outside of vim */
  autoRead?: boolean;
  /** Automatically write file when moving to another buffer */
  autoWrite?: boolean;
  /** File encoding */
  fileEncoding?: string;

  // === Completion Options ===

  /** Enable command-line completion */
  wildMenu?: boolean;
  /** Completion mode for wildmenu */
  wildMode?: string;
  /** Completion options */
  completeOpt?: string;

  // === Performance Options ===

  /** Faster scrolling */
  lazyRedraw?: boolean;
  /** Time in ms to wait before triggering events */
  updateTime?: number;
}

/**
 * Common highlight group names (not exhaustive)
 * These are standard Vim/Neovim highlight groups
 */
export type HighlightGroup =
  // === Editor UI ===
  | 'Normal'          // Normal text
  | 'NormalFloat'     // Normal text in floating windows
  | 'NormalNC'        // Normal text in non-current windows
  | 'CursorLine'      // Screen line of the cursor
  | 'CursorColumn'    // Screen column of the cursor
  | 'ColorColumn'     // Color column
  | 'LineNr'          // Line number
  | 'CursorLineNr'    // Line number for cursor line
  | 'SignColumn'      // Column where signs are displayed
  | 'FoldColumn'      // Fold column
  | 'Folded'          // Line used for closed folds
  | 'VertSplit'       // Vertical split separator
  | 'StatusLine'      // Status line of current window
  | 'StatusLineNC'    // Status line of non-current windows
  | 'TabLine'         // Tab pages line
  | 'TabLineFill'     // Tab pages line filler
  | 'TabLineSel'      // Tab pages line selected tab
  | 'WinSeparator'    // Window separator
  | 'Pmenu'           // Popup menu
  | 'PmenuSel'        // Popup menu selected item
  | 'PmenuSbar'       // Popup menu scrollbar
  | 'PmenuThumb'      // Popup menu scrollbar thumb

  // === Syntax Highlighting ===
  | 'Comment'         // Comments
  | 'Constant'        // Constants
  | 'String'          // String constants
  | 'Character'       // Character constants
  | 'Number'          // Number constants
  | 'Boolean'         // Boolean constants
  | 'Float'           // Floating point constants
  | 'Identifier'      // Variable names
  | 'Function'        // Function names
  | 'Statement'       // Statements
  | 'Conditional'     // if, then, else, etc.
  | 'Repeat'          // for, while, etc.
  | 'Label'           // Labels
  | 'Operator'        // Operators
  | 'Keyword'         // Keywords
  | 'Exception'       // try, catch, throw
  | 'PreProc'         // Preprocessor
  | 'Include'         // Include directives
  | 'Define'          // Define directives
  | 'Macro'           // Macros
  | 'PreCondit'       // Preprocessor conditionals
  | 'Type'            // Types
  | 'StorageClass'    // Storage class (static, etc.)
  | 'Structure'       // Structures
  | 'Typedef'         // Typedefs
  | 'Special'         // Special symbols
  | 'SpecialChar'     // Special characters
  | 'Tag'             // Tags
  | 'Delimiter'       // Delimiters
  | 'SpecialComment'  // Special comments
  | 'Debug'           // Debug statements
  | 'Underlined'      // Underlined text
  | 'Ignore'          // Ignored text
  | 'Error'           // Errors
  | 'Todo'            // TODO notes

  // === Diagnostics (LSP) ===
  | 'DiagnosticError'         // Error diagnostics
  | 'DiagnosticWarn'          // Warning diagnostics
  | 'DiagnosticInfo'          // Info diagnostics
  | 'DiagnosticHint'          // Hint diagnostics
  | 'DiagnosticUnderlineError'
  | 'DiagnosticUnderlineWarn'
  | 'DiagnosticUnderlineInfo'
  | 'DiagnosticUnderlineHint'

  // === Search ===
  | 'Search'          // Last search pattern
  | 'IncSearch'       // Incremental search
  | 'CurSearch'       // Current search match

  // === Diff ===
  | 'DiffAdd'         // Added lines
  | 'DiffChange'      // Changed lines
  | 'DiffDelete'      // Deleted lines
  | 'DiffText'        // Changed text within a line

  // === Misc ===
  | 'Visual'          // Visual mode selection
  | 'VisualNOS'       // Visual mode selection when not owning selection
  | 'MatchParen'      // Matching parenthesis
  | 'Conceal'         // Concealed text
  | 'Directory'       // Directory names
  | 'Title'           // Titles
  | 'Question'        // Question prompts
  | 'MoreMsg'         // More prompt
  | 'ModeMsg'         // Mode message
  | 'NonText'         // Non-text characters
  | 'SpecialKey'      // Special keys
  | 'Whitespace'      // Whitespace characters
  | 'EndOfBuffer'     // Empty lines at end of buffer

  // Allow any string for custom highlight groups
  | string;

/**
 * Key mapping modes
 */
export type MapMode =
  | 'n'   // Normal mode
  | 'i'   // Insert mode
  | 'v'   // Visual mode
  | 'x'   // Visual block mode
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
  /** Expression mapping */
  expr?: boolean;
  /** Unique mapping */
  unique?: boolean;
  /** Buffer-local mapping */
  buffer?: boolean;
  /** Description of the mapping */
  desc?: string;
}

/**
 * Main vim global interface
 */
export interface Vim {
  /**
   * Define syntax highlighting for a group
   * @param name - Highlight group name
   * @param opts - Styling options (bg, fg, bold, etc.)
   *
   * @example
   * vim.highlight('CursorLine', { bg: '#2b2b2b' });
   * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
   */
  highlight(name: HighlightGroup, opts: HighlightOpts): void;

  /**
   * Clear highlight for a group
   * @param name - Highlight group name
   *
   * @example
   * vim.clearHighlight('Comment');
   */
  clearHighlight?(name: HighlightGroup): void;

  /**
   * Set a key mapping
   * @param mode - Mode(s) where mapping applies
   * @param lhs - Left-hand side (key to map)
   * @param rhs - Right-hand side (action or keys)
   * @param opts - Mapping options
   *
   * @example
   * vim.keymap('n', '<leader>w', ':w<CR>', { silent: true });
   * vim.keymap('i', 'jk', '<Esc>', { noremap: true });
   */
  keymap?(mode: MapMode, lhs: string, rhs: string, opts?: KeymapOpts): void;

  /**
   * Execute a Vim command
   * @param cmd - Command to execute
   *
   * @example
   * vim.cmd('set number');
   * vim.cmd('colorscheme default');
   */
  cmd?(cmd: string): void;

  /**
   * Execute a Vim Ex command
   * @param cmd - Ex command (without leading ':')
   *
   * @example
   * vim.ex('write');
   * vim.ex('quit');
   */
  ex?(cmd: string): void;

  /**
   * Editor options
   *
   * @example
   * vim.opt.cursorLine = true;
   * vim.opt.number = true;
   * vim.opt.relativeNumber = true;
   */
  opt: VimOptions;

  /**
   * Global variables
   *
   * @example
   * vim.g.mapleader = ' ';
   * vim.g.loaded_netrw = 1;
   */
  g?: Record<string, any>;

  /**
   * Buffer-local variables
   */
  b?: Record<string, any>;

  /**
   * Window-local variables
   */
  w?: Record<string, any>;

  /**
   * Tab-local variables
   */
  t?: Record<string, any>;

  /**
   * Vim variables (v:)
   */
  v?: Record<string, any>;

  /**
   * Environment variables
   */
  env?: Record<string, string>;
}

/**
 * Console interface for debugging
 */
export interface Console {
  /**
   * Log messages to Chrome DevTools console
   * Supports multiple arguments of any type
   */
  log(...args: any[]): void;
}

// Global declarations
declare global {
  /**
   * Global vim object - main API for configuring OpenVim
   */
  var vim: Vim;

  /**
   * Global console object - for debugging via Chrome DevTools
   * Available methods: log(...args)
   */
  var console: Console;

  /**
   * Schedule a function to run after a delay
   * @param callback - Function to execute
   * @param delay - Delay in milliseconds (default: 0)
   * @returns Timer ID for clearTimeout
   */
  function setTimeout(callback: () => void, delay?: number): number;

  /**
   * Schedule a function to run repeatedly at intervals
   * @param callback - Function to execute
   * @param delay - Delay between executions in milliseconds (default: 0)
   * @returns Timer ID for clearInterval
   */
  function setInterval(callback: () => void, delay?: number): number;

  /**
   * Cancel a timeout created by setTimeout
   * @param id - Timer ID returned by setTimeout
   */
  function clearTimeout(id: number): void;

  /**
   * Cancel an interval created by setInterval
   * @param id - Timer ID returned by setInterval
   */
  function clearInterval(id: number): void;
}

export {};
