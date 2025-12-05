// Vimcraft TypeScript Type Definitions
// Version: 0.7.0 - Modern Editor API with CommonJS Module System
// JavaScript-first API design with camelCase naming conventions
// Phase 4: CommonJS require(), module.exports, Event Emitter

// ============================================================================
// Type Aliases & Utility Types
// ============================================================================

/**
 * Buffer handle representing a Vimcraft buffer.
 *
 * Special values:
 * - `0` refers to the current buffer
 * - Positive integers refer to specific buffer numbers
 *
 * @example
 * // Get current buffer number
 * const buf: Buffer = vim.api.getCurrentBuf();
 *
 * // Use 0 to refer to current buffer
 * vim.api.bufGetLines(0, 0, -1, false);
 */
export type Buffer = number;

/**
 * Window handle representing a Vimcraft window.
 *
 * Special values:
 * - `0` refers to the current window
 * - Positive integers refer to specific window numbers
 *
 * @example
 * // Get current window
 * const win: Window = vim.api.getCurrentWin();
 *
 * // Get cursor position in current window
 * const [row, col] = vim.api.winGetCursor(0);
 */
export type Window = number;

/**
 * Tabpage handle representing a Vimcraft tabpage.
 *
 * Special values:
 * - `0` refers to the current tabpage
 * - Positive integers refer to specific tabpage numbers
 *
 * @example
 * // Get current tabpage
 * const tab: Tabpage = vim.api.getCurrentTabpage();
 */
export type Tabpage = number;

/**
 * Namespace ID for organizing highlights, extmarks, and diagnostics.
 *
 * Namespaces allow plugins to group related decorations together
 * and manage them independently. Create with `vim.api.createNamespace()`.
 *
 * @example
 * // Create a namespace for your plugin
 * const ns = vim.api.createNamespace('my-plugin');
 *
 * // Use namespace for highlights
 * vim.api.bufAddHighlight(0, ns, 'Error', 0, 0, 5);
 *
 * // Clear all highlights in namespace
 * vim.api.bufClearNamespace(0, ns, 0, -1);
 */
export type Namespace = number;

/**
 * Autocommand ID returned by `vim.api.createAutocmd()`.
 *
 * Used to identify and delete specific autocommands.
 *
 * @example
 * // Create an autocommand and save its ID
 * const id: AutocmdID = vim.api.createAutocmd('BufEnter', {
 *   callback: (args) => console.log('Entered buffer:', args.file)
 * });
 *
 * // Delete the autocommand later
 * vim.api.delAutocmd(id);
 */
export type AutocmdID = number;

/**
 * User command ID for custom Ex commands.
 *
 * Used to identify user-defined commands created with
 * `vim.api.createUserCmd()`.
 */
export type CommandID = number;

/**
 * Extmark ID returned by `vim.api.bufSetExtmark()`.
 *
 * Used to identify and manage extmarks (extended marks) in buffers.
 * Extmarks track positions and survive text edits.
 *
 * @example
 * const ns = vim.api.createNamespace('my-plugin');
 * const id: ExtmarkID = vim.api.bufSetExtmark(0, ns, 0, 0, { hlGroup: 'Error' });
 */
export type ExtmarkID = number;

/**
 * Options for creating or updating an extmark.
 *
 * @example
 * // Simple extmark at position
 * vim.api.bufSetExtmark(0, ns, 0, 5, {});
 *
 * // Extmark with highlight
 * vim.api.bufSetExtmark(0, ns, 0, 5, {
 *   endLine: 0,
 *   endCol: 10,
 *   hlGroup: 'Search'
 * });
 *
 * // Extmark with priority
 * vim.api.bufSetExtmark(0, ns, 0, 5, {
 *   hlGroup: 'Error',
 *   priority: 200
 * });
 */
export interface ExtmarkOpts {
  /** End line for range (0-indexed) */
  endLine?: number;
  /** End column for range (0-indexed, byte offset) */
  endCol?: number;
  /** Highlight group name */
  hlGroup?: string;
  /** Priority for overlapping highlights (higher = more priority, default: 4096) */
  priority?: number;
  /** Update existing extmark by ID instead of creating new */
  id?: ExtmarkID;
  /** Sign text to display in signcolumn (1-2 chars, e.g., "+", ">>", "✓") */
  signText?: string;
  /** Highlight group for sign text (e.g., "GitSignsAdd", "DiagnosticSignError") */
  signHlGroup?: string;
}

/**
 * Detailed information about an extmark when `details: true` is passed.
 *
 * @example
 * const [id, line, col, details] = vim.api.bufGetExtmarkById(0, ns, extmarkId, { details: true });
 * console.log(details.hlGroup); // 'Error'
 */
export interface ExtmarkDetails {
  /** End line (0-indexed) */
  endLine?: number;
  /** End column (0-indexed, byte offset) */
  endCol?: number;
  /** Highlight group name */
  hlGroup?: string;
  /** Priority value */
  priority?: number;
}

/**
 * Options for querying extmarks.
 *
 * @example
 * // Get all extmarks in namespace
 * const marks = vim.api.bufGetExtmarks(0, ns, 0, -1, {});
 *
 * // Get extmarks with details
 * const marksWithDetails = vim.api.bufGetExtmarks(0, ns, 0, -1, { details: true });
 *
 * // Limit results
 * const first5 = vim.api.bufGetExtmarks(0, ns, 0, -1, { limit: 5 });
 */
export interface ExtmarkGetOpts {
  /** Maximum number of extmarks to return */
  limit?: number;
  /** Include details (endLine, endCol, hlGroup, priority) */
  details?: boolean;
}

/**
 * Position specification for extmark queries.
 *
 * - `0`: Start of buffer
 * - `-1`: End of buffer
 * - `[line, col]`: Specific position (0-indexed)
 * - `ExtmarkID`: Position of existing extmark
 *
 * @example
 * // Get all extmarks
 * vim.api.bufGetExtmarks(0, ns, 0, -1, {});
 *
 * // Get extmarks from line 5 to end
 * vim.api.bufGetExtmarks(0, ns, [5, 0], -1, {});
 *
 * // Get extmarks from specific extmark to end
 * vim.api.bufGetExtmarks(0, ns, existingExtmarkId, -1, {});
 */
export type ExtmarkPosition = 0 | -1 | [number, number] | ExtmarkID;

// ============================================================================
// Floating Window Types
// ============================================================================

/**
 * Relative positioning mode for floating windows.
 *
 * - `'editor'`: Position relative to the editor grid
 * - `'win'`: Position relative to a window (requires `win` option)
 * - `'cursor'`: Position relative to cursor position
 * - `'mouse'`: Position relative to mouse position (if available)
 */
export type FloatingRelative = 'editor' | 'win' | 'cursor' | 'mouse';

/**
 * Anchor position for floating windows.
 *
 * The anchor determines which corner of the floating window is placed
 * at the specified row/col position.
 *
 * - `'NW'`: Top-left (default)
 * - `'NE'`: Top-right
 * - `'SW'`: Bottom-left
 * - `'SE'`: Bottom-right
 */
export type FloatingAnchor = 'NW' | 'NE' | 'SW' | 'SE';

/**
 * Border style for floating windows.
 *
 * Can be a preset string or a custom array of border characters.
 *
 * @example
 * // Preset styles
 * border: 'none'     // No border
 * border: 'single'   // Single-line box drawing characters
 * border: 'double'   // Double-line box drawing characters
 * border: 'rounded'  // Rounded corners
 * border: 'solid'    // Solid block characters
 * border: 'shadow'   // Shadow effect
 *
 * @example
 * // Custom border (8 characters: top-left, top, top-right, right, bottom-right, bottom, bottom-left, left)
 * border: ['╭', '─', '╮', '│', '╯', '─', '╰', '│']
 */
export type FloatingBorder = 'none' | 'single' | 'double' | 'rounded' | 'solid' | 'shadow' | string[];

/**
 * Configuration options for floating windows.
 *
 * Floating windows are positioned relative to the editor, cursor, or another window.
 * They can have borders, titles, and various styling options.
 *
 * @example
 * // Simple floating window at cursor
 * const config: FloatingWinConfig = {
 *   relative: 'cursor',
 *   row: 1,
 *   col: 0,
 *   width: 20,
 *   height: 5
 * };
 *
 * @example
 * // Centered floating window with border
 * const config: FloatingWinConfig = {
 *   relative: 'editor',
 *   row: 10,
 *   col: 20,
 *   width: 40,
 *   height: 10,
 *   border: 'rounded',
 *   title: 'My Window',
 *   titlePos: 'center'
 * };
 *
 * @example
 * // Floating window anchored to another window
 * const config: FloatingWinConfig = {
 *   relative: 'win',
 *   win: existingWindow,
 *   anchor: 'NE',
 *   row: 0,
 *   col: 0,
 *   width: 30,
 *   height: 8
 * };
 */
export interface FloatingWinConfig {
  /**
   * Positioning mode for the floating window.
   * Required when creating a new floating window.
   */
  relative: FloatingRelative;

  /**
   * Window to position relative to when `relative: 'win'`.
   * Use 0 for current window.
   */
  win?: Window;

  /**
   * Anchor corner of the floating window for positioning.
   * Default: 'NW' (top-left)
   */
  anchor?: FloatingAnchor;

  /**
   * Row position (0-indexed), relative to the anchor.
   * Can be negative to position above the anchor point.
   */
  row: number;

  /**
   * Column position (0-indexed), relative to the anchor.
   * Can be negative to position left of the anchor point.
   */
  col: number;

  /**
   * Width of the floating window in columns.
   */
  width: number;

  /**
   * Height of the floating window in rows.
   */
  height: number;

  /**
   * Whether the window can receive focus.
   * Default: true
   */
  focusable?: boolean;

  /**
   * Z-index for stacking order. Higher values appear on top.
   * Default: 50
   */
  zindex?: number;

  /**
   * Border style. Can be a preset name or custom characters.
   */
  border?: FloatingBorder;

  /**
   * Title text to display in the border.
   * Requires a border to be set.
   */
  title?: string;

  /**
   * Position of the title in the border.
   * Default: 'left'
   */
  titlePos?: 'left' | 'center' | 'right';

  /**
   * Footer text to display in the bottom border.
   * Requires a border to be set.
   */
  footer?: string;

  /**
   * Position of the footer in the border.
   * Default: 'left'
   */
  footerPos?: 'left' | 'center' | 'right';

  /**
   * Whether the window is hidden.
   * Hidden windows are not displayed but retain their configuration.
   */
  hide?: boolean;

  /**
   * Style presets for the window.
   * - 'minimal': No line numbers, no status line
   */
  style?: 'minimal';
}

/**
 * RGB color representation with integer values 0-255.
 *
 * @example
 * const red: Color = { r: 255, g: 0, b: 0 };
 * const blue: Color = { r: 0, g: 0, b: 255 };
 */
export interface Color {
  /** Red component (0-255) */
  r: number;
  /** Green component (0-255) */
  g: number;
  /** Blue component (0-255) */
  b: number;
}

// ============================================================================
// Highlight System
// ============================================================================

/**
 * Highlight group styling options for defining syntax colors and text attributes.
 *
 * Used with `vim.highlight()` and `vim.api.setHighlight()` to customize
 * the appearance of text, UI elements, and syntax highlighting.
 *
 * @example
 * // Define a simple highlight with foreground color
 * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
 *
 * @example
 * // Define a highlight with background and multiple attributes
 * vim.highlight('Visual', {
 *   bg: '#264f78',
 *   bold: true
 * });
 *
 * @example
 * // Link to an existing highlight group
 * vim.highlight('MyCustomGroup', { link: 'Comment' });
 *
 * @see https://vimcraft.com/docs/api/highlight
 */
export interface HighlightOpts {
  /**
   * Background color as a hex string (e.g., '#1a1b26') or null to clear.
   *
   * @example
   * vim.highlight('CursorLine', { bg: '#2e2e3e' });
   */
  bg?: string | null;

  /**
   * Foreground (text) color as a hex string (e.g., '#abb2bf') or null to clear.
   *
   * @example
   * vim.highlight('Comment', { fg: '#6c6c6c' });
   */
  fg?: string | null;

  /**
   * Special color for undercurl, underline, and other decorations.
   * Typically used for spell checking and diagnostic underlines.
   *
   * @example
   * vim.highlight('SpellBad', { sp: '#ff0000', undercurl: true });
   */
  sp?: string | null;

  /**
   * Color blend value for floating windows (0-100).
   * 0 = fully opaque, 100 = fully transparent.
   *
   * @example
   * vim.highlight('NormalFloat', { bg: '#1a1b26', blend: 20 });
   */
  blend?: number;

  /**
   * Render text in bold.
   *
   * @example
   * vim.highlight('Keyword', { fg: '#c678dd', bold: true });
   */
  bold?: boolean;

  /**
   * Render text in italic.
   *
   * @example
   * vim.highlight('Comment', { fg: '#5c6370', italic: true });
   */
  italic?: boolean;

  /**
   * Render text with a straight underline.
   */
  underline?: boolean;

  /**
   * Render text with a curly underline (squiggly line).
   * Commonly used for spell checking and diagnostics.
   *
   * @example
   * vim.highlight('DiagnosticUnderlineError', { sp: '#e06c75', undercurl: true });
   */
  undercurl?: boolean;

  /**
   * Render text with a double underline.
   */
  underdouble?: boolean;

  /**
   * Render text with a dotted underline.
   */
  underdotted?: boolean;

  /**
   * Render text with a dashed underline.
   */
  underdashed?: boolean;

  /**
   * Render text with a horizontal line through the middle.
   *
   * @example
   * vim.highlight('Deprecated', { fg: '#808080', strikethrough: true });
   */
  strikethrough?: boolean;

  /**
   * Swap foreground and background colors.
   *
   * @example
   * vim.highlight('Search', { fg: '#000000', bg: '#ffff00', reverse: true });
   */
  reverse?: boolean;

  /**
   * Make the text stand out (implementation varies by terminal).
   */
  standout?: boolean;

  /**
   * Highlight priority (0-10000).
   * Higher values take precedence when multiple highlights overlap.
   * Default priority varies by highlight type.
   */
  priority?: number;

  /**
   * Link this highlight group to another group.
   * The linked group inherits all styling from the target.
   *
   * @example
   * // Make 'MyKeyword' look exactly like 'Keyword'
   * vim.highlight('MyKeyword', { link: 'Keyword' });
   */
  link?: string;
}

/**
 * Standard Vim/Neovim highlight group names.
 *
 * These are the built-in highlight groups used for syntax highlighting,
 * UI elements, and various editor features. Custom group names (strings)
 * are also allowed.
 *
 * Categories:
 * - **Editor UI**: Normal, CursorLine, LineNr, StatusLine, etc.
 * - **Syntax**: Comment, String, Keyword, Function, Type, etc.
 * - **Diagnostics**: DiagnosticError, DiagnosticWarn, etc.
 * - **Diff**: DiffAdd, DiffChange, DiffDelete, etc.
 *
 * @example
 * // Use a standard group name
 * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
 *
 * @example
 * // Use a custom group name
 * vim.highlight('MyPluginHighlight', { bg: '#2e2e3e' });
 *
 * @see https://vimcraft.com/docs/editor-api/user/syntax#highlight-groups
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
 * Status line display mode controlling when the status line is shown.
 *
 * Used with `vim.opt.lastStatus` to control status line visibility.
 *
 * @example
 * // Hide status line completely
 * vim.opt.lastStatus = LastStatus.Never;
 *
 * @example
 * // Always show status line (default behavior)
 * vim.opt.lastStatus = LastStatus.Always;
 *
 * @example
 * // Or use numeric values directly
 * vim.opt.lastStatus = 2; // Same as LastStatus.Always
 *
 * @see https://vimcraft.com/docs/editor-api/user/options#'laststatus'
 */
export enum LastStatus {
  /**
   * Never show status line.
   * Equivalent to Vim's `set laststatus=0`.
   */
  Never = 0,

  /**
   * Show status line only if there are multiple windows.
   * Currently behaves like `Always` in Vimcraft.
   * Equivalent to Vim's `set laststatus=1`.
   */
  OnlyIfMultipleWindows = 1,

  /**
   * Always show status line (default).
   * Equivalent to Vim's `set laststatus=2`.
   */
  Always = 2,

  /**
   * Global status line - show only in the last window.
   * Currently behaves like `Always` in Vimcraft.
   * Equivalent to Vim's `set laststatus=3`.
   */
  Global = 3,
}

/**
 * Controls how concealed text is displayed.
 *
 * Used with `vim.opt.concealLevel` to control visibility of concealed text
 * (e.g., markdown code fence markers in LSP hover popups).
 *
 * @example
 * // Show concealed text normally (default for editing)
 * vim.opt.concealLevel = ConcealLevel.Normal;
 *
 * @example
 * // Hide concealed text completely (for popups)
 * vim.opt.concealLevel = ConcealLevel.Hidden;
 */
export enum ConcealLevel {
  /**
   * Show concealed text normally (no concealment).
   * Equivalent to Vim's `set conceallevel=0`.
   */
  Normal = 0,

  /**
   * Replace concealed text with a single character.
   * Uses the character from syntax or a default.
   * Equivalent to Vim's `set conceallevel=1`.
   */
  ReplaceWithChar = 1,

  /**
   * Hide concealed text completely (unless it has a replacement char).
   * Equivalent to Vim's `set conceallevel=2`.
   */
  Hidden = 2,

  /**
   * Hide concealed text completely (always).
   * Equivalent to Vim's `set conceallevel=3`.
   */
  HiddenAlways = 3,
}

/**
 * Controls whether concealed text is hidden on the cursor line.
 *
 * Used with `vim.opt.concealCursor` to control when concealment
 * applies to the line where the cursor is positioned.
 *
 * @example
 * // Keep text concealed in normal mode (for popups)
 * vim.opt.concealCursor = ConcealCursor.Normal;
 *
 * @example
 * // Never conceal on cursor line (default for editing)
 * vim.opt.concealCursor = ConcealCursor.None;
 */
export enum ConcealCursor {
  /**
   * Never conceal text on cursor line.
   * Equivalent to Vim's `set concealcursor=`.
   */
  None = "",

  /**
   * Conceal in normal mode.
   * Equivalent to Vim's `set concealcursor=n`.
   */
  Normal = "n",

  /**
   * Conceal in visual mode.
   * Equivalent to Vim's `set concealcursor=v`.
   */
  Visual = "v",

  /**
   * Conceal in insert mode.
   * Equivalent to Vim's `set concealcursor=i`.
   */
  Insert = "i",

  /**
   * Conceal in command mode.
   * Equivalent to Vim's `set concealcursor=c`.
   */
  Command = "c",

  /**
   * Conceal in normal and visual modes.
   * Equivalent to Vim's `set concealcursor=nv`.
   */
  NormalVisual = "nv",

  /**
   * Conceal in normal, visual, and insert modes.
   * Equivalent to Vim's `set concealcursor=nvi`.
   */
  NormalVisualInsert = "nvi",

  /**
   * Conceal in all modes.
   * Equivalent to Vim's `set concealcursor=nvic`.
   */
  All = "nvic",
}

/**
 * Editor options accessible via `vim.opt`.
 *
 * All option names use camelCase for JavaScript/TypeScript convention,
 * mapping to their Vim snake_case equivalents (e.g., `cursorLine` → `cursorline`).
 *
 * Options are reactive - changes take effect immediately.
 *
 * @example
 * // Enable line numbers and cursor line highlighting
 * vim.opt.number = true;
 * vim.opt.cursorLine = true;
 *
 * @example
 * // Configure tabs and indentation
 * vim.opt.tabStop = 4;
 * vim.opt.shiftWidth = 4;
 * vim.opt.expandTab = true;
 *
 * @example
 * // Configure search behavior
 * vim.opt.ignoreCase = true;
 * vim.opt.smartCase = true;
 * vim.opt.hlSearch = true;
 *
 * @see https://vimcraft.com/docs/editor-api/user/options
 */
export interface VimOptions {
  // =========================================================================
  // Display Options
  // =========================================================================

  /**
   * Show line numbers in the gutter.
   * @default false
   */
  number?: boolean;

  /**
   * Show relative line numbers (distance from cursor line).
   * When combined with `number`, shows absolute number on cursor line.
   * @default false
   */
  relativeNumber?: boolean;

  /**
   * Minimum number of columns to use for line numbers.
   * The actual width will be larger if needed to fit the highest line number.
   * Valid range: 1-20.
   * @default 4
   *
   * @example
   * vim.opt.numberWidth = 2;  // Compact line numbers (e.g., " 1 " instead of "   1 ")
   * vim.opt.numberWidth = 6;  // Extra padding for alignment
   */
  numberWidth?: number;

  /**
   * Highlight the current line the cursor is on.
   * @default false
   */
  cursorLine?: boolean;

  /**
   * Highlight the current column the cursor is on.
   * @default false
   */
  cursorColumn?: boolean;

  /**
   * When and how to display the sign column (gutter for diagnostics, git signs, etc.).
   * - `'yes'`: Always show sign column
   * - `'no'`: Never show sign column
   * - `'auto'`: Show only when there are signs
   * - `'number'`: Display signs in the number column
   * @default 'auto'
   */
  signColumn?: 'yes' | 'no' | 'auto' | 'number';

  /**
   * Columns to highlight with ColorColumn highlight group.
   * Useful for marking text width limits (e.g., 80, 120 characters).
   *
   * @example
   * vim.opt.colorColumn = '80,120';
   */
  colorColumn?: string;

  /**
   * Minimum number of lines to keep visible above and below the cursor.
   * Prevents cursor from reaching the very top or bottom of the viewport.
   * @default 0
   */
  scrollOff?: number;

  /**
   * Minimum number of columns to keep visible left and right of the cursor.
   * Useful for horizontal scrolling contexts.
   * @default 0
   */
  sideScrollOff?: number;

  /**
   * When to show the status line.
   * See `LastStatus` enum for available values.
   * @default LastStatus.Always (2)
   */
  lastStatus?: LastStatus | 0 | 1 | 2 | 3;

  /**
   * How to display concealed text (e.g., markdown code fence markers).
   * See `ConcealLevel` enum for available values.
   *
   * - `Normal` (0): Show text normally
   * - `ReplaceWithChar` (1): Replace with single character
   * - `Hidden` (2): Hide completely (used for popups)
   * - `HiddenAlways` (3): Always hide
   *
   * @default ConcealLevel.Normal (0)
   */
  concealLevel?: ConcealLevel | 0 | 1 | 2 | 3;

  /**
   * Whether to conceal text on the cursor line.
   * See `ConcealCursor` enum for available values.
   *
   * Controls which modes keep text concealed even when cursor is on the line.
   * Commonly set to `"n"` for floating windows so content stays clean.
   *
   * @default ConcealCursor.None ("")
   */
  concealCursor?: ConcealCursor | "" | "n" | "v" | "i" | "c" | "nv" | "nvi" | "nvic";

  /**
   * Show (partial) command in the last line of the screen.
   * Displays keys as they are typed for multi-key commands.
   * @default true
   */
  showCmd?: boolean;

  /**
   * Show current mode (INSERT, VISUAL, etc.) in the command line.
   * @default true
   */
  showMode?: boolean;

  /**
   * Show cursor position (line and column) in the status line.
   * @default true
   */
  ruler?: boolean;

  /**
   * Wrap long lines at the edge of the screen.
   * When disabled, lines extend beyond the visible area.
   * @default true
   */
  wrap?: boolean;

  /**
   * Wrap long lines at word boundaries instead of mid-word.
   * Only effective when `wrap` is enabled.
   * @default false
   */
  lineBreak?: boolean;

  /**
   * Show invisible characters (tabs, trailing spaces, etc.).
   * Configure which characters to show with `listChars`.
   * @default false
   */
  list?: boolean;

  /**
   * Characters to show for invisible characters when `list` is enabled.
   * Each key specifies which invisible character to display and its replacement.
   *
   * @example
   * vim.opt.listChars = { tab: '→ ', trail: '·', nbsp: '␣', eol: '¬' };
   */
  listChars?: {
    /** Two or three characters for tabs (e.g., "→ " or "<->") */
    tab?: string;
    /** Character for regular spaces */
    space?: string;
    /** Character for trailing spaces */
    trail?: string;
    /** Character for non-breaking spaces (0xA0) */
    nbsp?: string;
    /** Character at end of line */
    eol?: string;
    /** Character for leading spaces */
    lead?: string;
    /** Characters for multiple leading spaces */
    leadmultispace?: string;
    /** Characters for multiple spaces */
    multispace?: string;
    /** Character when line extends beyond screen (nowrap) */
    extends?: string;
    /** Character when line precedes screen (nowrap) */
    precedes?: string;
    /** Character for concealed text */
    conceal?: string;
  };

  /**
   * How text with "conceal" syntax attribute is shown.
   * - `0`: Concealed text shown normally
   * - `1`: Concealed text replaced with one character
   * - `2`: Concealed text replaced or hidden unless cursor is on line
   * - `3`: Concealed text completely hidden
   * @default 0
   */
  concealLevel?: 0 | 1 | 2 | 3;

  /**
   * Enable spell checking.
   * @default false
   */
  spell?: boolean;

  /**
   * Width of the fold column for displaying fold indicators.
   * @default '0'
   */
  foldColumn?: string;

  /**
   * Enable 24-bit RGB colors in the terminal.
   * Required for most modern color schemes.
   * @default true
   */
  termGuiColors?: boolean;

  /**
   * Background color mode ('light' or 'dark').
   * Affects default highlight group colors.
   * @default 'dark'
   */
  background?: 'light' | 'dark';

  /**
   * Briefly jump to matching bracket when inserting one.
   * @default false
   */
  showMatch?: boolean;

  // =========================================================================
  // Editing Options
  // =========================================================================

  /**
   * Number of spaces that a <Tab> character represents visually.
   * @default 8
   */
  tabStop?: number;

  /**
   * Number of spaces for each step of (auto)indent.
   * Used by `>>`, `<<`, and automatic indentation.
   * @default 8
   */
  shiftWidth?: number;

  /**
   * Use spaces instead of tabs when pressing <Tab>.
   * @default false
   */
  expandTab?: boolean;

  /**
   * Smart autoindenting when starting a new line.
   * Adds extra indentation after `{`, removes it after `}`.
   * @default false
   */
  smartIndent?: boolean;

  /**
   * Copy indent from current line when starting a new line.
   * @default true
   */
  autoIndent?: boolean;

  /**
   * Maximum width of text being inserted. Longer lines are broken.
   * Set to 0 to disable automatic line breaking.
   * @default 0
   */
  textWidth?: number;

  /**
   * Number of spaces that a <Tab> counts for while editing.
   * Set to 0 to use `tabStop` value.
   * @default 0
   */
  softTabStop?: number;

  /**
   * <Tab> at start of line inserts blanks according to `shiftWidth`.
   * @default true
   */
  smartTab?: boolean;

  /**
   * What the backspace key can delete in Insert mode.
   * Common values: 'indent', 'eol', 'start' (comma-separated).
   * @default 'indent,eol,start'
   */
  backspace?: string;

  /**
   * Controls automatic formatting behavior.
   * Common flags: t (auto-wrap text), c (auto-wrap comments), q (allow gq).
   */
  formatOptions?: string;

  /**
   * Options for Insert mode completion popup.
   * Common values: 'menu', 'menuone', 'noselect', 'preview'.
   */
  completeOpt?: string;

  /**
   * When to allow cursor to move beyond end of line.
   * Common values: 'block' (Visual block mode), 'all' (always).
   */
  virtualEdit?: string;

  /**
   * Whether the buffer can be modified.
   * @default true
   */
  modifiable?: boolean;

  /**
   * Whether the buffer is read-only.
   * @default false
   */
  readOnly?: boolean;

  // =========================================================================
  // Search Options
  // =========================================================================

  /**
   * Ignore case in search patterns.
   * @default false
   */
  ignoreCase?: boolean;

  /**
   * Override `ignoreCase` if search pattern contains uppercase letters.
   * Requires `ignoreCase` to be enabled.
   * @default false
   */
  smartCase?: boolean;

  /**
   * Highlight all matches of the previous search pattern.
   * Use `:nohlsearch` to clear highlighting.
   * @default false
   */
  hlSearch?: boolean;

  /**
   * Show matches incrementally while typing search pattern.
   * @default true
   */
  incSearch?: boolean;

  /**
   * Wrap around to the beginning when searching past the end of file.
   * @default true
   */
  wrapScan?: boolean;

  // =========================================================================
  // Behavior Options
  // =========================================================================

  /**
   * Enable mouse support.
   * Set to 'a' to enable for all modes.
   * @default ''
   */
  mouse?: string;

  /**
   * Clipboard configuration.
   * Set to 'unnamedplus' to use system clipboard for all yank/paste.
   */
  clipboard?: string;

  /**
   * Maximum number of undo levels to remember.
   * @default 1000
   */
  undoLevels?: number;

  /**
   * Time out on mappings and key codes.
   * @default true
   */
  timeout?: boolean;

  /**
   * Time in milliseconds to wait for a mapped sequence to complete.
   * @default 1000
   */
  timeoutLen?: number;

  /**
   * Time in milliseconds for CursorHold event and swap file writes.
   * Lower values trigger CursorHold more frequently.
   * @default 4000
   */
  updateTime?: number;

  /**
   * Allow switching buffers without saving changes first.
   * @default false
   */
  hidden?: boolean;

  /**
   * Create backup files before overwriting.
   * @default false
   */
  backup?: boolean;

  /**
   * Create backup before overwriting, delete after successful write.
   * @default true
   */
  writeBackup?: boolean;

  /**
   * Use swap files for crash recovery.
   * @default true
   */
  swapFile?: boolean;

  /**
   * Persist undo history to file for cross-session undo.
   * @default false
   */
  undoFile?: boolean;

  /**
   * Directory for storing undo files.
   */
  undoDir?: string;

  /**
   * New vertical splits open to the right of current window.
   * @default false
   */
  splitRight?: boolean;

  /**
   * New horizontal splits open below current window.
   * @default false
   */
  splitBelow?: boolean;

  /**
   * Automatically read file when changed outside the editor.
   * @default false
   */
  autoRead?: boolean;

  /**
   * Automatically write file when switching buffers.
   * @default false
   */
  autoWrite?: boolean;

  /**
   * Ask for confirmation when abandoning unsaved buffer.
   * @default false
   */
  confirm?: boolean;

  // =========================================================================
  // UI Options
  // =========================================================================

  /**
   * Number of lines to use for the command-line area.
   * @default 1
   */
  cmdHeight?: number;

  /**
   * Maximum height of popup menu (completion menu).
   * Set to 0 for unlimited height.
   * @default 0
   */
  pumHeight?: number;

  /**
   * Pseudo-transparency for floating windows (0-100).
   * 0 = fully opaque, 100 = fully transparent.
   * @default 0
   */
  winBlend?: number;

  /**
   * Pseudo-transparency for popup menu (0-100).
   * 0 = fully opaque, 100 = fully transparent.
   * @default 0
   */
  pumBlend?: number;

  /**
   * When to show the tabline.
   * - `0`: Never
   * - `1`: Only if there are multiple tabs
   * - `2`: Always
   * @default 1
   */
  showTabLine?: 0 | 1 | 2;

  /**
   * Enable enhanced command-line completion menu.
   * @default true
   */
  wildMenu?: boolean;

  /**
   * Completion mode for command-line.
   * Controls how matches are displayed and cycled.
   */
  wildMode?: string;
}

// ============================================================================
// Keymap System
// ============================================================================

/**
 * Key mapping mode identifiers.
 *
 * Each character represents a different Vim mode:
 * - `'n'` - Normal mode (default navigation mode)
 * - `'i'` - Insert mode (text input)
 * - `'v'` - Visual mode (character-wise selection)
 * - `'x'` - Visual block mode (block selection)
 * - `'s'` - Select mode (like Visual but typing replaces)
 * - `'o'` - Operator-pending mode (waiting for motion after operator)
 * - `'c'` - Command-line mode (`:`, `/`, `?`)
 * - `'t'` - Terminal mode (terminal emulator)
 * - `''`  - All modes
 *
 * @example
 * // Map only in Normal mode
 * vim.keymap.set('n', '<leader>f', ':find<CR>');
 *
 * @example
 * // Map in multiple modes
 * vim.keymap.set(['n', 'v'], '<leader>y', '"+y');
 *
 * @see https://vimcraft.com/docs/editor-api/user/map#map-modes
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
 * Options for key mappings.
 *
 * Controls mapping behavior like whether it's recursive, silent, or buffer-local.
 *
 * @example
 * // Silent, non-recursive mapping
 * vim.keymap.set('n', '<leader>w', ':w<CR>', {
 *   silent: true,
 *   noremap: true,
 *   desc: 'Save file'
 * });
 *
 * @example
 * // Buffer-local mapping
 * vim.keymap.set('n', 'gd', gotoDefinition, {
 *   buffer: true,
 *   desc: 'Go to definition'
 * });
 *
 * @see https://vimcraft.com/docs/editor-api/user/map#:map-arguments
 */
export interface KeymapOpts {
  /**
   * Non-recursive mapping (don't expand rhs mappings).
   * Equivalent to `:nnoremap` instead of `:nmap`.
   * @default true in vim.keymap.set()
   */
  noremap?: boolean;

  /**
   * Don't echo the mapping in the command line.
   * Equivalent to `:map <silent>`.
   * @default false
   */
  silent?: boolean;

  /**
   * Expression mapping - rhs is evaluated as an expression.
   * The result is used as the mapping.
   * Equivalent to `:map <expr>`.
   *
   * @example
   * vim.keymap.set('i', '<Tab>', () => {
   *   return vim.fn.pumvisible() ? '<C-n>' : '<Tab>';
   * }, { expr: true });
   */
  expr?: boolean;

  /**
   * Error if the mapping already exists.
   * Useful for plugins that don't want to override user mappings.
   * @default false
   */
  unique?: boolean;

  /**
   * Create a buffer-local mapping.
   * - `true` or `0`: Current buffer
   * - `number > 0`: Specific buffer number
   *
   * @example
   * // Map only for current buffer
   * vim.keymap.set('n', 'K', showDocs, { buffer: true });
   */
  buffer?: boolean | number;

  /**
   * Don't wait for other longer mappings to be typed.
   * Useful when you have mappings like 'a' and 'ab'.
   * @default false
   */
  nowait?: boolean;

  /**
   * Allow script-local remapping.
   * @default false
   */
  script?: boolean;

  /**
   * Replace keycodes in rhs (e.g., '<CR>' becomes actual carriage return).
   * @default true when expr is true
   */
  replaceKeycodes?: boolean;

  /**
   * Description of the mapping.
   * Shown in `:map` output and which-key plugins.
   *
   * @example
   * vim.keymap.set('n', '<leader>ff', findFiles, {
   *   desc: 'Find files in project'
   * });
   */
  desc?: string;

  /**
   * Callback function instead of rhs string.
   * Alternative to passing function as rhs parameter.
   */
  callback?: () => void;
}

/**
 * Key mapping interface for creating and managing key bindings.
 *
 * @example
 * // Basic mapping with command string
 * vim.keymap.set('n', '<leader>w', ':w<CR>', { desc: 'Save file' });
 *
 * @example
 * // Mapping with callback function
 * vim.keymap.set('n', '<leader>f', () => {
 *   console.log('Finding files...');
 *   // ... implementation
 * });
 *
 * @example
 * // Mapping in multiple modes
 * vim.keymap.set(['n', 'v'], '<leader>y', '"+y', {
 *   desc: 'Yank to system clipboard'
 * });
 *
 * @see https://vimcraft.com/docs/editor-api/user/lua#vim.keymap
 */
export interface Keymap {
  /**
   * Set a key mapping.
   *
   * Creates a mapping from {lhs} to {rhs} in the specified mode(s).
   * Can map to a command string or a Lua/JavaScript function.
   *
   * @param mode - Mode(s) where mapping applies. Can be a single mode
   *               character or an array of modes.
   * @param lhs - Left-hand side (key sequence to map, e.g., '<leader>w', 'jk')
   * @param rhs - Right-hand side (action). Can be:
   *              - Command string (e.g., ':w<CR>')
   *              - Key sequence (e.g., '<Esc>')
   *              - Callback function
   * @param opts - Optional mapping options
   *
   * @example
   * // Map <leader>w to save file
   * vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
   *
   * @example
   * // Map jk to escape in insert mode
   * vim.keymap.set('i', 'jk', '<Esc>');
   *
   * @example
   * // Map with callback function
   * vim.keymap.set('n', '<leader>d', () => {
   *   console.log('Custom delete action');
   * }, { desc: 'Custom delete' });
   *
   * @example
   * // Map in multiple modes
   * vim.keymap.set(['n', 'v'], 'Y', '"+y', {
   *   desc: 'Yank to clipboard'
   * });
   *
   * @see https://vimcraft.com/docs/editor-api/user/lua#vim.keymap.set()
   */
  set(mode: MapMode | MapMode[], lhs: string, rhs: string | (() => void), opts?: KeymapOpts): void;

  /**
   * Delete a key mapping.
   *
   * Removes an existing mapping for {lhs} in the specified mode(s).
   *
   * @param mode - Mode(s) where mapping should be deleted
   * @param lhs - Left-hand side (key sequence to unmap)
   * @param opts - Options. Currently only `buffer` is supported.
   *
   * @example
   * // Delete a global mapping
   * vim.keymap.del('n', '<leader>w');
   *
   * @example
   * // Delete a buffer-local mapping
   * vim.keymap.del('n', 'K', { buffer: true });
   *
   * @example
   * // Delete from multiple modes
   * vim.keymap.del(['n', 'v'], '<leader>y');
   *
   * @see https://vimcraft.com/docs/editor-api/user/lua#vim.keymap.del()
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
 * Autocommand callback arguments passed to autocmd callbacks.
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
  completeFunction?: (argLead: string, cmdLine: string, cursorPos: number) => string[];
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
  endLnum?: number;
  /** Column number (0-indexed) */
  col: number;
  /** End column number (0-indexed, optional) */
  endCol?: number;
  /** Severity level */
  severity: DiagnosticSeverity | number;
  /** Diagnostic message */
  message: string;
  /** Source of diagnostic (e.g., 'eslint', 'typescript') */
  source?: string;
  /** Error code */
  code?: string | number;
  /** User data */
  userData?: any;
}

/**
 * Diagnostic configuration
 */
export interface DiagnosticConfig {
  /** Underline diagnostics */
  underline?: boolean;
  /** Virtual text configuration */
  virtualText?: boolean | {
    spacing?: number;
    prefix?: string;
    source?: boolean | 'always' | 'ifMany';
    format?: (diagnostic: Diagnostic) => string;
  };
  /** Signs in sign column */
  signs?: boolean | {
    text?: Record<string, string>;
    priority?: number;
  };
  /** Update diagnostics in insert mode */
  updateInInsert?: boolean;
  /** Severity sort order */
  severitySort?: boolean | {
    reverse?: boolean;
  };
  /** Float window configuration */
  float?: boolean | {
    source?: boolean | 'always' | 'ifMany';
    border?: string;
    header?: string;
    prefix?: string | ((diagnostic: Diagnostic, i: number, total: number) => string);
  };
}

/**
 * Diagnostic severity object with both named and numeric keys.
 * Neovim-compatible severity levels.
 *
 * @example
 * // Access by name
 * vim.diagnostic.severity.ERROR // 1
 * vim.diagnostic.severity.WARN  // 2
 *
 * // Reverse lookup
 * vim.diagnostic.severity[1] // "ERROR"
 */
export interface DiagnosticSeverityMap {
  ERROR: 1;
  WARN: 2;
  INFO: 3;
  HINT: 4;
  // Reverse mappings
  1: 'ERROR';
  2: 'WARN';
  3: 'INFO';
  4: 'HINT';
}

/**
 * Diagnostic interface (vim.diagnostic)
 */
export interface DiagnosticAPI {
  /**
   * Severity levels (ERROR=1, WARN=2, INFO=3, HINT=4)
   */
  severity: DiagnosticSeverityMap;

  /**
   * Set diagnostics for a namespace
   */
  set(namespace: Namespace, bufnr: Buffer, diagnostics: Diagnostic[], opts?: any): void;

  /**
   * Get diagnostics
   */
  get(bufnr?: Buffer, opts?: { namespace?: Namespace; lnum?: number; severity?: DiagnosticSeverity }): Diagnostic[];

  /**
   * Clear diagnostics for a namespace/buffer
   * @param namespace - Namespace to clear (undefined for all namespaces)
   * @param bufnr - Buffer to clear (undefined for all buffers)
   */
  reset(namespace?: Namespace, bufnr?: Buffer): void;

  /**
   * Count diagnostics by severity
   * @param bufnr - Buffer to count (undefined for all buffers)
   * @param opts - Options with optional namespace filter
   * @returns Object with severity keys (1-4) and counts
   *
   * @example
   * const counts = vim.diagnostic.count(0);
   * console.log(counts[vim.diagnostic.severity.ERROR]); // 2
   */
  count(bufnr?: Buffer, opts?: { namespace?: Namespace }): Record<DiagnosticSeverity, number>;

  /**
   * Configure diagnostics (not yet implemented)
   */
  config?(opts: DiagnosticConfig, namespace?: Namespace): void;

  /**
   * Show diagnostics in floating window (not yet implemented)
   */
  openFloat?(opts?: any): void;

  /**
   * Jump to next diagnostic (not yet implemented)
   */
  gotoNext?(opts?: any): void;

  /**
   * Jump to previous diagnostic (not yet implemented)
   */
  gotoPrev?(opts?: any): void;

  /**
   * Enable diagnostics (not yet implemented)
   */
  enable?(bufnr?: Buffer, namespace?: Namespace): void;

  /**
   * Disable diagnostics (not yet implemented)
   */
  disable?(bufnr?: Buffer, namespace?: Namespace): void;
}

// ============================================================================
// Core API (vim.api)
// ============================================================================

/**
 * Core API interface (vim.api)
 * JavaScript-native functions with camelCase naming conventions.
 */
export interface API {
  // === Buffer Functions ===

  /** Get current buffer */
  getCurrentBuf(): Buffer;

  /** Set current buffer */
  setCurrentBuf(buffer: Buffer): void;

  /** Get buffer lines */
  bufGetLines(buffer: Buffer, start: number, end: number, strictIndexing: boolean): string[];

  /** Set buffer lines */
  bufSetLines(buffer: Buffer, start: number, end: number, strictIndexing: boolean, replacement: string[]): void;

  /** Get buffer line count */
  bufLineCount(buffer: Buffer): number;

  /** Get buffer name */
  bufGetName(buffer: Buffer): string;

  /** Set buffer name */
  bufSetName(buffer: Buffer, name: string): void;

  /** Check if buffer is valid */
  bufIsValid(buffer: Buffer): boolean;

  /** Delete buffer */
  bufDelete(buffer: Buffer, opts: { force?: boolean; unload?: boolean }): void;

  // === Window Functions ===

  /** Get current window */
  getCurrentWin(): Window;

  /** Set current window */
  setCurrentWin(window: Window): void;

  /** Get window buffer */
  winGetBuf(window: Window): Buffer;

  /** Set window buffer */
  winSetBuf(window: Window, buffer: Buffer): void;

  /** Get window cursor position [row, col] (1-indexed, 0-indexed) */
  winGetCursor(window: Window): [number, number];

  /** Set window cursor position [row, col] (1-indexed, 0-indexed) */
  winSetCursor(window: Window, pos: [number, number]): void;

  /** Get window height */
  winGetHeight(window: Window): number;

  /** Set window height */
  winSetHeight(window: Window, height: number): void;

  /** Get window width */
  winGetWidth(window: Window): number;

  /** Set window width */
  winSetWidth(window: Window, width: number): void;

  /** Check if window is valid */
  winIsValid(window: Window): boolean;

  /** Close window */
  winClose(window: Window, force: boolean): void;

  // === Floating Window Functions ===

  /**
   * Open a new floating window.
   *
   * Creates a floating window displaying the specified buffer. Floating windows
   * are positioned relative to the editor, cursor, or another window.
   *
   * @param buffer - Buffer to display (use 0 for current buffer or vim.api.createBuf())
   * @param enter - Whether to enter the window (make it current)
   * @param config - Floating window configuration
   * @returns Window handle for the new floating window
   *
   * @example
   * // Create a simple floating window at cursor
   * const buf = vim.api.createBuf(false, true);
   * vim.api.bufSetLines(buf, 0, -1, false, ['Hello', 'World']);
   * const win = vim.api.openWin(buf, true, {
   *   relative: 'cursor',
   *   row: 1,
   *   col: 0,
   *   width: 20,
   *   height: 2
   * });
   *
   * // Create a centered floating window
   * const win = vim.api.openWin(buf, false, {
   *   relative: 'editor',
   *   row: 10,
   *   col: 20,
   *   width: 40,
   *   height: 10,
   *   border: 'rounded',
   *   title: 'My Window'
   * });
   */
  openWin(buffer: Buffer, enter: boolean, config: FloatingWinConfig): Window;

  /**
   * Update the configuration of a floating window.
   *
   * @param window - Window handle
   * @param config - New configuration options (only specified fields are updated)
   *
   * @example
   * // Move a floating window
   * vim.api.winSetConfig(win, { row: 5, col: 10 });
   *
   * // Resize and add a border
   * vim.api.winSetConfig(win, { width: 30, height: 15, border: 'single' });
   */
  winSetConfig(window: Window, config: Partial<FloatingWinConfig>): void;

  /**
   * Get the configuration of a floating window.
   *
   * @param window - Window handle
   * @returns Floating window configuration, or null if not a floating window
   *
   * @example
   * const config = vim.api.winGetConfig(win);
   * if (config) {
   *   console.log('Window is at:', config.row, config.col);
   * }
   */
  winGetConfig(window: Window): FloatingWinConfig | null;

  /**
   * Hide a floating window without destroying it.
   *
   * The window can be shown again by updating its configuration.
   * This is more efficient than closing and recreating the window.
   *
   * @param window - Window handle
   *
   * @example
   * // Hide the window
   * vim.api.winHide(win);
   *
   * // Show it again later
   * vim.api.winSetConfig(win, { hide: false });
   */
  winHide(window: Window): void;

  // === Tabpage Functions ===

  /** Get current tabpage */
  getCurrentTabpage(): Tabpage;

  /** Set current tabpage */
  setCurrentTabpage(tabpage: Tabpage): void;

  /** List all tabpages */
  listTabpages(): Tabpage[];

  // === Option Functions ===

  /** Get option value */
  getOption(name: string): any;

  /** Set option value */
  setOption(name: string, value: any): void;

  /** Get buffer option value */
  bufGetOption(buffer: Buffer, name: string): any;

  /** Set buffer option value */
  bufSetOption(buffer: Buffer, name: string, value: any): void;

  /** Get window option value */
  winGetOption(window: Window, name: string): any;

  /** Set window option value */
  winSetOption(window: Window, name: string, value: any): void;

  // === Variable Functions ===

  /** Get global variable */
  getVar(name: string): any;

  /** Set global variable */
  setVar(name: string, value: any): void;

  /** Delete global variable */
  delVar(name: string): void;

  /** Get buffer variable */
  bufGetVar(buffer: Buffer, name: string): any;

  /** Set buffer variable */
  bufSetVar(buffer: Buffer, name: string, value: any): void;

  // === Keymap Functions ===

  /** Set global keymap */
  setKeymap(mode: string, lhs: string, rhs: string, opts: any): void;

  /** Delete global keymap */
  delKeymap(mode: string, lhs: string): void;

  /** Get keymaps */
  getKeymap(mode: string): any[];

  /** Set buffer keymap */
  bufSetKeymap(buffer: Buffer, mode: string, lhs: string, rhs: string, opts: any): void;

  /** Delete buffer keymap */
  bufDelKeymap(buffer: Buffer, mode: string, lhs: string): void;

  // === Highlight Functions ===

  /** Set highlight group */
  setHighlight(namespace: Namespace, name: string, val: HighlightOpts): void;

  /** Get highlight group */
  getHighlight(namespace: Namespace, opts: { name?: string; id?: number; link?: boolean }): Record<string, any>;

  /** Set buffer highlight (extmark-based) */
  bufAddHighlight(buffer: Buffer, nsId: Namespace, hlGroup: string, line: number, colStart: number, colEnd: number): number;

  /** Clear namespace highlights */
  bufClearNamespace(buffer: Buffer, nsId: Namespace, lineStart: number, lineEnd: number): void;

  // === Extmark Functions ===

  /**
   * Create or update an extmark.
   *
   * Extmarks are buffer annotations that track positions across edits.
   * They can be used for highlighting, virtual text, diagnostics, etc.
   *
   * @param buffer - Buffer handle (0 for current)
   * @param nsId - Namespace ID from `createNamespace()`
   * @param line - Line number (0-indexed)
   * @param col - Column number (0-indexed, byte offset)
   * @param opts - Extmark options
   * @returns Extmark ID
   *
   * @example
   * const ns = vim.api.createNamespace('my-plugin');
   *
   * // Simple extmark
   * const id = vim.api.bufSetExtmark(0, ns, 0, 0, {});
   *
   * // Extmark with highlight
   * vim.api.bufSetExtmark(0, ns, 0, 5, {
   *   endLine: 0,
   *   endCol: 10,
   *   hlGroup: 'Search'
   * });
   *
   * // Update existing extmark
   * vim.api.bufSetExtmark(0, ns, 2, 0, { id: existingId });
   */
  bufSetExtmark(buffer: Buffer, nsId: Namespace, line: number, col: number, opts: ExtmarkOpts): ExtmarkID;

  /**
   * Get extmarks in a range.
   *
   * @param buffer - Buffer handle (0 for current)
   * @param nsId - Namespace ID
   * @param start - Start position (0, -1, [line, col], or extmark ID)
   * @param end - End position (0, -1, [line, col], or extmark ID)
   * @param opts - Query options
   * @returns Array of extmarks: `[id, line, col]` or `[id, line, col, details]` if `details: true`
   *
   * @example
   * // Get all extmarks in namespace
   * const marks = vim.api.bufGetExtmarks(0, ns, 0, -1, {});
   *
   * // Get extmarks with details
   * const marks = vim.api.bufGetExtmarks(0, ns, 0, -1, { details: true });
   * for (const [id, line, col, details] of marks) {
   *   console.log(`Extmark ${id} at ${line}:${col}, hl: ${details.hlGroup}`);
   * }
   *
   * // Get first 5 extmarks starting from line 10
   * const marks = vim.api.bufGetExtmarks(0, ns, [10, 0], -1, { limit: 5 });
   */
  bufGetExtmarks(
    buffer: Buffer,
    nsId: Namespace,
    start: ExtmarkPosition,
    end: ExtmarkPosition,
    opts?: ExtmarkGetOpts
  ): [ExtmarkID, number, number][] | [ExtmarkID, number, number, ExtmarkDetails][];

  /**
   * Delete an extmark.
   *
   * @param buffer - Buffer handle (0 for current)
   * @param nsId - Namespace ID
   * @param id - Extmark ID to delete
   * @returns `true` if extmark was found and deleted, `false` otherwise
   *
   * @example
   * const deleted = vim.api.bufDelExtmark(0, ns, extmarkId);
   */
  bufDelExtmark(buffer: Buffer, nsId: Namespace, id: ExtmarkID): boolean;

  /**
   * Get extmark by ID.
   *
   * @param buffer - Buffer handle (0 for current)
   * @param nsId - Namespace ID
   * @param id - Extmark ID
   * @param opts - Query options
   * @returns `[line, col]` or `[line, col, details]` if found, `null` if not found
   *
   * @example
   * // Get position only
   * const result = vim.api.bufGetExtmarkById(0, ns, extmarkId, {});
   * if (result) {
   *   const [line, col] = result;
   *   console.log(`Extmark at ${line}:${col}`);
   * }
   *
   * // Get position with details
   * const result = vim.api.bufGetExtmarkById(0, ns, extmarkId, { details: true });
   * if (result) {
   *   const [line, col, details] = result;
   *   console.log(`Extmark at ${line}:${col}, hl: ${details.hlGroup}`);
   * }
   */
  bufGetExtmarkById(
    buffer: Buffer,
    nsId: Namespace,
    id: ExtmarkID,
    opts?: ExtmarkGetOpts
  ): [number, number] | [number, number, ExtmarkDetails] | null;

  // === Autocommand Functions ===

  /** Create autocommand */
  createAutocmd(event: AutocmdEvent | AutocmdEvent[], opts: AutocmdOpts): AutocmdID;

  /** Delete autocommand by ID */
  delAutocmd(id: AutocmdID): void;

  /** Create augroup */
  createAugroup(name: string, opts: AugroupOpts): number;

  /** Clear autocmds in augroup */
  clearAutocmds(opts: { group?: string | number; event?: string | string[]; buffer?: number }): void;

  // === User Command Functions ===

  /** Create user command */
  createUserCmd(name: string, command: string | ((args: UserCommandCallbackArgs) => void), opts: UserCommandOpts): void;

  /** Delete user command */
  delUserCmd(name: string): void;

  /** Create buffer-local user command */
  bufCreateUserCmd(buffer: Buffer, name: string, command: string | ((args: UserCommandCallbackArgs) => void), opts: UserCommandOpts): void;

  /** Delete buffer-local user command */
  bufDelUserCmd(buffer: Buffer, name: string): void;

  // === Command Execution ===

  /** Execute Ex command */
  command(command: string): void;

  /** Execute Lua code (or JS code in Vimcraft context) */
  execLua(code: string, args: any[]): any;

  // === Namespace Functions ===

  /** Create namespace */
  createNamespace(name: string): Namespace;

  /** Get namespaces */
  getNamespaces(): Record<string, Namespace>;

  // === Misc Functions ===

  /** Call Vimscript function */
  callFunction(fname: string, args: any[]): any;

  /** Evaluate Vimscript expression */
  eval(expr: string): any;

  /** Get mode */
  getMode(): { mode: string; blocking: boolean };

  /** Notify user */
  notify(msg: string, logLevel: number, opts: any): void;

  /** Echo message */
  echo(chunks: Array<[string, string?]>, history: boolean, opts: any): void;

  /** Get runtime files */
  getRuntimeFile(name: string, all: boolean): string[];
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

  /**
   * Get current working directory
   * @returns The current working directory path
   * @example
   * const cwd = vim.fn.getCwd();
   * console.log('Working in:', cwd);
   */
  getCwd(): string;

  /**
   * Check if command exists in PATH
   * @param cmd - Command name to check
   * @returns 1 if executable exists, 0 otherwise
   * @example
   * if (vim.fn.executable('node')) {
   *   console.log('Node.js is installed');
   * }
   */
  executable(cmd: string): number;

  /** Get character at cursor */
  getchar(): number;

  /** Get character from position */
  getcharpos(expr: string): [number, number, number, number];

  /**
   * Check if file exists and is readable
   * @param file - File path to check
   * @returns 1 if file exists and is readable, 0 otherwise
   * @example
   * if (vim.fn.filereadable('/path/to/file')) {
   *   console.log('File exists and is readable');
   * }
   */
  filereadable(file: string): number;

  /**
   * Check if path is a directory
   * @param path - Path to check
   * @returns 1 if path is a directory, 0 otherwise
   * @example
   * if (vim.fn.isdirectory('/path/to/dir')) {
   *   console.log('Path is a directory');
   * }
   */
  isdirectory(path: string): number;

  /**
   * Modify filename according to modifiers
   * @param path - File path to modify
   * @param mods - Modifiers string (e.g., ':p:h', ':t:r', ':e')
   * @returns Modified path
   *
   * Modifiers:
   * - `:p` - Full path (make absolute)
   * - `:h` - Head (directory part)
   * - `:t` - Tail (filename part)
   * - `:r` - Root (remove extension)
   * - `:e` - Extension only
   *
   * @example
   * // Get directory of a path
   * const dir = vim.fn.fnamemodify('/path/to/file.txt', ':h');
   * // Returns: '/path/to'
   *
   * // Get filename without extension
   * const name = vim.fn.fnamemodify('/path/to/file.txt', ':t:r');
   * // Returns: 'file'
   *
   * // Get extension
   * const ext = vim.fn.fnamemodify('file.txt', ':e');
   * // Returns: 'txt'
   */
  fnamemodify(path: string, mods: string): string;

  /**
   * Get line content by line number
   * @param lnum - Line number (1-indexed), '.' for current line, '$' for last line
   * @returns Line content as string, or empty string if line doesn't exist
   * @example
   * // Get first line
   * const line1 = vim.fn.getline(1);
   *
   * // Get current line
   * const current = vim.fn.getline('.');
   *
   * // Get last line
   * const last = vim.fn.getline('$');
   */
  getline(lnum: number | '.' | '$'): string;

  /** Get file type */
  getftype(fname: string): string;

  /** Simplify file path */
  simplify(path: string): string;

  /** Join path components */
  join(list: string[], sep: string): string;

  /** Split string */
  split(string: string, pattern: string): string[];

  // === Search Register Functions ===

  /**
   * Get the contents of a register
   * @param regname - Register name (e.g., '/', '"', 'a')
   * @returns Register contents as string, empty string if not found
   *
   * Currently supported registers:
   * - `/` - Last search pattern
   *
   * @example
   * // Get current search pattern
   * const pattern = vim.fn.getReg('/');
   * console.log('Searching for:', pattern);
   */
  getReg(regname: string): string;

  /**
   * Set the contents of a register
   * @param regname - Register name (e.g., '/', '"', 'a')
   * @param value - Value to set
   *
   * Currently supported registers:
   * - `/` - Set search pattern (triggers search highlighting)
   *
   * @example
   * // Set search pattern programmatically
   * vim.fn.setReg('/', 'TODO');
   * // Now 'n' and 'N' will navigate to TODO matches
   */
  setReg(regname: string, value: string): void;

  /**
   * Search for a pattern in the buffer
   * @param pattern - Search pattern
   * @param flags - Optional search flags (not yet implemented)
   * @returns Line number if found, 0 if not found
   *
   * @example
   * const found = vim.fn.search('function');
   * if (found > 0) {
   *   console.log('Found on line:', found);
   * }
   */
  search(pattern: string, flags?: string): number;

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
 * Writable stream for subprocess stdin
 */
/**
 * Writable stdin stream for a child process.
 *
 * Provides methods to write data to the subprocess stdin and signal EOF.
 * This interface is only available when the process was spawned with
 * `stdin: 'pipe'` (the default).
 *
 * @example
 * ```typescript
 * const proc = process.spawn('cat');
 * proc.stdin.write('Hello, ');
 * proc.stdin.write('World!\n');
 * proc.stdin.end();  // Signal EOF
 * ```
 *
 * @see {@link ChildProcess} - Parent interface
 * @see {@link SpawnOptions.stdin} - Control stdin mode
 */
export interface ChildProcessStdin {
  /**
   * Write string data to the subprocess stdin.
   *
   * Data is written asynchronously. Multiple writes are queued and sent
   * in order. Returns immediately without waiting for the write to complete.
   *
   * **Note**: If the process was spawned with `stdin: 'null'`, this method
   * returns false and has no effect.
   *
   * @param data - String data to write to stdin
   * @returns `true` if the write was queued successfully, `false` if stdin
   *          is not available or the process has exited
   *
   * @example
   * ```typescript
   * // Simple write
   * proc.stdin.write('hello\n');
   *
   * // Multiple writes (sent in order)
   * proc.stdin.write('line 1\n');
   * proc.stdin.write('line 2\n');
   * proc.stdin.write('line 3\n');
   *
   * // JSON-RPC style protocol (like LSP)
   * const message = JSON.stringify({ jsonrpc: '2.0', method: 'initialize' });
   * proc.stdin.write(`Content-Length: ${message.length}\r\n\r\n${message}`);
   * ```
   */
  write(data: string): boolean;

  /**
   * Close stdin, signaling EOF to the subprocess.
   *
   * Many CLI tools read from stdin until EOF before processing. This method
   * closes the stdin pipe, which sends EOF to the subprocess, triggering
   * it to process any buffered input.
   *
   * **Common Use Cases**:
   * - Code formatters (prettier, black, gofmt) that read source from stdin
   * - Compilers that accept input via stdin
   * - Tools that process piped input (grep, sed, awk)
   * - Any program that uses `read()` until EOF
   *
   * **Important**: After calling `end()`, further `write()` calls will fail.
   *
   * @returns `true` if stdin was closed successfully, `false` if already
   *          closed or stdin is not available
   *
   * @example
   * ```typescript
   * // Format code with prettier
   * const prettier = process.spawn('prettier', ['--stdin-filepath', 'file.ts']);
   * prettier.onStdout((formatted) => {
   *   vim.api.bufSetLines(0, 0, -1, false, formatted.split('\n'));
   * });
   * prettier.stdin.write(vim.api.bufGetLines(0, 0, -1, false).join('\n'));
   * prettier.stdin.end();  // Prettier now processes and outputs
   *
   * // Pipe JSON to jq
   * const jq = process.spawn('jq', ['.']);
   * jq.stdin.write('{"name": "test", "value": 42}');
   * jq.stdin.end();  // jq parses and pretty-prints the JSON
   *
   * // Compile TypeScript from stdin
   * const tsc = process.spawn('tsc', ['--outFile', '/dev/stdout']);
   * tsc.stdin.write(sourceCode);
   * tsc.stdin.end();  // tsc compiles and outputs JavaScript
   * ```
   */
  end(): boolean;
}

/**
 * Child process handle returned by `process.spawn()`.
 *
 * Represents a running subprocess with bidirectional stdio communication.
 * Use this handle to:
 * - Write to the process stdin
 * - Receive stdout/stderr output via callbacks
 * - Monitor process exit
 * - Send signals to terminate or control the process
 *
 * ## Lifecycle
 *
 * ```
 * spawn() → ChildProcess created → callbacks registered
 *                      ↓
 *              stdin.write() / stdin.end()
 *                      ↓
 *              onStdout/onStderr callbacks fire
 *                      ↓
 *              Process exits → onExit callback fires
 *                      ↓
 *              ChildProcess handle becomes inactive
 * ```
 *
 * ## Example: LSP Server Communication
 *
 * ```typescript
 * const lsp = process.spawn('typescript-language-server', ['--stdio']);
 *
 * // Handle responses
 * lsp.onStdout((data) => {
 *   const messages = parseJsonRpcMessages(data);
 *   messages.forEach(handleLspResponse);
 * });
 *
 * // Handle errors
 * lsp.onStderr((error) => {
 *   console.error('LSP error:', error);
 * });
 *
 * // Handle exit
 * lsp.onExit((code, signal) => {
 *   if (code !== 0) {
 *     vim.api.echoError(`LSP crashed: code=${code}, signal=${signal}`);
 *   }
 * });
 *
 * // Send initialize request
 * const request = JSON.stringify({
 *   jsonrpc: '2.0',
 *   id: 1,
 *   method: 'initialize',
 *   params: { capabilities: {} }
 * });
 * lsp.stdin.write(`Content-Length: ${request.length}\r\n\r\n${request}`);
 * ```
 *
 * @see {@link SpawnOptions} - Options for spawning
 * @see {@link ChildProcessStdin} - stdin interface
 * @since 0.7.0
 */
export interface ChildProcess {
  /**
   * Process ID (PID) of the spawned subprocess.
   *
   * The PID is assigned by the operating system and uniquely identifies
   * the process. It's available immediately after `spawn()` returns.
   *
   * **Use Cases**:
   * - Logging/debugging which process is running
   * - Sending signals via external tools (`kill` command)
   * - Monitoring via external process managers
   *
   * @example
   * ```typescript
   * const proc = process.spawn('long-running-task');
   * console.log(`Started process with PID: ${proc.pid}`);
   *
   * // Log PID for external monitoring
   * vim.fn.writefile([`${proc.pid}`], '/tmp/my-process.pid');
   * ```
   */
  readonly pid: number;

  /**
   * Writable stdin stream for sending data to the subprocess.
   *
   * This property is always present, but `write()` will return false if
   * the process was spawned with `stdin: 'null'`.
   *
   * @see {@link ChildProcessStdin} - Full stdin interface documentation
   *
   * @example
   * ```typescript
   * // Write and close
   * proc.stdin.write('input data\n');
   * proc.stdin.end();
   *
   * // Check if write succeeded
   * if (!proc.stdin.write(data)) {
   *   console.error('Failed to write to stdin');
   * }
   * ```
   */
  readonly stdin: ChildProcessStdin;

  /**
   * Send a signal to the subprocess.
   *
   * Signals are used to control or terminate processes. Common signals:
   *
   * | Signal | Number | Description |
   * |--------|--------|-------------|
   * | SIGTERM | 15 | Graceful termination (default) |
   * | SIGKILL | 9 | Immediate termination (cannot be caught) |
   * | SIGINT | 2 | Interrupt (like Ctrl+C) |
   * | SIGHUP | 1 | Hangup (reload config in some programs) |
   * | SIGUSR1 | 10 | User-defined signal 1 |
   * | SIGUSR2 | 12 | User-defined signal 2 |
   *
   * **Best Practice**: Use SIGTERM first to allow graceful shutdown.
   * Only use SIGKILL if the process doesn't respond to SIGTERM.
   *
   * @param signal - Signal to send. Can be:
   *   - Signal name: `'SIGTERM'`, `'SIGKILL'`, `'SIGINT'`, `'TERM'`, `'KILL'`
   *   - Signal number: `15`, `9`, `2` (1-31)
   *   - Omitted: defaults to SIGTERM (15)
   *
   * @returns `true` if signal was sent successfully, `false` if process
   *          has already exited or signal failed
   *
   * @example
   * ```typescript
   * // Graceful termination (default)
   * proc.kill();  // Sends SIGTERM
   *
   * // Explicit signal by name
   * proc.kill('SIGTERM');  // Graceful
   * proc.kill('SIGKILL');  // Forceful
   * proc.kill('SIGINT');   // Interrupt
   *
   * // Signal by number
   * proc.kill(15);  // SIGTERM
   * proc.kill(9);   // SIGKILL
   *
   * // Graceful shutdown with fallback
   * proc.kill('SIGTERM');
   * setTimeout(() => {
   *   if (!processExited) {
   *     proc.kill('SIGKILL');  // Force kill if still running
   *   }
   * }, 5000);
   * ```
   */
  kill(signal?: number | string): boolean;

  /**
   * Register a callback for stdout data from the subprocess.
   *
   * **Streaming Mode** (default):
   * The callback is called multiple times as output arrives. Each call
   * receives a chunk of data (size varies based on OS buffering).
   *
   * **Buffered Mode** (`stdoutBuffered: true`):
   * The callback is called once after the process exits, with all
   * stdout data concatenated into a single string.
   *
   * **Important**: Register callbacks before writing to stdin or the
   * process may produce output before you're ready to receive it.
   *
   * @param callback - Function called with stdout data string
   *
   * @example
   * ```typescript
   * // Streaming mode - accumulate output
   * let output = '';
   * proc.onStdout((chunk) => {
   *   output += chunk;
   *   // Optionally process chunks as they arrive
   *   if (chunk.includes('READY')) {
   *     console.log('Process is ready');
   *   }
   * });
   *
   * // Buffered mode - single callback
   * const proc = process.spawn('cmd', [], { stdoutBuffered: true });
   * proc.onStdout((completeOutput) => {
   *   // This is called once with all output
   *   const result = JSON.parse(completeOutput);
   * });
   *
   * // Real-time logging
   * proc.onStdout((data) => {
   *   vim.api.echo(data.trimEnd());
   * });
   * ```
   */
  onStdout(callback: (data: string) => void): void;

  /**
   * Register a callback for stderr data from the subprocess.
   *
   * Works identically to `onStdout()` but for the stderr stream.
   * Many programs write error messages, warnings, and diagnostic
   * information to stderr.
   *
   * **Note**: Some programs write non-error output to stderr (e.g.,
   * progress indicators, debug info). Don't assume stderr means failure.
   *
   * @param callback - Function called with stderr data string
   *
   * @example
   * ```typescript
   * // Log errors
   * proc.onStderr((error) => {
   *   console.error('Process error:', error);
   * });
   *
   * // Collect all errors
   * let errors = '';
   * proc.onStderr((chunk) => {
   *   errors += chunk;
   * });
   * proc.onExit((code) => {
   *   if (code !== 0 && errors) {
   *     vim.api.echoError(errors);
   *   }
   * });
   *
   * // Buffered stderr for parsing
   * const proc = process.spawn('eslint', ['.'], { stderrBuffered: true });
   * proc.onStderr((allErrors) => {
   *   const diagnostics = parseEslintOutput(allErrors);
   *   showDiagnostics(diagnostics);
   * });
   * ```
   */
  onStderr(callback: (data: string) => void): void;

  /**
   * Register a callback for process exit.
   *
   * Called when the subprocess terminates, either normally or due to
   * a signal. This is guaranteed to be called exactly once for every
   * spawned process.
   *
   * **Exit Code Meanings**:
   * - `0`: Success (by convention)
   * - `1-125`: Program-defined error codes
   * - `124`: Timeout (when using `timeout` option)
   * - `126`: Command found but not executable
   * - `127`: Command not found
   * - `128+N`: Killed by signal N (e.g., 137 = 128+9 = SIGKILL)
   *
   * **Signal Values**:
   * When a process is killed by a signal, `signal` contains the signal
   * name (e.g., `'SIGTERM'`, `'SIGKILL'`). If the process exited normally,
   * `signal` is `null`.
   *
   * @param callback - Function called with exit code and signal
   *   - `code`: Exit code (integer, 0-255)
   *   - `signal`: Signal name if killed by signal, `null` otherwise
   *
   * @example
   * ```typescript
   * // Basic exit handling
   * proc.onExit((code, signal) => {
   *   if (code === 0) {
   *     console.log('Process completed successfully');
   *   } else if (signal) {
   *     console.log(`Process killed by ${signal}`);
   *   } else {
   *     console.log(`Process failed with code ${code}`);
   *   }
   * });
   *
   * // Handle timeout
   * const proc = process.spawn('slow-cmd', [], { timeout: 5000 });
   * proc.onExit((code) => {
   *   if (code === 124) {
   *     vim.api.echoWarning('Command timed out');
   *   }
   * });
   *
   * // Comprehensive error handling
   * proc.onExit((code, signal) => {
   *   switch (code) {
   *     case 0:
   *       onSuccess();
   *       break;
   *     case 124:
   *       onTimeout();
   *       break;
   *     case 127:
   *       vim.api.echoError('Command not found');
   *       break;
   *     default:
   *       if (signal === 'SIGKILL') {
   *         vim.api.echoError('Process was force-killed');
   *       } else {
   *         onError(code);
   *       }
   *   }
   * });
   * ```
   */
  onExit(callback: (code: number, signal: string | null) => void): void;

  /**
   * **[PLANNED - Phase 5a]** Resize the PTY terminal dimensions.
   *
   * Only available when the process was spawned with `pty: true`.
   * Sends SIGWINCH to notify the subprocess of the new terminal size.
   *
   * **Neovim Compatibility**: Matches `jobsend()` with resize command or
   * `chanresize(chan, rows, cols)`.
   *
   * @param rows - New terminal height in character rows
   * @param cols - New terminal width in character columns
   * @returns true if resize succeeded, false if not in PTY mode or failed
   *
   * @example
   * ```typescript
   * // [PLANNED] Handle window resize event
   * const shell = process.spawn('/bin/bash', [], {
   *   pty: true,
   *   rows: 24,
   *   cols: 80
   * });
   *
   * // When editor window resizes
   * vim.autocmd.on('VimResized', () => {
   *   const { rows, cols } = vim.ui.getTerminalSize();
   *   shell.resize(rows, cols);
   * });
   * ```
   *
   * @since [Phase 5a - Planned]
   */
  resize?(rows: number, cols: number): boolean;
}

/**
 * Options for exec() (synchronous, Promise-based)
 */
export interface ExecOptions {
  /** Working directory for the subprocess */
  cwd?: string;
  /**
   * Environment variables for the subprocess.
   * These are merged with the current process environment unless clearEnv is true.
   */
  env?: Record<string, string>;
  /**
   * If true, do not inherit the current process environment.
   * Only the variables specified in `env` will be available to the subprocess.
   * @default false
   */
  clearEnv?: boolean;
  /**
   * How to handle stdin for the subprocess.
   * - 'pipe': Connect stdin to a pipe (default for spawn, not used for sync exec)
   * - 'null' or 'ignore': Connect stdin to /dev/null (no input)
   * @default 'pipe' for spawn, inherit for exec
   */
  stdin?: 'pipe' | 'null' | 'ignore';
}

/**
 * Options for `process.spawn()` - Async subprocess spawning with full control.
 *
 * This interface provides Neovim-compatible process spawning options including
 * timeout management, detached processes, and buffered I/O modes. These options
 * give plugin authors fine-grained control over subprocess lifecycle and I/O handling.
 *
 * ## Basic Usage
 *
 * ```typescript
 * // Simple command with working directory
 * const proc = process.spawn('npm', ['install'], { cwd: '/my/project' });
 *
 * // Command with custom environment
 * const proc = process.spawn('my-tool', [], {
 *   env: { DEBUG: 'true', API_KEY: 'secret' }
 * });
 * ```
 *
 * ## Advanced Patterns
 *
 * ### Timeout for Long-Running Commands
 * ```typescript
 * // Auto-kill after 30 seconds
 * const proc = process.spawn('slow-build', [], { timeout: 30000 });
 * proc.onExit((code) => {
 *   if (code === 124) {
 *     vim.api.notifyError('Build timed out after 30 seconds');
 *   }
 * });
 * ```
 *
 * ### Buffered Output for Formatters
 * ```typescript
 * // Collect all output before processing (ideal for formatters)
 * const prettier = process.spawn('prettier', ['--stdin-filepath', 'file.ts'], {
 *   stdoutBuffered: true  // Single callback with complete output
 * });
 * prettier.onStdout((formatted) => {
 *   // `formatted` contains the entire formatted file
 *   vim.api.bufSetLines(0, 0, -1, false, formatted.split('\n'));
 * });
 * prettier.stdin.write(currentBufferContent);
 * prettier.stdin.end();
 * ```
 *
 * ### Background Daemon
 * ```typescript
 * // Start a server that survives editor exit
 * const server = process.spawn('my-daemon', ['--port', '8080'], {
 *   detach: true,
 *   stdin: 'null'  // Daemon doesn't need stdin
 * });
 * console.log('Started daemon with PID:', server.pid);
 * ```
 *
 * @see {@link ChildProcess} - The handle returned by spawn()
 * @see {@link ExecOptions} - Options for synchronous exec()
 * @since 0.7.0
 */
export interface SpawnOptions {
  /**
   * Working directory for the subprocess.
   *
   * The subprocess will start with this directory as its current working directory.
   * If not specified, inherits the editor's current working directory.
   *
   * @example
   * ```typescript
   * // Run npm install in a specific project
   * const proc = process.spawn('npm', ['install'], {
   *   cwd: '/Users/me/projects/my-app'
   * });
   *
   * // Run git commands in a repository
   * const proc = process.spawn('git', ['status'], {
   *   cwd: vim.fn.expand('%:p:h')  // Directory of current file
   * });
   * ```
   */
  cwd?: string;

  /**
   * Environment variables for the subprocess.
   *
   * By default, these variables are **merged** with the current process environment,
   * allowing you to add or override specific variables while keeping system defaults
   * like PATH, HOME, etc.
   *
   * Set `clearEnv: true` to start with a clean environment containing only
   * the variables you specify.
   *
   * @example
   * ```typescript
   * // Add/override specific variables (PATH, HOME, etc. still available)
   * const proc = process.spawn('my-tool', [], {
   *   env: {
   *     DEBUG: 'true',
   *     NODE_ENV: 'development',
   *     MY_CONFIG: '/path/to/config'
   *   }
   * });
   *
   * // Isolated environment (only specified variables)
   * const proc = process.spawn('my-tool', [], {
   *   env: {
   *     PATH: '/usr/local/bin:/usr/bin',
   *     HOME: '/tmp',
   *     MY_VAR: 'value'
   *   },
   *   clearEnv: true
   * });
   * ```
   *
   * @see {@link clearEnv} - Control environment inheritance
   */
  env?: Record<string, string>;

  /**
   * If true, do not inherit the current process environment.
   *
   * When `clearEnv` is false (default), the subprocess inherits all environment
   * variables from the editor process, and `env` options are merged on top.
   *
   * When `clearEnv` is true, the subprocess starts with an empty environment
   * and only has access to variables explicitly specified in `env`.
   *
   * **Warning**: Many programs expect certain environment variables to exist
   * (PATH, HOME, USER, SHELL, TERM, etc.). Setting `clearEnv: true` without
   * providing these may cause unexpected behavior.
   *
   * @default false
   *
   * @example
   * ```typescript
   * // Minimal environment for security-sensitive operations
   * const proc = process.spawn('/usr/bin/gpg', ['--decrypt', 'file.gpg'], {
   *   env: {
   *     PATH: '/usr/bin',
   *     HOME: process.env.HOME,
   *     GNUPGHOME: '/secure/gnupg'
   *   },
   *   clearEnv: true  // Don't leak other env vars to gpg
   * });
   * ```
   */
  clearEnv?: boolean;

  /**
   * How to handle stdin for the subprocess.
   *
   * - `'pipe'` (default): Create a writable pipe. Use `proc.stdin.write()` to send
   *   data and `proc.stdin.end()` to signal EOF.
   *
   * - `'null'` or `'ignore'`: Connect stdin to /dev/null. The subprocess receives
   *   immediate EOF on stdin. Use for commands that don't need input.
   *
   * When stdin is `'null'`, calling `proc.stdin.write()` will return false and
   * have no effect.
   *
   * @default 'pipe'
   *
   * @example
   * ```typescript
   * // Interactive command - needs stdin pipe
   * const repl = process.spawn('node');
   * repl.stdin.write('console.log("hello")\n');
   * repl.stdin.write('.exit\n');
   *
   * // Non-interactive command - doesn't need stdin
   * const proc = process.spawn('ls', ['-la'], { stdin: 'null' });
   * // proc.stdin.write() would return false
   *
   * // Formatter - needs stdin for input, then EOF
   * const fmt = process.spawn('prettier', ['--parser', 'typescript']);
   * fmt.stdin.write(sourceCode);
   * fmt.stdin.end();  // Signal EOF so prettier processes input
   * ```
   */
  stdin?: 'pipe' | 'null' | 'ignore';

  /**
   * Timeout in milliseconds after which the process is automatically killed.
   *
   * When the timeout expires:
   * 1. SIGTERM is sent to allow graceful shutdown
   * 2. If the process doesn't exit, SIGKILL may be sent
   * 3. The exit code is set to **124** (matching Neovim's `vim.system()` convention)
   *
   * This is essential for:
   * - Preventing runaway processes from hanging the editor
   * - Build/compile commands that might infinite loop
   * - Network operations that might stall
   * - Any command where you need guaranteed termination
   *
   * **Exit Code 124**: This convention comes from the `timeout` command and is
   * also used by Neovim's `vim.system()`. It allows distinguishing timeout from
   * other failures (code 1) or success (code 0).
   *
   * @example
   * ```typescript
   * // 5 second timeout for a build command
   * const build = process.spawn('npm', ['run', 'build'], {
   *   timeout: 5000,
   *   cwd: projectRoot
   * });
   *
   * build.onExit((code, signal) => {
   *   if (code === 124) {
   *     vim.api.echoError('Build timed out after 5 seconds');
   *   } else if (code === 0) {
   *     vim.api.echo('Build succeeded');
   *   } else {
   *     vim.api.echoError(`Build failed with code ${code}`);
   *   }
   * });
   *
   * // Very short timeout for quick checks
   * const ping = process.spawn('curl', ['-s', '--max-time', '1', url], {
   *   timeout: 2000  // Kill if curl doesn't respect its own timeout
   * });
   * ```
   *
   * @see Neovim's `vim.system()` timeout behavior: https://neovim.io/doc/user/lua.html#vim.system()
   */
  timeout?: number;

  /**
   * Spawn the child process in a detached state (process group leader).
   *
   * When `detach` is true:
   * - The subprocess becomes a process group leader
   * - It can continue running after the editor exits
   * - It will NOT keep the editor's event loop alive (you can exit freely)
   * - The subprocess is automatically disowned from the editor
   *
   * **Use Cases**:
   * - Starting background daemons or servers
   * - Launching external applications that should outlive the editor
   * - Running long build processes that should continue if editor crashes
   *
   * **Important Notes**:
   * - You can still receive `onExit` callbacks if the process exits while editor runs
   * - `kill()` still works on detached processes
   * - Consider using `stdin: 'null'` for detached processes that don't need input
   *
   * @default false
   *
   * @example
   * ```typescript
   * // Start a development server that survives editor exit
   * const server = process.spawn('npm', ['run', 'dev'], {
   *   cwd: projectRoot,
   *   detach: true,
   *   stdin: 'null'
   * });
   * console.log(`Dev server started with PID ${server.pid}`);
   * // Editor can exit, server keeps running
   *
   * // Start a file watcher daemon
   * const watcher = process.spawn('fswatch', ['-r', '.'], {
   *   detach: true,
   *   stdin: 'null'
   * });
   * // Watcher continues even if editor closes
   *
   * // Note: You can still kill it manually
   * server.kill('SIGTERM');
   * ```
   */
  detach?: boolean;

  /**
   * Buffer all stdout data until EOF before delivering to callback.
   *
   * **Streaming Mode** (default, `stdoutBuffered: false`):
   * - `onStdout` is called multiple times as data arrives
   * - Each call receives a chunk of output (size varies)
   * - Good for real-time progress updates, logs, interactive output
   *
   * **Buffered Mode** (`stdoutBuffered: true`):
   * - `onStdout` is called **once** after process exits
   * - Single call receives the complete stdout output
   * - Good for formatters, compilers, any command where you need complete output
   *
   * **Memory Consideration**: Buffered mode accumulates all output in memory.
   * For commands that produce very large output (e.g., large file dumps),
   * streaming mode is more memory-efficient.
   *
   * @default false (streaming mode)
   *
   * @example
   * ```typescript
   * // STREAMING MODE - Real-time build output
   * const build = process.spawn('npm', ['run', 'build']);
   * build.onStdout((chunk) => {
   *   // Called multiple times with partial output
   *   vim.api.echo(chunk);  // Show progress in real-time
   * });
   *
   * // BUFFERED MODE - Code formatter
   * const prettier = process.spawn('prettier', ['--stdin-filepath', 'file.ts'], {
   *   stdoutBuffered: true
   * });
   * prettier.onStdout((completeOutput) => {
   *   // Called ONCE with entire formatted file
   *   const lines = completeOutput.trimEnd().split('\n');
   *   vim.api.bufSetLines(0, 0, -1, false, lines);
   * });
   * prettier.stdin.write(vim.api.bufGetLines(0, 0, -1, false).join('\n'));
   * prettier.stdin.end();
   *
   * // BUFFERED MODE - JSON output from CLI tool
   * const cli = process.spawn('my-tool', ['--json'], {
   *   stdoutBuffered: true
   * });
   * cli.onStdout((json) => {
   *   const data = JSON.parse(json);  // Safe - we have complete JSON
   *   processData(data);
   * });
   * ```
   *
   * @see {@link stderrBuffered} - Same concept for stderr
   */
  stdoutBuffered?: boolean;

  /**
   * Buffer all stderr data until EOF before delivering to callback.
   *
   * Works identically to `stdoutBuffered` but for the stderr stream.
   *
   * **Streaming Mode** (default, `stderrBuffered: false`):
   * - `onStderr` is called multiple times as errors/warnings arrive
   * - Good for real-time error reporting during long operations
   *
   * **Buffered Mode** (`stderrBuffered: true`):
   * - `onStderr` is called **once** after process exits
   * - Single call receives all stderr output
   * - Good when you need to parse complete error output
   *
   * @default false (streaming mode)
   *
   * @example
   * ```typescript
   * // STREAMING MODE - Show compiler errors in real-time
   * const compile = process.spawn('tsc', ['--noEmit']);
   * compile.onStderr((error) => {
   *   vim.api.echoError(error);  // Show each error as it's found
   * });
   *
   * // BUFFERED MODE - Collect all linter warnings
   * const lint = process.spawn('eslint', ['.', '--format', 'json'], {
   *   stderrBuffered: true
   * });
   * lint.onStderr((allErrors) => {
   *   // Parse complete error output as JSON
   *   const errors = JSON.parse(allErrors);
   *   populateDiagnostics(errors);
   * });
   *
   * // BOTH BUFFERED - Complete capture for analysis
   * const tool = process.spawn('my-tool', [], {
   *   stdoutBuffered: true,
   *   stderrBuffered: true
   * });
   * let stdout = '', stderr = '';
   * tool.onStdout((data) => { stdout = data; });
   * tool.onStderr((data) => { stderr = data; });
   * tool.onExit((code) => {
   *   // Both stdout and stderr are complete here
   *   analyzeOutput(stdout, stderr, code);
   * });
   * ```
   *
   * @see {@link stdoutBuffered} - Same concept for stdout
   */
  stderrBuffered?: boolean;

}

// ============================================================================
// PTY (Pseudo-Terminal) Process - Phase 5a
// ============================================================================

/**
 * Options for spawning a process in PTY (pseudo-terminal) mode.
 *
 * PTY mode enables proper terminal emulation for interactive CLI tools like
 * `fzf`, `htop`, shells, and other TUI programs that require raw terminal access.
 *
 * **Key Differences from `SpawnOptions`**:
 * - Stdin/stdout/stderr are merged into a single bidirectional PTY stream
 * - Supports terminal resize via `resize(rows, cols)`
 * - Handles terminal signals (SIGWINCH, SIGINT via Ctrl+C, etc.)
 * - Programs see a real TTY (isatty() returns true)
 *
 * @since Phase 5a
 */
export interface SpawnPtyOptions {
  /**
   * Working directory for the subprocess.
   *
   * @example
   * ```typescript
   * const shell = process.spawnPty('/bin/zsh', [], { cwd: '/home/user/projects' });
   * ```
   */
  cwd?: string;

  /**
   * Environment variables for the subprocess.
   *
   * By default, merged with the current process environment.
   * Set `clearEnv: true` to start with only the specified variables.
   *
   * @example
   * ```typescript
   * const shell = process.spawnPty('/bin/bash', [], {
   *   env: { TERM: 'xterm-256color', COLORTERM: 'truecolor' }
   * });
   * ```
   */
  env?: Record<string, string>;

  /**
   * If true, do not inherit the current process environment.
   *
   * @default false
   */
  clearEnv?: boolean;

  /**
   * Initial number of rows (height) for the PTY.
   *
   * This sets the terminal height in character rows. Can be changed later
   * via `pty.resize(rows, cols)`.
   *
   * @default 24
   *
   * @example
   * ```typescript
   * // Small terminal for popup picker
   * const fzf = process.spawnPty('fzf', [], { rows: 10, cols: 60 });
   *
   * // Full-size terminal
   * const shell = process.spawnPty('/bin/zsh', [], { rows: 40, cols: 120 });
   * ```
   */
  rows?: number;

  /**
   * Initial number of columns (width) for the PTY.
   *
   * This sets the terminal width in character columns. Can be changed later
   * via `pty.resize(rows, cols)`.
   *
   * @default 80
   */
  cols?: number;

  /**
   * TERM environment variable value for the PTY.
   *
   * This tells programs what terminal capabilities are available.
   * Common values: `'xterm-256color'`, `'screen-256color'`, `'vt100'`.
   *
   * @default 'xterm-256color'
   *
   * @example
   * ```typescript
   * // Force basic terminal for compatibility
   * const shell = process.spawnPty('/bin/sh', [], { term: 'vt100' });
   * ```
   */
  term?: string;

  /**
   * Timeout in milliseconds after which the process is automatically killed.
   *
   * When the timeout expires, the process is terminated and the exit code
   * is set to 124 (matching Neovim's convention).
   *
   * @example
   * ```typescript
   * // 30 second timeout for interactive command
   * const fzf = process.spawnPty('fzf', [], { timeout: 30000 });
   * ```
   */
  timeout?: number;
}

/**
 * Handle for a process running in PTY (pseudo-terminal) mode.
 *
 * Unlike `ChildProcess` which has separate stdin/stdout/stderr streams,
 * `PtyProcess` has a single bidirectional data stream that combines all I/O.
 * This matches how real terminals work.
 *
 * **Use Cases**:
 * - Interactive pickers (`fzf`, `sk`)
 * - TUI applications (`htop`, `vim`, `less`)
 * - Shell sessions
 * - Any program that requires a real TTY
 *
 * @since Phase 5a
 *
 * @example
 * ```typescript
 * // Run fzf as a file picker
 * const fzf = process.spawnPty('fzf', ['--height', '40%']);
 *
 * let output = '';
 * fzf.onData((data) => {
 *   output += data;
 *   // Render terminal output to a floating window
 * });
 *
 * fzf.onExit((code) => {
 *   if (code === 0) {
 *     const selectedFile = output.trim();
 *     vim.cmd.edit(selectedFile);
 *   }
 * });
 *
 * // Handle keyboard input from user
 * vim.keymap.set('t', '<C-c>', () => fzf.kill('SIGINT'));
 * ```
 */
export interface PtyProcess {
  /**
   * Process ID (PID) of the spawned subprocess.
   *
   * @example
   * ```typescript
   * const shell = process.spawnPty('/bin/zsh');
   * console.log(`Shell PID: ${shell.pid}`);
   * ```
   */
  readonly pid: number;

  /**
   * Write data to the PTY (send input to the process).
   *
   * This is the equivalent of typing on a keyboard in a terminal.
   * The data is sent directly to the process's stdin through the PTY.
   *
   * @param data - String data to write (can include escape sequences)
   * @returns `true` if write succeeded, `false` otherwise
   *
   * @example
   * ```typescript
   * const shell = process.spawnPty('/bin/bash');
   *
   * // Send commands
   * shell.write('ls -la\n');
   * shell.write('cd /tmp\n');
   *
   * // Send Ctrl+C (SIGINT)
   * shell.write('\x03');
   *
   * // Send Ctrl+D (EOF)
   * shell.write('\x04');
   *
   * // Send escape sequence
   * shell.write('\x1b[A');  // Up arrow
   * ```
   */
  write(data: string): boolean;

  /**
   * Resize the PTY terminal dimensions.
   *
   * This sends a SIGWINCH signal to the process, notifying it that the
   * terminal size has changed. Programs like vim, htop, and shells will
   * redraw themselves to fit the new size.
   *
   * @param rows - New number of rows (height)
   * @param cols - New number of columns (width)
   *
   * @example
   * ```typescript
   * const shell = process.spawnPty('/bin/zsh', [], { rows: 24, cols: 80 });
   *
   * // User resizes the window
   * vim.autocmd.create('VimResized', () => {
   *   const newRows = vim.api.getOption('lines');
   *   const newCols = vim.api.getOption('columns');
   *   shell.resize(newRows - 2, newCols);  // Leave room for statusline
   * });
   * ```
   */
  resize(rows: number, cols: number): void;

  /**
   * Send a signal to the subprocess.
   *
   * @param signal - Signal to send (default: SIGTERM)
   * @returns `true` if signal was sent, `false` if process already exited
   *
   * @example
   * ```typescript
   * // Graceful termination
   * pty.kill('SIGTERM');
   *
   * // Force kill
   * pty.kill('SIGKILL');
   *
   * // Interrupt (like Ctrl+C, but bypassing PTY)
   * pty.kill('SIGINT');
   * ```
   */
  kill(signal?: number | string): boolean;

  /**
   * Register a callback for PTY data (combined stdout/stderr).
   *
   * In PTY mode, stdout and stderr are merged into a single stream,
   * just like in a real terminal. The callback receives all output
   * including ANSI escape sequences for colors, cursor movement, etc.
   *
   * @param callback - Function called when data is received
   *
   * @example
   * ```typescript
   * const htop = process.spawnPty('htop');
   *
   * htop.onData((data) => {
   *   // data includes ANSI sequences for colors, cursor positioning, etc.
   *   // Render to a terminal emulator widget or floating window
   *   terminalWidget.write(data);
   * });
   * ```
   */
  onData(callback: (data: string) => void): void;

  /**
   * Register a callback for process exit.
   *
   * @param callback - Function called when process exits
   *   - `code`: Exit code (0 = success, 124 = timeout, other = error)
   *   - `signal`: Signal name if killed by signal (e.g., 'SIGTERM'), null otherwise
   *
   * @example
   * ```typescript
   * const fzf = process.spawnPty('fzf');
   *
   * fzf.onExit((code, signal) => {
   *   if (code === 0) {
   *     // User selected something
   *   } else if (code === 130) {
   *     // User pressed Ctrl+C (128 + SIGINT=2)
   *   } else if (signal === 'SIGKILL') {
   *     // Process was force-killed
   *   }
   * });
   * ```
   */
  onExit(callback: (code: number, signal: string | null) => void): void;
}

/**
 * Process API (Node.js-style)
 * @future Phase 5+
 */
export interface Process {
  cwd(): string;
  env: Record<string, string>;
  platform: 'darwin' | 'linux' | 'windows';

  /**
   * Execute a subprocess and wait for it to complete (Promise-based)
   *
   * @example
   * ```typescript
   * // Basic usage
   * const result = await process.exec('ls', ['-la']);
   * console.log(result.stdout);
   *
   * // With custom environment
   * const result = await process.exec('env', [], {
   *   env: { MY_VAR: 'hello' }
   * });
   *
   * // With isolated environment (no inherited variables)
   * const result = await process.exec('env', [], {
   *   env: { PATH: '/usr/bin', MY_VAR: 'hello' },
   *   clearEnv: true
   * });
   * ```
   *
   * @param command - Command to execute
   * @param args - Arguments to pass to the command
   * @param options - Exec options (cwd, env, clearEnv)
   * @returns Promise resolving to stdout, stderr, and exit code
   */
  exec(command: string, args?: string[], options?: ExecOptions): Promise<{
    stdout: string;
    stderr: string;
    code: number;
  }>;

  /**
   * Spawn a long-running subprocess with bidirectional stdio communication
   * Ideal for LSP servers, language servers, and other persistent processes
   *
   * @example
   * ```typescript
   * const lsp = process.spawn('typescript-language-server', ['--stdio']);
   *
   * lsp.onStdout((data) => {
   *   console.log('LSP response:', data);
   * });
   *
   * lsp.onStderr((data) => {
   *   console.error('LSP error:', data);
   * });
   *
   * lsp.onExit((code, signal) => {
   *   console.log('LSP exited:', code, signal);
   * });
   *
   * // Send JSON-RPC request
   * const request = JSON.stringify({ jsonrpc: '2.0', method: 'initialize', ... });
   * lsp.stdin.write(`Content-Length: ${request.length}\r\n\r\n${request}`);
   *
   * // Kill when done
   * lsp.kill('SIGTERM');
   * ```
   *
   * @param command - Command to execute
   * @param args - Arguments to pass to the command
   * @param options - Spawn options (cwd, env, timeout, detach, etc.)
   * @returns ChildProcess handle with stdin, kill, and event callbacks
   */
  spawn(command: string, args?: string[], options?: SpawnOptions): ChildProcess;

  /**
   * Spawn a process in PTY (pseudo-terminal) mode for interactive programs
   *
   * PTY mode is required for programs that need a real terminal, such as:
   * - Interactive pickers: `fzf`, `sk`, `peco`
   * - TUI applications: `htop`, `vim`, `less`, `man`
   * - Shell sessions: `/bin/bash`, `/bin/zsh`
   * - Any program that checks `isatty()` or needs terminal capabilities
   *
   * **Key Differences from `spawn()`**:
   * - Single bidirectional stream (use `onData` instead of `onStdout`/`onStderr`)
   * - Supports terminal resize via `resize(rows, cols)`
   * - Process sees a real TTY (enables colors, interactive features)
   *
   * @example
   * ```typescript
   * // Interactive file picker with fzf
   * const fzf = process.spawnPty('fzf', ['--preview', 'cat {}'], {
   *   rows: 20,
   *   cols: 80
   * });
   *
   * let result = '';
   * fzf.onData((data) => {
   *   result += data;
   *   renderToFloatingWindow(data);
   * });
   *
   * fzf.onExit((code) => {
   *   if (code === 0) {
   *     vim.cmd.edit(result.trim());
   *   }
   * });
   *
   * // Forward keyboard input
   * vim.keymap.set('t', '<CR>', () => fzf.write('\r'));
   * vim.keymap.set('t', '<C-c>', () => fzf.kill('SIGINT'));
   *
   * // Shell session
   * const shell = process.spawnPty('/bin/zsh', [], {
   *   rows: 24,
   *   cols: 80,
   *   env: { TERM: 'xterm-256color' }
   * });
   *
   * shell.write('ls -la\n');
   * shell.resize(40, 120);  // Handle terminal resize
   * ```
   *
   * @param command - Command to execute
   * @param args - Arguments to pass to the command
   * @param options - PTY spawn options (rows, cols, term, etc.)
   * @returns PtyProcess handle with write, resize, kill, and event callbacks
   *
   * @since Phase 5a
   * @see Neovim's `jobstart()` with `{ pty: true }`
   */
  spawnPty(command: string, args?: string[], options?: SpawnPtyOptions): PtyProcess;
}

// ============================================================================
// LSP (Language Server Protocol)
// ============================================================================

/**
 * Options for starting an LSP client.
 *
 * @example
 * ```typescript
 * const client = await vim.lsp.start({
 *   name: 'typescript-language-server',
 *   cmd: ['typescript-language-server', '--stdio'],
 *   rootDir: '/path/to/project',
 *   capabilities: {
 *     textDocument: { completion: { snippetSupport: true } }
 *   },
 *   onAttach: (client, bufnr) => {
 *     console.log('LSP attached to buffer', bufnr);
 *   },
 * });
 * ```
 */
export interface LspClientOptions {
  /** Client name for logging and identification (default: 'lsp') */
  name?: string;

  /** Command and arguments to spawn the LSP server */
  cmd: string[];

  /** Project root directory (sent as rootUri to server) */
  rootDir?: string;

  /** Client capabilities to advertise to server */
  capabilities?: Record<string, any>;

  /** Workspace settings (sent as initializationOptions) */
  settings?: Record<string, any>;

  /** Callback when client attaches to a buffer */
  onAttach?: (client: LspClient, bufnr: number) => void;

  /** Callback when server exits */
  onExit?: (code: number, signal: string | null) => void;

  /**
   * Default request timeout in milliseconds.
   * If a request does not receive a response within this time, it will be rejected.
   * Set to 0 to disable timeout.
   * @default 30000 (30 seconds)
   */
  requestTimeout?: number;
}

/**
 * Filter options for vim.lsp.getClients().
 */
export interface LspClientFilter {
  /** Filter by attached buffer number */
  bufnr?: number;

  /** Filter by client name */
  name?: string;
}

/**
 * LSP client instance - represents a connection to an LSP server.
 *
 * Created by `vim.lsp.start()`. Provides methods for sending requests,
 * notifications, and handling server messages.
 *
 * @example
 * ```typescript
 * const client = await vim.lsp.start({
 *   name: 'tsserver',
 *   cmd: ['typescript-language-server', '--stdio'],
 *   rootDir: process.cwd(),
 * });
 *
 * // Handle diagnostics
 * client.on('textDocument/publishDiagnostics', (params) => {
 *   console.log('Diagnostics:', params.diagnostics.length);
 * });
 *
 * // Request hover info
 * const hover = await client.request('textDocument/hover', {
 *   textDocument: { uri: 'file:///path/to/file.ts' },
 *   position: { line: 10, character: 5 },
 * });
 *
 * // Send notification
 * client.notify('textDocument/didOpen', {
 *   textDocument: { uri, languageId: 'typescript', version: 1, text },
 * });
 *
 * // Stop the client
 * client.stop();
 * ```
 */
export interface LspClient {
  /** Unique client ID */
  readonly id: number;

  /** Client name */
  readonly name: string;

  /** Whether the client has completed initialization */
  readonly initialized: boolean;

  /** Whether the client is in the process of stopping */
  readonly stopping: boolean;

  /** Server capabilities received from initialize response */
  readonly serverCapabilities: Record<string, any>;

  /** List of attached buffer numbers */
  readonly attachedBuffers: number[];

  /**
   * Send a request to the LSP server and wait for response.
   *
   * @param method - LSP method name (e.g., 'textDocument/hover')
   * @param params - Request parameters
   * @returns Promise resolving to the server's response
   *
   * @example
   * ```typescript
   * const result = await client.request('textDocument/definition', {
   *   textDocument: { uri: 'file:///path/to/file.ts' },
   *   position: { line: 10, character: 5 },
   * });
   *
   * // With custom timeout
   * const result = await client.request('textDocument/completion', params, { timeout: 5000 });
   * ```
   */
  request(method: string, params?: Record<string, any>, options?: { timeout?: number }): Promise<any>;

  /**
   * Send a notification to the LSP server (fire-and-forget).
   *
   * @param method - LSP method name (e.g., 'textDocument/didOpen')
   * @param params - Notification parameters
   *
   * @example
   * ```typescript
   * client.notify('textDocument/didSave', {
   *   textDocument: { uri: 'file:///path/to/file.ts' },
   * });
   * ```
   */
  notify(method: string, params?: Record<string, any>): void;

  /**
   * Register a handler for server notifications.
   *
   * @param method - Method name to handle
   * @param callback - Handler function
   * @returns this (for chaining)
   *
   * @example
   * ```typescript
   * client.on('textDocument/publishDiagnostics', (params) => {
   *   const { uri, diagnostics } = params;
   *   console.log(`${diagnostics.length} diagnostics for ${uri}`);
   * });
   * ```
   */
  on(method: string, callback: (params: any) => void): this;

  /**
   * Check if server supports a capability.
   *
   * @param capability - Capability path (e.g., 'textDocument.hover', 'hoverProvider')
   * @returns true if server supports the capability
   *
   * @example
   * ```typescript
   * if (client.supports('hoverProvider')) {
   *   const hover = await client.request('textDocument/hover', ...);
   * }
   * ```
   */
  supports(capability: string): boolean;

  /**
   * Attach this client to a buffer.
   *
   * @param bufnr - Buffer number
   */
  attachBuffer(bufnr: number): void;

  /**
   * Detach this client from a buffer.
   *
   * @param bufnr - Buffer number
   */
  detachBuffer(bufnr: number): void;

  /**
   * Check if this client is attached to a buffer.
   *
   * @param bufnr - Buffer number
   * @returns true if client is attached to the buffer
   */
  hasBuffer(bufnr: number): boolean;

  /**
   * Stop the LSP server gracefully.
   *
   * Sends shutdown request, then exit notification. Falls back to SIGTERM
   * if shutdown fails or takes too long.
   */
  stop(): void;
}

/**
 * LSP message framer for Content-Length parsing.
 *
 * Handles the LSP message framing protocol:
 * ```
 * Content-Length: <length>\r\n
 * \r\n
 * <JSON payload>
 * ```
 *
 * @example
 * ```typescript
 * const framer = new vim.lsp.LspFramer();
 * framer.onMessage((msg) => {
 *   console.log('Received:', msg);
 * });
 *
 * // Feed raw data from stdout
 * framer.feed('Content-Length: 23\r\n\r\n{"jsonrpc":"2.0",...}');
 *
 * // Encode outgoing message
 * const encoded = vim.lsp.LspFramer.encode({ jsonrpc: '2.0', ... });
 * ```
 */
export interface LspFramerConstructor {
  new (): LspFramer;

  /**
   * Encode a message with Content-Length header.
   *
   * @param message - JSON-RPC message object
   * @returns Framed string with header
   */
  encode(message: Record<string, any>): string;
}

export interface LspFramer {
  /**
   * Set callback for complete messages.
   *
   * @param callback - Called with parsed JSON for each complete message
   */
  onMessage(callback: (message: any) => void): void;

  /**
   * Feed raw data from server stdout.
   *
   * @param data - Raw string data
   */
  feed(data: string): void;
}

/**
 * Context passed to LSP handler functions.
 */
export interface LspHandlerContext {
  /** Buffer number the request was made for */
  bufnr: number;
  /** LSP client that made the request */
  client: LspClient;
}

/**
 * LSP response handler function type.
 *
 * Handlers are called when LSP methods receive responses from the server.
 * They can be overridden to customize how results are displayed.
 *
 * @param result - The LSP response (varies by method)
 * @param ctx - Context including buffer and client info
 */
export type LspHandler = (result: any, ctx: LspHandlerContext) => void;

/**
 * vim.lsp.handlers - Customizable response handlers.
 *
 * Override these to customize how LSP results are displayed.
 * Default handlers show floating windows, jump to locations, etc.
 *
 * @example
 * ```typescript
 * // Custom hover handler with fancy formatting
 * vim.lsp.handlers['textDocument/hover'] = (result, ctx) => {
 *   if (!result?.contents) return;
 *
 *   // Custom popup implementation
 *   const text = extractHoverText(result.contents);
 *   showFancyPopup(text);
 * };
 *
 * // Disable default definition jump (handle manually)
 * vim.lsp.handlers['textDocument/definition'] = (result, ctx) => {
 *   console.log('Definition result:', result);
 *   // Custom navigation logic
 * };
 * ```
 */
export interface LspHandlers {
  /** Handler for hover results - displays floating window */
  'textDocument/hover'?: LspHandler;
  /** Handler for definition results - jumps to location */
  'textDocument/definition'?: LspHandler;
  /** Handler for references results - shows in quickfix/floating */
  'textDocument/references'?: LspHandler;
  /** Handler for signature help - shows parameter hints */
  'textDocument/signatureHelp'?: LspHandler;
  /** Handler for implementation results */
  'textDocument/implementation'?: LspHandler;
  /** Handler for type definition results */
  'textDocument/typeDefinition'?: LspHandler;
  /** Handler for code action results */
  'textDocument/codeAction'?: LspHandler;
  /** Handler for formatting results */
  'textDocument/formatting'?: LspHandler;
  /** Handler for rename results */
  'textDocument/rename'?: LspHandler;
  /** Handler for document symbol results */
  'textDocument/documentSymbol'?: LspHandler;
  /** Allow custom handlers for any method */
  [method: string]: LspHandler | undefined;
}

/**
 * vim.lsp - LSP client management interface.
 *
 * Provides high-level API for managing Language Server Protocol clients.
 * Built on top of `process.spawn()` with JSON-RPC 2.0 message framing.
 *
 * @example
 * ```typescript
 * // Start a TypeScript language server
 * const client = await vim.lsp.start({
 *   name: 'tsserver',
 *   cmd: ['typescript-language-server', '--stdio'],
 *   rootDir: '/path/to/project',
 *   onAttach: (client, bufnr) => {
 *     // Setup keymaps when LSP attaches
 *     vim.keymap.set('n', 'K', async () => {
 *       const hover = await vim.lsp.bufHover(bufnr, uri, line, col);
 *       if (hover) showHover(hover);
 *     }, { buffer: bufnr });
 *   },
 * });
 *
 * // Get all active clients
 * const clients = vim.lsp.getClients();
 *
 * // Get clients for a specific buffer
 * const bufferClients = vim.lsp.getClients({ bufnr: 0 });
 *
 * // Stop a client
 * vim.lsp.stopClient(client);
 * ```
 */
export interface LSP {
  /**
   * Start an LSP client.
   *
   * Spawns the LSP server process, performs initialize handshake,
   * and returns the client instance.
   *
   * @param opts - Client configuration
   * @returns Promise resolving to started client
   * @throws Error if spawn or initialization fails
   *
   * @example
   * ```typescript
   * const client = await vim.lsp.start({
   *   name: 'rust-analyzer',
   *   cmd: ['rust-analyzer'],
   *   rootDir: process.cwd(),
   * });
   * ```
   */
  start(opts: LspClientOptions): Promise<LspClient>;

  /**
   * Get all active LSP clients.
   *
   * @param filter - Optional filter criteria
   * @returns Array of matching clients
   *
   * @example
   * ```typescript
   * // All clients
   * const all = vim.lsp.getClients();
   *
   * // Clients attached to buffer 0
   * const forBuf = vim.lsp.getClients({ bufnr: 0 });
   *
   * // Clients by name
   * const rust = vim.lsp.getClients({ name: 'rust-analyzer' });
   * ```
   */
  getClients(filter?: LspClientFilter): LspClient[];

  /**
   * Stop an LSP client.
   *
   * @param clientOrId - Client instance or client ID
   * @param force - If true, send SIGKILL instead of graceful shutdown
   *
   * @example
   * ```typescript
   * vim.lsp.stopClient(client);
   * vim.lsp.stopClient(1, true);  // Force kill client ID 1
   * ```
   */
  stopClient(clientOrId: LspClient | number, force?: boolean): void;

  /**
   * Get client by ID.
   *
   * @param id - Client ID
   * @returns Client or undefined if not found
   */
  getClientById(id: number): LspClient | undefined;

  // ========== Buffer-level helpers ==========

  /**
   * Send textDocument/didOpen notification to all clients attached to buffer.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI (file://...)
   * @param languageId - Language identifier (e.g., 'typescript')
   * @param text - Document content
   */
  bufDidOpen(bufnr: number, uri: string, languageId: string, text: string): void;

  /**
   * Send textDocument/didChange notification to all clients attached to buffer.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   * @param version - Document version number
   * @param text - Full document text (full sync mode)
   */
  bufDidChange(bufnr: number, uri: string, version: number, text: string): void;

  /**
   * Send textDocument/didClose notification to all clients attached to buffer.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   */
  bufDidClose(bufnr: number, uri: string): void;

  /**
   * Send textDocument/didSave notification to all clients attached to buffer.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   * @param text - Document text (optional, for includeText capability)
   */
  bufDidSave(bufnr: number, uri: string, text?: string): void;

  // ========== Request helpers ==========

  /**
   * Request hover information at a position.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   * @param line - Line number (0-indexed)
   * @param character - Character offset (0-indexed)
   * @returns Hover result or null
   */
  bufHover(bufnr: number, uri: string, line: number, character: number): Promise<any>;

  /**
   * Request definition location at a position.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   * @param line - Line number (0-indexed)
   * @param character - Character offset (0-indexed)
   * @returns Definition location(s) or null
   */
  bufDefinition(bufnr: number, uri: string, line: number, character: number): Promise<any>;

  /**
   * Request references at a position.
   *
   * @param bufnr - Buffer number
   * @param uri - Document URI
   * @param line - Line number (0-indexed)
   * @param character - Character offset (0-indexed)
   * @param includeDeclaration - Include declaration in results (default: true)
   * @returns Reference locations or null
   */
  bufReferences(
    bufnr: number,
    uri: string,
    line: number,
    character: number,
    includeDeclaration?: boolean
  ): Promise<any>;

  // ========== vim.lsp.handlers namespace ==========

  /**
   * Customizable response handlers.
   *
   * Override these to customize how LSP results are displayed.
   * Default handlers show floating windows, jump to locations, etc.
   *
   * @example
   * ```typescript
   * // Custom hover handler
   * vim.lsp.handlers['textDocument/hover'] = (result, ctx) => {
   *   // Your custom popup implementation
   * };
   * ```
   */
  handlers: LspHandlers;

  // ========== vim.lsp.buf namespace ==========

  /**
   * Buffer-local LSP operations.
   *
   * Methods in this namespace operate on the current buffer at the current cursor position.
   * They automatically find attached LSP clients and send appropriate requests.
   *
   * @example
   * ```typescript
   * // Show hover info at cursor
   * vim.lsp.buf.hover();
   *
   * // Go to definition
   * vim.lsp.buf.definition();
   *
   * // Find all references
   * vim.lsp.buf.references();
   * ```
   */
  buf: LspBuf;

  // ========== Advanced ==========

  /** LspClient class for advanced use */
  LspClient: new (opts: LspClientOptions) => LspClient;

  /** LspFramer class for Content-Length message framing */
  LspFramer: LspFramerConstructor;
}

/**
 * vim.lsp.buf - Buffer-local LSP operations.
 *
 * All methods operate on the current buffer at the current cursor position.
 * Following Neovim's vim.lsp.buf pattern with camelCase naming.
 *
 * @example
 * ```typescript
 * // Map K to show hover
 * vim.keymap.set('n', 'K', () => vim.lsp.buf.hover());
 *
 * // Map gd to go to definition
 * vim.keymap.set('n', 'gd', () => vim.lsp.buf.definition());
 * ```
 */
export interface LspBuf {
  /**
   * Display hover information at the current cursor position.
   *
   * Shows documentation, type info, or other hover content from the LSP server.
   *
   * @returns Promise resolving to hover result or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', 'K', async () => {
   *   const hover = await vim.lsp.buf.hover();
   *   if (hover) {
   *     // Display hover in floating window
   *   }
   * });
   * ```
   */
  hover(): Promise<any>;

  /**
   * Jump to the definition of the symbol under cursor.
   *
   * If multiple definitions are found, may show a selection UI.
   *
   * @returns Promise resolving to definition location(s) or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', 'gd', () => vim.lsp.buf.definition());
   * ```
   */
  definition(): Promise<any>;

  /**
   * Find all references to the symbol under cursor.
   *
   * @param opts - Optional settings
   * @param opts.includeDeclaration - Include declaration in results (default: true)
   * @returns Promise resolving to reference locations or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', 'gr', () => vim.lsp.buf.references());
   * ```
   */
  references(opts?: { includeDeclaration?: boolean }): Promise<any>;

  /**
   * Show available code actions at the current cursor position.
   *
   * Code actions include quick fixes, refactorings, and source actions.
   *
   * @param opts - Optional filter options
   * @param opts.only - Only show actions of these kinds (e.g., 'quickfix', 'refactor')
   * @returns Promise resolving to available actions or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', '<leader>ca', () => vim.lsp.buf.codeAction());
   * ```
   */
  codeAction(opts?: { only?: string[] }): Promise<any>;

  /**
   * Rename the symbol under cursor.
   *
   * @param newName - New name for the symbol (prompts if not provided)
   * @returns Promise resolving when rename is complete
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', '<leader>rn', () => vim.lsp.buf.rename());
   * ```
   */
  rename(newName?: string): Promise<any>;

  /**
   * Format the current buffer using LSP formatting.
   *
   * @param opts - Optional formatting options
   * @param opts.tabSize - Size of a tab (default: from buffer options)
   * @param opts.insertSpaces - Use spaces instead of tabs
   * @returns Promise resolving to text edits or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', '<leader>f', () => vim.lsp.buf.formatting());
   * ```
   */
  formatting(opts?: { tabSize?: number; insertSpaces?: boolean }): Promise<any>;

  /**
   * Jump to the implementation of the symbol under cursor.
   *
   * For interfaces/abstract classes, jumps to implementing types.
   *
   * @returns Promise resolving to implementation location(s) or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', 'gi', () => vim.lsp.buf.implementation());
   * ```
   */
  implementation(): Promise<any>;

  /**
   * Jump to the type definition of the symbol under cursor.
   *
   * @returns Promise resolving to type definition location(s) or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', 'gt', () => vim.lsp.buf.typeDefinition());
   * ```
   */
  typeDefinition(): Promise<any>;

  /**
   * Show signature help for the current function call.
   *
   * Displays parameter hints and documentation for function arguments.
   *
   * @returns Promise resolving to signature help or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('i', '<C-k>', () => vim.lsp.buf.signatureHelp());
   * ```
   */
  signatureHelp(): Promise<any>;

  /**
   * List document symbols in the current buffer.
   *
   * Shows functions, classes, variables, etc. in the current file.
   *
   * @returns Promise resolving to document symbols or null
   *
   * @example
   * ```typescript
   * vim.keymap.set('n', '<leader>ds', () => vim.lsp.buf.documentSymbol());
   * ```
   */
  documentSymbol(): Promise<any>;
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
// E2E Testing API
// ============================================================================

/**
 * Assertion methods for E2E tests.
 *
 * Provides Jest-style assertions for validating editor state, cursor position,
 * mode, and buffer contents during testing.
 *
 * @example
 * vim.e2e.test('cursor moves down', function() {
 *   vim.e2e.keys('j');
 *   vim.e2e.assert.cursorAt(1, 0);
 *   vim.e2e.assert.mode('NORMAL');
 * });
 */
export interface E2EAssert {
  /**
   * Assert two values are strictly equal (===).
   *
   * @param actual - The actual value from the test
   * @param expected - The expected value
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.assert.equal(vim.e2e.getMode(), 'NORMAL', 'Should be in normal mode');
   */
  equal(actual: any, expected: any, message?: string): void;

  /**
   * Assert two values are deeply equal (recursive object comparison).
   *
   * @param actual - The actual object/array
   * @param expected - The expected object/array
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.assert.deepEqual(vim.e2e.getCursor(), { line: 0, col: 0 });
   */
  deepEqual(actual: any, expected: any, message?: string): void;

  /**
   * Assert a condition is truthy.
   *
   * @param condition - Condition to check
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.assert.true(lineCount > 0, 'Buffer should have lines');
   */
  true(condition: boolean, message?: string): void;

  /**
   * Assert a condition is falsy.
   *
   * @param condition - Condition to check
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.assert.false(isModified, 'Buffer should not be modified');
   */
  false(condition: boolean, message?: string): void;

  /**
   * Assert value is null or undefined.
   *
   * @param value - Value to check
   * @param message - Optional failure message
   */
  null(value: any, message?: string): void;

  /**
   * Assert value is NOT null or undefined.
   *
   * @param value - Value to check
   * @param message - Optional failure message
   */
  notNull(value: any, message?: string): void;

  /**
   * Assert editor is in the specified mode.
   *
   * @param expected - Expected mode string ('NORMAL', 'INSERT', 'VISUAL', etc.)
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.keys('i');
   * vim.e2e.assert.mode('INSERT');
   */
  mode(expected: string, message?: string): void;

  /**
   * Assert cursor is at the specified position.
   *
   * @param line - Expected line number (0-indexed)
   * @param col - Expected column number (0-indexed)
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.keys('jjj');
   * vim.e2e.assert.cursorAt(3, 0, 'Cursor should move down 3 lines');
   */
  cursorAt(line: number, col: number, message?: string): void;

  /**
   * Assert buffer contains the specified text.
   *
   * @param text - Text to search for in buffer
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.keys('iHello<Esc>');
   * vim.e2e.assert.bufferContains('Hello');
   */
  bufferContains(text: string, message?: string): void;

  // ============================================================================
  // Frame Assertion Helpers (for animation testing)
  // ============================================================================

  /**
   * Assert the number of captured frames matches expected.
   * Use after calling pty.captureFrame() multiple times.
   *
   * @param expected - Expected number of frames
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * for (let i = 0; i < 5; i++) {
   *   vim.e2e.keys('l');
   *   vim.e2e.pty.render();
   *   vim.e2e.pty.captureFrame();
   * }
   * vim.e2e.assert.frameCount(5);
   */
  frameCount(expected: number, message?: string): void;

  /**
   * Assert all frame timestamps are strictly increasing.
   * Verifies animation progresses forward in time.
   *
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * // ... capture frames with waits between them ...
   * vim.e2e.assert.framesIncreasing('Timestamps should increase');
   */
  framesIncreasing(message?: string): void;

  /**
   * Assert all captured frames have non-empty output.
   * Validates that each frame actually rendered something.
   *
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * // ... capture frames ...
   * vim.e2e.assert.framesNotEmpty('All frames should have output');
   */
  framesNotEmpty(message?: string): void;

  /**
   * Assert all captured frames have unique output.
   * Detects animation progression (each frame should differ).
   *
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * for (let i = 0; i < 3; i++) {
   *   vim.e2e.keys('l');
   *   vim.e2e.pty.render();
   *   vim.e2e.pty.captureFrame();
   * }
   * vim.e2e.assert.framesUnique('Each frame should show cursor at different position');
   */
  framesUnique(message?: string): void;

  /**
   * Assert total animation duration is within expected bounds.
   * Validates animation timing is reasonable.
   *
   * @param minMs - Minimum expected duration in milliseconds
   * @param maxMs - Maximum expected duration in milliseconds
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * for (let i = 0; i < 5; i++) {
   *   vim.e2e.keys('l');
   *   vim.e2e.pty.render();
   *   vim.e2e.pty.captureFrame();
   *   vim.e2e.wait(16);  // ~60fps
   * }
   * vim.e2e.assert.frameDuration(50, 200, 'Animation should take 50-200ms');
   */
  frameDuration(minMs: number, maxMs: number, message?: string): void;

  /**
   * Assert a specific frame contains a pattern.
   * Validates specific animation frame content.
   *
   * @param frameIndex - Zero-based frame index
   * @param pattern - Text pattern to search for
   * @param message - Optional failure message
   *
   * @example
   * vim.e2e.keys('iTestContent<Esc>');
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.pty.render();
   * vim.e2e.pty.captureFrame();
   * vim.e2e.assert.frameContains(0, 'TestContent', 'Frame should show typed text');
   */
  frameContains(frameIndex: number, pattern: string, message?: string): void;
}

/**
 * Cursor position returned by E2E API.
 *
 * Note: Uses `line` (not `row`) for consistency with the E2E API.
 *
 * @example
 * const cursor = vim.e2e.getCursor();
 * console.log(`Line: ${cursor.line}, Col: ${cursor.col}`);
 */
export interface E2ECursor {
  /** Line number (0-indexed) */
  line: number;
  /** Column number (0-indexed) */
  col: number;
}

/**
 * Complete editor state snapshot for E2E testing.
 *
 * Provides cursor position, mode, and buffer information.
 *
 * @example
 * const state = vim.e2e.getState();
 * console.log(`Mode: ${state.mode}`);
 * console.log(`Line count: ${state.buffer.lineCount}`);
 */
export interface E2EState {
  /** Current cursor position */
  cursor: E2ECursor;
  /** Current editor mode ('NORMAL', 'INSERT', 'VISUAL', etc.) */
  mode: string;
  /** Buffer information */
  buffer: {
    /** Number of lines in the buffer */
    lineCount: number;
    /** Buffer change counter (increments on each edit) */
    changedTick: number;
    /** Buffer content as array of lines (when requested) */
    lines?: string[];
  };
}

/**
 * Compositor layer information for debugging rendering.
 *
 * Layers are used for virtual text, cursor overlays, and plugin rendering.
 *
 * @example
 * const layers = vim.e2e.getLayers();
 * for (const layer of layers) {
 *   console.log(`${layer.name}: ${layer.enabled ? 'enabled' : 'disabled'}`);
 * }
 */
export interface E2ELayer {
  /** Layer name (e.g., 'cursor', 'virtual_text', 'diagnostic') */
  name: string;
  /** Whether the layer is currently enabled */
  enabled: boolean;
  /** Whether the layer needs re-rendering */
  dirty: boolean;
  /** Number of cells in the layer */
  cells: number;
}

/**
 * Individual cell from a compositor layer.
 *
 * Used by getLayerCells() for debugging "which layer painted this cell?"
 *
 * @example
 * const cells = vim.e2e.getLayerCells('selection');
 * const highlighted = cells.filter(c => c.bg !== undefined);
 */
export interface E2ELayerCell {
  /** Row position (0-indexed) */
  row: number;
  /** Column position (0-indexed) */
  col: number;
  /** Character at this cell (if any) */
  char?: string;
  /** Foreground color (if set) */
  fg?: { r: number; g: number; b: number };
  /** Background color (if set) */
  bg?: { r: number; g: number; b: number };
}

/**
 * Captured animation frame with timestamp and terminal output.
 *
 * Used by the animation frame capture API to record sequences of
 * render frames for testing animations (like smear-cursor).
 *
 * @example
 * vim.e2e.pty.startFrameCapture();
 * vim.e2e.keys('lllll');  // Trigger animation
 * vim.e2e.wait(500);       // Let animation run
 * const frames = vim.e2e.pty.getFrames();
 * console.log(`Captured ${frames.length} frames`);
 * frames.forEach(f => console.log(`t=${f.timestamp}ms: ${f.output.length} bytes`));
 */
export interface CapturedFrame {
  /** Milliseconds since frame capture started */
  timestamp: number;
  /** Raw ANSI terminal output for this frame */
  output: string;
}

/**
 * Rendering statistics from PTY capture.
 *
 * Used to analyze terminal output efficiency and detect rendering issues.
 *
 * @example
 * vim.e2e.pty.startCapture();
 * vim.e2e.keys('jjjjj');
 * vim.e2e.pty.render();
 * const stats = vim.e2e.pty.getRenderStats();
 * console.log(`Renders: ${stats.totalRenders}, Avg: ${stats.avgRenderMs}ms`);
 */
export interface E2ERenderStats {
  /** Total number of render operations */
  totalRenders: number;
  /** Number of cursor hide escape codes sent */
  cursorHideCodes: number;
  /** Number of cursor show escape codes sent */
  cursorShowCodes: number;
  /** Number of cursor position escape codes sent */
  cursorPositionCodes: number;
  /** Average render time in milliseconds */
  avgRenderMs: number;
}

/**
 * PTY (Pseudo-Terminal) API for inspecting terminal output.
 *
 * Used for testing terminal rendering, escape code generation, and
 * debugging visual issues. Captures raw ANSI escape codes sent to the terminal.
 *
 * @example
 * // Test that cursor doesn't flicker during movement
 * vim.e2e.pty.startCapture();
 * vim.e2e.keys('jjjjj');
 * vim.e2e.pty.render();
 * vim.e2e.pty.stopCapture();
 *
 * const hideCodes = vim.e2e.pty.countHideCursor();
 * vim.e2e.assert.true(hideCodes < 5, 'Too many cursor hide codes');
 */
export interface E2EPTY {
  /**
   * Start capturing terminal output to internal buffer.
   * Call before executing commands you want to inspect.
   */
  startCapture(): void;

  /**
   * Stop capturing terminal output.
   * Call after executing commands, before analyzing output.
   */
  stopCapture(): void;

  /**
   * Check if PTY is currently capturing output.
   * @returns true if capture is active
   */
  isCapturing(): boolean;

  /**
   * Clear the captured output buffer.
   * Use between tests to get fresh capture.
   */
  clear(): void;

  /**
   * Trigger a render operation.
   * Forces the editor to generate terminal output.
   */
  render(): void;

  /**
   * Get the raw captured terminal output.
   * Contains ANSI escape codes and text.
   * @returns Raw terminal output string
   */
  getOutput(): string;

  /**
   * Get length of captured output in bytes.
   * @returns Number of bytes captured
   */
  getLength(): number;

  /**
   * Clear the captured output buffer (alias for clear()).
   */
  clearOutput(): void;

  /**
   * Count SGR (Select Graphic Rendition) codes in captured output.
   * SGR codes control colors and text attributes (ESC[...m).
   * @returns Number of SGR escape sequences
   */
  countSGRCodes(): number;

  /**
   * Count cursor hide escape codes (ESC[?25l).
   * @returns Number of cursor hide codes
   */
  countHideCursor(): number;

  /**
   * Count cursor show escape codes (ESC[?25h).
   * @returns Number of cursor show codes
   */
  countShowCursor(): number;

  /**
   * Count cursor position escape codes (ESC[row;colH).
   * @returns Number of cursor position codes
   */
  countCursorPositionCodes(): number;

  /**
   * Count occurrences of a specific escape sequence.
   *
   * @param seq - Escape sequence to count (e.g., '\x1b[2J' for clear screen)
   * @returns Number of occurrences
   *
   * @example
   * const clearCount = vim.e2e.pty.countSequence('\x1b[2J');
   */
  countSequence(seq: string): number;

  /**
   * Reset internal cursor state tracking.
   * Use when starting fresh cursor position tests.
   */
  resetCursorState(): void;

  /**
   * Get comprehensive render statistics.
   * @returns Statistics about rendering operations
   */
  getRenderStats(): E2ERenderStats;

  // ============================================================================
  // Animation Frame Capture API
  // ============================================================================

  /**
   * Start capturing animation frames.
   * Each render cycle will create a new timestamped frame.
   * Use this for testing animations like smear-cursor.
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.keys('lllll');  // Move cursor (triggers animation)
   * vim.e2e.wait(500);       // Let animation run
   * const frames = vim.e2e.pty.getFrames();
   * vim.e2e.pty.stopFrameCapture();
   */
  startFrameCapture(): void;

  /**
   * Stop capturing animation frames.
   * @returns Number of frames captured
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.keys('jjjjj');
   * vim.e2e.wait(200);
   * const count = vim.e2e.pty.stopFrameCapture();
   * console.log(`Captured ${count} frames`);
   */
  stopFrameCapture(): number;

  /**
   * Manually capture the current render output as a frame.
   * Frames are also captured automatically during render when
   * frame capture mode is active, but this allows explicit control.
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.pty.render();
   * vim.e2e.pty.captureFrame();  // Explicitly save this frame
   * vim.e2e.keys('j');
   * vim.e2e.pty.render();
   * vim.e2e.pty.captureFrame();  // Another explicit frame
   */
  captureFrame(): void;

  /**
   * Get all captured animation frames.
   * Each frame contains a timestamp (ms since capture started) and
   * the raw ANSI terminal output.
   *
   * @returns Array of captured frames with timestamps
   *
   * @example
   * const frames = vim.e2e.pty.getFrames();
   * vim.e2e.assert.true(frames.length >= 5, 'Should capture multiple frames');
   *
   * // Check animation progression
   * for (let i = 1; i < frames.length; i++) {
   *   vim.e2e.assert.true(
   *     frames[i].timestamp > frames[i-1].timestamp,
   *     'Timestamps should increase'
   *   );
   * }
   */
  getFrames(): CapturedFrame[];

  /**
   * Get the number of captured frames.
   * @returns Number of frames in the capture buffer
   *
   * @example
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.keys('lllll');
   * vim.e2e.wait(300);
   * const count = vim.e2e.pty.getFrameCount();
   * vim.e2e.assert.true(count > 0, 'Should have captured frames');
   */
  getFrameCount(): number;

  /**
   * Check if frame capture mode is currently active.
   * @returns true if capturing frames
   *
   * @example
   * vim.e2e.assert.false(vim.e2e.pty.isCapturingFrames());
   * vim.e2e.pty.startFrameCapture();
   * vim.e2e.assert.true(vim.e2e.pty.isCapturingFrames());
   */
  isCapturingFrames(): boolean;

  // ============================================================================
  // Terminal Size Control
  // ============================================================================

  /**
   * Set the terminal size for E2E testing.
   * This allows testing different terminal dimensions without a real PTY.
   * Useful for testing responsive layouts, text wrapping, viewport behavior.
   *
   * Note: This controls the Display's internal grid size, not a real PTY.
   * For real PTY operations (external processes), use process.spawnPty().resize().
   *
   * @param rows - Number of terminal rows (height), must be 1-1000
   * @param cols - Number of terminal columns (width), must be 1-1000
   * @returns true on success
   *
   * @example
   * // Test rendering at 80x24 terminal (classic size)
   * vim.e2e.pty.setSize(24, 80);
   * vim.e2e.pty.render();
   * vim.e2e.assert.cursorAt(0, 0);
   *
   * @example
   * // Test responsive behavior at small size
   * vim.e2e.pty.setSize(10, 40);
   * vim.e2e.keys('iHello World<Esc>');
   * vim.e2e.pty.render();
   * // Assert layout behavior at smaller terminal
   */
  setSize(rows: number, cols: number): boolean;

  /**
   * Get the current terminal size.
   * @returns Object with rows and cols properties
   *
   * @example
   * const size = vim.e2e.pty.getSize();
   * console.log(`Terminal: ${size.cols}x${size.rows}`);
   *
   * @example
   * // Verify size after setSize()
   * vim.e2e.pty.setSize(30, 100);
   * const size = vim.e2e.pty.getSize();
   * vim.e2e.assert.equal(size.rows, 30);
   * vim.e2e.assert.equal(size.cols, 100);
   */
  getSize(): { rows: number; cols: number };
}

/**
 * Result from running E2E tests.
 *
 * @example
 * const result = vim.e2e.runAll();
 * console.log(`Passed: ${result.passed}, Failed: ${result.failed}`);
 */
export interface E2ETestResult {
  /** Number of tests that passed */
  passed: number;
  /** Number of tests that failed */
  failed: number;
}

/**
 * E2E Testing API for plugin testing and interactive debugging.
 *
 * Provides Jest/Mocha-style test structure (`describe`, `test`, `assert`)
 * for writing end-to-end tests that interact with the real editor.
 *
 * Only available when running `vimc test` command.
 *
 * @example
 * // Basic E2E test structure
 * vim.e2e.describe('Motion Commands', function() {
 *   vim.e2e.test('j moves cursor down', function() {
 *     vim.e2e.keys('j');
 *     vim.e2e.assert.cursorAt(1, 0);
 *   });
 *
 *   vim.e2e.test('w moves to next word', function() {
 *     vim.e2e.keys('w');
 *     const cursor = vim.e2e.getCursor();
 *     vim.e2e.assert.true(cursor.col > 0, 'Cursor should move forward');
 *   });
 * });
 *
 * vim.e2e.runAll();
 *
 * @example
 * // Testing rendering with PTY capture
 * vim.e2e.describe('Rendering Optimization', function() {
 *   vim.e2e.test('no excessive cursor codes', function() {
 *     vim.e2e.pty.startCapture();
 *     vim.e2e.keys('jjjjj');
 *     vim.e2e.pty.render();
 *     vim.e2e.pty.stopCapture();
 *
 *     const stats = vim.e2e.pty.getRenderStats();
 *     vim.e2e.assert.true(stats.cursorPositionCodes < 10);
 *   });
 * });
 *
 * vim.e2e.runAll();
 *
 * @see https://vimcraft.dev/docs/testing
 */
export interface E2EAPI {
  /**
   * Group related tests under a description.
   *
   * @param description - Name/description for this test group
   * @param fn - Function containing test definitions
   *
   * @example
   * vim.e2e.describe('Visual Mode', function() {
   *   vim.e2e.test('v enters visual mode', function() { ... });
   *   vim.e2e.test('V enters line visual mode', function() { ... });
   * });
   */
  describe(description: string, fn: () => void): void;

  /**
   * Define a single test case.
   *
   * @param name - Name of the test
   * @param fn - Test function containing assertions
   *
   * @example
   * vim.e2e.test('cursor moves right with l', function() {
   *   vim.e2e.keys('l');
   *   vim.e2e.assert.cursorAt(0, 1);
   * });
   */
  test(name: string, fn: () => void): void;

  /**
   * Run all defined tests and return results.
   *
   * @returns Object containing pass/fail counts
   *
   * @example
   * const result = vim.e2e.runAll();
   * if (result.failed > 0) {
   *   console.error(`${result.failed} tests failed!`);
   * }
   */
  runAll(): E2ETestResult;

  /**
   * Send a key sequence to the editor.
   *
   * Simulates user input. Supports special keys in angle brackets.
   *
   * @param keys - Key sequence to send (e.g., 'jjj', '<Esc>', 'iHello<Esc>')
   *
   * @example
   * vim.e2e.keys('i');        // Enter insert mode
   * vim.e2e.keys('Hello');    // Type "Hello"
   * vim.e2e.keys('<Esc>');    // Exit insert mode
   * vim.e2e.keys('dd');       // Delete line
   */
  keys(keys: string): void;

  /**
   * Get current cursor position.
   *
   * @returns Cursor position with line and col (both 0-indexed)
   *
   * @example
   * const cursor = vim.e2e.getCursor();
   * console.log(`Cursor at line ${cursor.line}, col ${cursor.col}`);
   */
  getCursor(): E2ECursor;

  /**
   * Get complete editor state snapshot.
   *
   * @returns State object with cursor, mode, and buffer info
   *
   * @example
   * const state = vim.e2e.getState();
   * console.log(`Mode: ${state.mode}, Lines: ${state.buffer.lineCount}`);
   */
  getState(): E2EState;

  /**
   * Get current editor mode as a string.
   *
   * @returns Mode string: 'NORMAL', 'INSERT', 'VISUAL', 'VISUAL_LINE', etc.
   *
   * @example
   * vim.e2e.keys('i');
   * console.log(vim.e2e.getMode()); // 'INSERT'
   */
  getMode(): string;

  /**
   * Get information about compositor layers.
   *
   * Useful for debugging rendering and virtual text.
   *
   * @returns Array of layer information objects
   *
   * @example
   * const layers = vim.e2e.getLayers();
   * const cursorLayer = layers.find(l => l.name === 'cursor');
   */
  getLayers(): E2ELayer[];

  /**
   * Get all non-empty cells from a specific layer.
   *
   * Enables "which layer painted this cell?" debugging.
   * Returns cells with content OR background color (for selection highlighting).
   *
   * @param layerName - Name of the layer (base, gutter, cursor, selection, etc.)
   * @returns Array of cells with position and color info
   *
   * @example
   * // Debug selection layer
   * vim.e2e.keys("Vjjj");  // Enter visual line mode
   * vim.e2e.pty.render();
   * const cells = vim.e2e.getLayerCells("selection");
   * console.log("Selection cells:", cells.length);
   *
   * @example
   * // Check cursorline highlight
   * const cursorCells = vim.e2e.getLayerCells("cursor");
   * const row0 = cursorCells.filter(c => c.row === 0);
   */
  getLayerCells(layerName: string): E2ELayerCell[];

  /**
   * Get recent log entries from the editor.
   *
   * @param opts - Optional filter options
   * @param opts.level - Minimum log level ('debug', 'info', 'warn', 'error')
   * @param opts.maxBytes - Maximum bytes to return
   * @returns Log entries as a string
   *
   * @example
   * const logs = vim.e2e.getLogs({ level: 'debug', maxBytes: 4096 });
   * console.log(logs);
   */
  getLogs(opts?: { level?: string; maxBytes?: number }): string;

  /**
   * Log a checkpoint for debugging.
   *
   * Creates a marker in logs to help identify test phases.
   *
   * @param label - Label for the checkpoint
   *
   * @example
   * vim.e2e.checkpoint('Before motion');
   * vim.e2e.keys('jjj');
   * vim.e2e.checkpoint('After motion');
   */
  checkpoint(label: string): void;

  /**
   * Assertion library for validating test expectations.
   *
   * @example
   * vim.e2e.assert.equal(actual, expected);
   * vim.e2e.assert.mode('NORMAL');
   * vim.e2e.assert.cursorAt(0, 0);
   */
  assert: E2EAssert;

  /**
   * PTY (Pseudo-Terminal) API for inspecting terminal output.
   *
   * @example
   * vim.e2e.pty.startCapture();
   * vim.e2e.keys('jjj');
   * vim.e2e.pty.render();
   * const output = vim.e2e.pty.getOutput();
   */
  pty: E2EPTY;
}

// ============================================================================
// Buffer API
// ============================================================================

/**
 * Buffer content access API for zero-copy buffer operations.
 *
 * Provides efficient access to buffer content without copying data.
 * Uses ArrayBuffer for binary-safe content access.
 *
 * @example
 * // Get total buffer content
 * const content = vim.buffer.getContent();
 * const text = new TextDecoder().decode(content);
 * console.log(`Buffer has ${text.length} characters`);
 *
 * @example
 * // Get specific line content
 * const line = vim.buffer.getLineContent(0);
 * const lineText = new TextDecoder().decode(line);
 *
 * @example
 * // Check buffer info
 * console.log(`Lines: ${vim.buffer.getLineCount()}`);
 * console.log(`Bytes: ${vim.buffer.getLength()}`);
 * console.log(`Changes: ${vim.buffer.getChangedTick()}`);
 */
export interface BufferAPI {
  /**
   * Get entire buffer content as ArrayBuffer.
   *
   * Returns a zero-copy snapshot of the buffer.
   * Note: Buffer modifications after this call may not be reflected.
   *
   * @returns ArrayBuffer containing buffer content
   *
   * @example
   * const content = vim.buffer.getContent();
   * const text = new TextDecoder().decode(content);
   */
  getContent(): ArrayBuffer;

  /**
   * Get content of a specific line as ArrayBuffer.
   *
   * @param lineNumber - Line number (0-indexed)
   * @returns ArrayBuffer containing line content (without newline)
   *
   * @example
   * const firstLine = vim.buffer.getLineContent(0);
   * const text = new TextDecoder().decode(firstLine);
   */
  getLineContent(lineNumber: number): ArrayBuffer;

  /**
   * Get total buffer length in bytes.
   *
   * @returns Number of bytes in buffer
   */
  getLength(): number;

  /**
   * Get number of lines in buffer.
   *
   * @returns Number of lines (including empty lines)
   */
  getLineCount(): number;

  /**
   * Get buffer change counter.
   *
   * Increments on each modification. Useful for caching.
   *
   * @returns Change counter value
   *
   * @example
   * const before = vim.buffer.getChangedTick();
   * vim.e2e.keys('iHello<Esc>');
   * const after = vim.buffer.getChangedTick();
   * console.log(`Changes: ${after - before}`);
   */
  getChangedTick(): number;
}

// ============================================================================
// Motion API
// ============================================================================

/**
 * Cursor motion primitives for programmatic cursor movement.
 *
 * Used by plugins like smear-cursor for smooth cursor animations.
 * All motions trigger `js_state_dirty` to ensure rendering updates.
 *
 * @example
 * // Move cursor like pressing 'jjjll'
 * vim.motion.down();
 * vim.motion.down();
 * vim.motion.down();
 * vim.motion.right();
 * vim.motion.right();
 *
 * @example
 * // Navigate to beginning of file
 * vim.motion.fileStart();
 *
 * @example
 * // Word-wise navigation
 * vim.motion.wordForward();  // Like 'w'
 * vim.motion.wordBackward(); // Like 'b'
 * vim.motion.wordEnd();      // Like 'e'
 */
export interface MotionAPI {
  /**
   * Move cursor left one character (like 'h').
   * Respects line boundaries.
   */
  left(): void;

  /**
   * Move cursor right one character (like 'l').
   * Respects line boundaries.
   */
  right(): void;

  /**
   * Move cursor up one line (like 'k').
   * Maintains preferred column when possible.
   */
  up(): void;

  /**
   * Move cursor down one line (like 'j').
   * Maintains preferred column when possible.
   */
  down(): void;

  /**
   * Move cursor to start of line (like '0').
   * Moves to column 0.
   */
  lineStart(): void;

  /**
   * Move cursor to end of line (like '$').
   * Moves to last character of line.
   */
  lineEnd(): void;

  /**
   * Move cursor to first non-blank character (like '^').
   * Skips leading whitespace.
   */
  firstNonBlank(): void;

  /**
   * Move cursor to start of next word (like 'w').
   */
  wordForward(): void;

  /**
   * Move cursor to start of previous word (like 'b').
   */
  wordBackward(): void;

  /**
   * Move cursor to end of current/next word (like 'e').
   */
  wordEnd(): void;

  /**
   * Move cursor to start of file (like 'gg').
   * Moves to line 0, column 0.
   */
  fileStart(): void;

  /**
   * Move cursor to end of file (like 'G').
   * Moves to last line, first non-blank column.
   */
  fileEnd(): void;

  /**
   * Move cursor to specific line (like ':123' or '123G').
   *
   * @param line - Line number (0-indexed)
   *
   * @example
   * vim.motion.gotoLine(99); // Go to line 100 (0-indexed)
   */
  gotoLine(line: number): void;
}

// ============================================================================
// Cursor API
// ============================================================================

/**
 * Cursor rendering API for animated cursor plugins.
 *
 * Allows plugins to override the visual cursor position for smooth
 * animations (like smear-cursor.nvim) while keeping the logical
 * cursor position unchanged.
 *
 * @example
 * // Animate cursor from current position to target
 * const start = vim.cursor.getPosition();
 * const target = { row: 10, col: 0 };
 *
 * // Render intermediate positions
 * for (let t = 0; t <= 1; t += 0.1) {
 *   const row = start.row + (target.row - start.row) * t;
 *   const col = start.col + (target.col - start.col) * t;
 *   vim.cursor.setRenderPosition(Math.round(row), Math.round(col));
 *   // ... wait for animation frame ...
 * }
 *
 * // Clear override when done
 * vim.cursor.clearRenderPosition();
 */
export interface CursorAPI {
  /**
   * Get current logical cursor position.
   *
   * Returns the actual cursor position, not the render override.
   *
   * @returns Object with row and col (both 0-indexed)
   *
   * @example
   * const { row, col } = vim.cursor.getPosition();
   * console.log(`Cursor at row ${row}, col ${col}`);
   */
  getPosition(): { row: number; col: number };

  /**
   * Set visual cursor render position (for animations).
   *
   * The logical cursor position is unchanged; only the visual
   * representation is moved. Use for smooth cursor animations.
   *
   * @param row - Visual row position (0-indexed)
   * @param col - Visual column position (0-indexed)
   *
   * @example
   * // Show cursor at row 5, col 10 (visual only)
   * vim.cursor.setRenderPosition(5, 10);
   */
  setRenderPosition(row: number, col: number): void;

  /**
   * Clear render position override.
   *
   * Restores cursor to render at its logical position.
   * Call when animation completes.
   *
   * @example
   * // Animation complete, show cursor at actual position
   * vim.cursor.clearRenderPosition();
   */
  clearRenderPosition(): void;

  /**
   * Hide the terminal cursor.
   *
   * Used by animation plugins (like smear-cursor) to hide the real
   * terminal cursor during animation, preventing "ghosting" artifacts.
   *
   * @example
   * // Hide cursor at animation start
   * vim.cursor.hide();
   *
   * // ... run animation frames ...
   *
   * // Show cursor when done
   * vim.cursor.show();
   */
  hide(): void;

  /**
   * Show the terminal cursor.
   *
   * Restores cursor visibility after hiding. Should be called when
   * animation completes to restore normal cursor behavior.
   *
   * @example
   * // Show cursor after animation ends
   * vim.cursor.show();
   */
  show(): void;
}

// ============================================================================
// Layer API
// ============================================================================

/**
 * Virtual text layer API for rendering overlays.
 *
 * Layers are used for Neovim-style features like:
 * - Diagnostic virtual text
 * - LSP inline hints
 * - Git blame annotations
 * - Plugin-specific decorations
 *
 * Layers are composited on top of the buffer content using alpha blending.
 *
 * @example
 * // Create a diagnostic layer
 * const layerId = vim.layer.create('my-diagnostics');
 *
 * // Add error indicator at line 5, col 0
 * vim.layer.setCell(layerId, 5, 0, 'E', '#ff0000', null);
 *
 * // Cleanup when done
 * vim.layer.destroy(layerId);
 *
 * @example
 * // Fade layer in/out
 * vim.layer.setOpacity(layerId, 0.5); // 50% visible
 * vim.layer.setEnabled(layerId, false); // Hide completely
 */
export interface LayerAPI {
  /**
   * Create a new rendering layer.
   *
   * @param name - Unique name for the layer (for debugging)
   * @returns Layer ID for subsequent operations
   *
   * @example
   * const id = vim.layer.create('git-blame');
   */
  create(name: string): number;

  /**
   * Destroy a layer and free its resources.
   *
   * @param id - Layer ID from create()
   *
   * @example
   * vim.layer.destroy(layerId);
   */
  destroy(id: number): void;

  /**
   * Set a cell's content and colors in the layer.
   *
   * @param id - Layer ID
   * @param row - Row position (0-indexed)
   * @param col - Column position (0-indexed)
   * @param char - Character to display (single char)
   * @param fg - Foreground color as hex string (e.g., '#ff0000') or null
   * @param bg - Background color as hex string or null
   *
   * @example
   * // Red 'E' for error indicator
   * vim.layer.setCell(layerId, 5, 0, 'E', '#ff0000', null);
   *
   * // Yellow background highlight
   * vim.layer.setCell(layerId, 10, 0, ' ', null, '#ffff00');
   */
  setCell(id: number, row: number, col: number, char: string, fg?: string, bg?: string): void;

  /**
   * Clear all cells in a layer.
   *
   * @param id - Layer ID
   *
   * @example
   * vim.layer.clear(layerId);
   */
  clear(id: number): void;

  /**
   * Enable or disable a layer.
   *
   * Disabled layers are not rendered but retain their content.
   *
   * @param id - Layer ID
   * @param enabled - Whether to show the layer
   *
   * @example
   * vim.layer.setEnabled(layerId, false); // Hide
   * vim.layer.setEnabled(layerId, true);  // Show
   */
  setEnabled(id: number, enabled: boolean): void;

  /**
   * Set layer opacity for alpha blending.
   *
   * @param id - Layer ID
   * @param opacity - Opacity value (0.0 = transparent, 1.0 = opaque)
   *
   * @example
   * vim.layer.setOpacity(layerId, 0.7); // 70% visible
   */
  setOpacity(id: number, opacity: number): void;

  /**
   * Get information about a layer.
   *
   * @param id - Layer ID
   * @returns Object with layer name, enabled state, and opacity
   *
   * @example
   * const info = vim.layer.getInfo(layerId);
   * console.log(`Layer: ${info.name}, visible: ${info.enabled}`);
   */
  getInfo(id: number): { name: string; enabled: boolean; opacity: number };
}

// ============================================================================
// Filetype API
// ============================================================================

/**
 * Filetype detection API using go-enry (GitHub Linguist).
 *
 * Detects programming language from filename and/or content.
 * Supports 697 languages with high accuracy.
 *
 * Detection strategies (in order):
 * 1. File extension (`.rs` → Rust)
 * 2. Filename (`Makefile` → Makefile)
 * 3. Shebang (`#!/usr/bin/env python` → Python)
 * 4. Modeline (`# vim: set ft=python:` → Python)
 * 5. Content heuristics (disambiguates `.h` files)
 * 6. Bayesian classifier (fallback)
 *
 * @example
 * // Detect by filename
 * const lang = vim.filetype.match({ filename: 'main.rs' });
 * console.log(lang); // 'Rust'
 *
 * @example
 * // Detect by content (shebang)
 * const lang = vim.filetype.match({
 *   filename: 'script',
 *   content: '#!/usr/bin/env node\nconsole.log("hello");'
 * });
 * console.log(lang); // 'JavaScript'
 *
 * @example
 * // Detect ambiguous .h file
 * const lang = vim.filetype.match({
 *   filename: 'header.h',
 *   content: '#include <iostream>\nclass Foo {};'
 * });
 * console.log(lang); // 'C++' (not 'C')
 */
export interface FiletypeAPI {
  /**
   * Detect language from filename and/or content.
   *
   * At least one of `filename` or `content` should be provided.
   * Both can be provided for better accuracy (especially for `.h` files).
   *
   * @param opts - Detection options
   * @param opts.filename - Filename (e.g., 'main.rs', 'Makefile')
   * @param opts.content - File content (for content-based detection)
   * @returns Language name (e.g., 'Rust', 'JavaScript') or null if unknown
   *
   * @example
   * vim.filetype.match({ filename: 'config.yaml' }); // 'YAML'
   * vim.filetype.match({ filename: 'README.md' });   // 'Markdown'
   * vim.filetype.match({ filename: 'unknown.xyz' }); // null
   */
  match(opts: { filename?: string; content?: string }): string | null;
}

// ============================================================================
// Tree-sitter API
// ============================================================================

/**
 * Tree-sitter integration API.
 *
 * Provides access to tree-sitter parsing and language injection support.
 * Uses LanguageTree for recursive parsing of embedded languages.
 *
 * Key features:
 * - Language detection and parser availability
 * - LanguageTree for injection support (e.g., Markdown with code blocks)
 * - Language-at-position queries for injected regions
 *
 * @example
 * // Check if language is supported
 * if (vim.treesitter.hasParser('javascript')) {
 *   console.log('JavaScript parsing available');
 * }
 *
 * @example
 * // Enable injection support for markdown
 * vim.treesitter.getLanguageTree(0, 'markdown');
 *
 * @example
 * // Get language at a specific position (for injected code)
 * const lang = vim.treesitter.languageForRange(100, 200);
 * console.log(lang); // 'javascript' if in a JS code block
 */
export interface TreesitterAPI {
  /**
   * Check if a tree-sitter parser is available for the language.
   *
   * @param lang - Language name (e.g., 'javascript', 'python', 'markdown')
   * @returns true if parser is available, false otherwise
   *
   * @example
   * vim.treesitter.hasParser('javascript'); // true
   * vim.treesitter.hasParser('unknown');    // false
   */
  hasParser(lang: string): boolean;

  /**
   * Initialize LanguageTree for a buffer with injection support.
   *
   * LanguageTree enables recursive parsing of embedded languages.
   * For example, Markdown files with JavaScript code blocks will have
   * separate parsers for Markdown and JavaScript.
   *
   * @param bufnr - Buffer number (0 for current buffer)
   * @param lang - Language name (optional, uses buffer filetype if not specified)
   * @returns true if initialization succeeded, false otherwise
   *
   * @example
   * // Enable injections for current buffer
   * vim.treesitter.getLanguageTree(0, 'markdown');
   */
  getLanguageTree(bufnr?: number, lang?: string): boolean;

  /**
   * Check if current buffer has LanguageTree (injection support enabled).
   *
   * @param bufnr - Buffer number (0 for current buffer)
   * @returns true if LanguageTree is initialized
   */
  hasLanguageTree(bufnr?: number): boolean;

  /**
   * Get list of all supported tree-sitter languages.
   *
   * @returns Array of language names
   *
   * @example
   * const langs = vim.treesitter.getLanguages();
   * // ['c', 'zig', 'javascript', 'typescript', 'markdown', ...]
   */
  getLanguages(): string[];

  /**
   * Get the language name for a byte range (useful for injected languages).
   *
   * Returns the most specific language for the given position. For example,
   * in a Markdown file with a JavaScript code block, this returns 'javascript'
   * when the range is inside the code block.
   *
   * @param startByte - Start byte position
   * @param endByte - End byte position
   * @returns Language name or null if no LanguageTree is active
   *
   * @example
   * const lang = vim.treesitter.languageForRange(100, 200);
   * // 'javascript' if position is in a JS code block
   */
  languageForRange(startByte: number, endByte: number): string | null;

  /**
   * Update LanguageTree after buffer modifications.
   *
   * Re-parses the buffer content and processes injections.
   * Call this after making changes to ensure highlighting is up-to-date.
   *
   * @returns true if update succeeded, false if no LanguageTree is active
   */
  updateTree(): boolean;

  /**
   * Get list of injected languages in the current buffer.
   *
   * Returns the languages detected in injection regions.
   * For example, a Markdown file with JS and CSS code blocks
   * returns ['javascript', 'css'].
   *
   * @returns Array of injected language names
   *
   * @example
   * const injected = vim.treesitter.getInjectedLanguages();
   * // ['javascript', 'css'] for a markdown file with code blocks
   */
  getInjectedLanguages(): string[];
}

// ============================================================================
// Main Vim Interface
// ============================================================================

/**
 * Main Vimcraft API interface.
 *
 * The global `vim` object is the entry point for all Vimcraft configuration
 * and plugin development. Uses JavaScript naming conventions (camelCase).
 *
 * Key features:
 * - **vim.opt**: Editor options (number, cursorLine, tabStop, etc.)
 * - **vim.keymap**: Key mapping creation and deletion
 * - **vim.api**: Low-level API functions (buffers, windows, highlights)
 * - **vim.highlight()**: Syntax highlighting configuration
 * - **vim.motion**: Cursor movement primitives
 * - **vim.e2e**: E2E testing API (test mode only)
 *
 * @example
 * // Basic configuration
 * vim.opt.number = true;
 * vim.opt.cursorLine = true;
 * vim.opt.tabStop = 4;
 *
 * @example
 * // Define key mappings
 * vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
 * vim.keymap.set('n', '<leader>q', ':q<CR>', { desc: 'Quit' });
 *
 * @example
 * // Define highlight groups
 * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
 * vim.highlight('CursorLine', { bg: '#2e2e3e' });
 *
 * @example
 * // Listen to autocommand events
 * vim.on('BufEnter', (args) => {
 *   console.log('Entered buffer:', args.file);
 * });
 *
 * @see https://vimcraft.com/docs/editor-api/user/lua
 */

// ============================================================================
// VimCmd - Ex Command Interface
// ============================================================================

/**
 * Direction for window navigation commands.
 */
export type WincmdDirection = 'h' | 'j' | 'k' | 'l' | 'left' | 'right' | 'up' | 'down';

/**
 * Ex command methods.
 *
 * @example
 * vim.cmd.wincmd('h');         // Window navigation
 * vim.cmd.vsplit();            // Vertical split
 * vim.cmd.write();             // Save file
 */
export interface VimCmd {
  /**
   * Navigate to adjacent window.
   * @param direction - 'h'=left, 'j'=down, 'k'=up, 'l'=right
   *
   * @example
   * vim.cmd.wincmd('h');  // Move to left window
   * vim.cmd.wincmd('l');  // Move to right window
   */
  wincmd(direction: WincmdDirection): void;

  /**
   * Create a vertical split.
   * @param file - Optional file to open in new split
   *
   * @example
   * vim.cmd.vsplit();              // Empty vsplit
   * vim.cmd.vsplit('file.txt');    // Vsplit with file
   */
  vsplit(file?: string): void;

  /**
   * Create a horizontal split.
   * @param file - Optional file to open in new split
   */
  split(file?: string): void;

  /**
   * Save the current buffer.
   */
  write(): void;

  /**
   * Quit the current window.
   */
  quit(): void;

  /**
   * Edit a file.
   * @param file - File path to open
   */
  edit(file?: string): void;

  /**
   * Create new buffer in horizontal split.
   */
  new(): void;

  /**
   * Create new buffer in vertical split.
   */
  vnew(): void;

  /**
   * Close all other windows (make current window the only one).
   */
  only(): void;

  /**
   * Close the current window.
   */
  close(): void;

  // === Search Commands ===

  /**
   * Clear search highlighting.
   * The search pattern is preserved for n/N navigation.
   *
   * @example
   * vim.fn.setReg('/', 'TODO');
   * // Matches are highlighted...
   * vim.cmd.nohlsearch();
   * // Highlighting cleared, but 'n' still works
   */
  nohlsearch(): void;

  /**
   * Clear search highlighting (short form).
   * Alias for nohlsearch().
   */
  noh(): void;

  /**
   * Execute a Vim command string.
   * @param cmd - Command to execute (e.g., "normal! dd", "set number")
   *
   * @example
   * vim.cmd.execute("normal! gg");
   * vim.cmd.execute("set cursorline");
   */
  execute(cmd: string): void;
}

export interface Vim {
  /**
   * Core API functions for buffer, window, and editor operations.
   *
   * Use this for low-level operations not exposed through other interfaces.
   *
   * @example
   * // Buffer operations
   * const buf = vim.api.getCurrentBuf();
   * const lines = vim.api.bufGetLines(buf, 0, 10, false);
   *
   * @example
   * // Window operations
   * const [row, col] = vim.api.winGetCursor(0);
   *
   * @example
   * // Create autocommands
   * vim.api.createAutocmd('BufWritePre', {
   *   pattern: '*.ts',
   *   callback: () => console.log('Saving TypeScript file')
   * });
   */
  api: API;

  /**
   * Editor options with automatic scope detection.
   *
   * Settings applied here are automatically scoped to the appropriate
   * level (global or buffer-local) based on the option type.
   *
   * All option names use camelCase (e.g., `cursorLine` not `cursorline`).
   *
   * @example
   * // Display options
   * vim.opt.number = true;
   * vim.opt.cursorLine = true;
   * vim.opt.signColumn = 'yes';
   *
   * @example
   * // Editing options
   * vim.opt.tabStop = 4;
   * vim.opt.shiftWidth = 4;
   * vim.opt.expandTab = true;
   *
   * @example
   * // Search options
   * vim.opt.ignoreCase = true;
   * vim.opt.smartCase = true;
   *
   * @see https://vimcraft.com/docs/editor-api/user/options
   */
  opt: VimOptions;

  /**
   * Buffer-local options only.
   *
   * Settings applied here only affect the current buffer.
   *
   * @example
   * // Set tabstop only for current buffer
   * vim.optLocal.tabStop = 2;
   */
  optLocal?: VimOptions;

  /**
   * Global options only.
   *
   * Settings applied here affect all buffers.
   *
   * @example
   * // Set global default tabstop
   * vim.optGlobal.tabStop = 4;
   */
  optGlobal?: VimOptions;

  /**
   * Key mapping interface for creating and deleting keybindings.
   *
   * Provides `set()` and `del()` methods for managing mappings.
   *
   * @example
   * // Save file with <leader>w
   * vim.keymap.set('n', '<leader>w', ':w<CR>', { silent: true });
   *
   * @example
   * // Map with callback function
   * vim.keymap.set('n', '<leader>f', () => {
   *   console.log('Finding files...');
   * });
   *
   * @see https://vimcraft.com/docs/editor-api/user/lua#vim.keymap
   */
  keymap: Keymap;

  /**
   * Register event listener for autocommand events.
   *
   * Provides Node.js EventEmitter-style API for editor events.
   *
   * @param event - Event name (e.g., 'BufRead', 'InsertEnter', 'FileType')
   * @param callback - Function called when event fires
   *
   * @example
   * // Log when entering a buffer
   * vim.on('BufEnter', (args) => {
   *   console.log('Entered buffer:', args.file);
   *   console.log('Buffer number:', args.buf);
   * });
   *
   * @example
   * // Format on save
   * vim.on('BufWritePre', (args) => {
   *   // Run formatter before saving
   *   formatBuffer(args.buf);
   * });
   *
   * @see https://vimcraft.com/docs/editor-api/user/autocmd
   */
  on(event: AutocmdEvent, callback: (args: AutocmdCallbackArgs) => void): void;

  /**
   * Remove event listener for autocommand events.
   *
   * Note: Currently removes ALL listeners for the event.
   * The callback parameter is for API compatibility.
   *
   * @param event - Event name
   * @param callback - Callback to remove (currently unused)
   *
   * @example
   * vim.off('BufWritePre', myCallback);
   */
  off(event: AutocmdEvent, callback: (args: AutocmdCallbackArgs) => void): void;

  /**
   * Remove all listeners for an event.
   *
   * @param event - Event name
   *
   * @example
   * // Clean up all BufWritePre handlers
   * vim.removeAllListeners('BufWritePre');
   */
  removeAllListeners(event: AutocmdEvent): void;

  /**
   * Get number of listeners registered for an event.
   *
   * @param event - Event name
   * @returns Number of registered listeners
   *
   * @example
   * const count = vim.listenerCount('BufWritePre');
   * console.log(`${count} handlers for BufWritePre`);
   */
  listenerCount(event: AutocmdEvent): number;

  /**
   * Emit an event programmatically.
   *
   * Used for testing or triggering custom User events.
   *
   * @param event - Event name
   * @param args - Event arguments to pass to callbacks
   *
   * @example
   * // Trigger custom event
   * vim.emit('User', {
   *   id: 0,
   *   event: 'MyPluginEvent',
   *   group: null,
   *   match: '',
   *   buf: 0,
   *   file: '',
   *   data: { custom: 'data' }
   * });
   */
  emit(event: AutocmdEvent, args: AutocmdCallbackArgs): void;

  /**
   * Vimscript function bridge for calling built-in Vim functions.
   *
   * Allows calling Vim's built-in functions from JavaScript.
   *
   * @example
   * // Get full path of current file
   * const path = vim.fn.expand('%:p');
   *
   * @example
   * // Check if file exists
   * if (vim.fn.filereadable('/path/to/file')) {
   *   console.log('File exists');
   * }
   */
  fn: VimFunctions;

  /**
   * Diagnostic system for LSP-style error/warning display.
   *
   * Configure and manage diagnostics (errors, warnings, hints).
   *
   * @example
   * // Configure diagnostic display
   * vim.diagnostic.config({
   *   virtual_text: true,
   *   signs: true,
   *   underline: true
   * });
   */
  diagnostic: DiagnosticAPI;

  /**
   * E2E Testing API for plugin testing and interactive debugging.
   *
   * Only available when running `vimc test` command.
   * Provides Jest/Mocha-style test structure.
   *
   * @example
   * vim.e2e.describe('My Plugin', function() {
   *   vim.e2e.test('does something', function() {
   *     vim.e2e.keys('i');
   *     vim.e2e.assert.mode('INSERT');
   *   });
   * });
   * vim.e2e.runAll();
   */
  e2e: E2EAPI;

  /**
   * Zero-copy buffer content access.
   *
   * Provides efficient access to buffer content using ArrayBuffer.
   *
   * @example
   * const content = vim.buffer.getContent();
   * const text = new TextDecoder().decode(content);
   */
  buffer: BufferAPI;

  /**
   * Cursor motion primitives for programmatic movement.
   *
   * Used by animation plugins like smear-cursor.
   *
   * @example
   * vim.motion.down();  // Move cursor down (like 'j')
   * vim.motion.right(); // Move cursor right (like 'l')
   */
  motion: MotionAPI;

  /**
   * Cursor rendering API for animated cursor plugins.
   *
   * Override visual cursor position for smooth animations.
   *
   * @example
   * const pos = vim.cursor.getPosition();
   * vim.cursor.setRenderPosition(pos.row + 0.5, pos.col);
   */
  cursor: CursorAPI;

  /**
   * Virtual text layer API for rendering overlays.
   *
   * Create layers for diagnostics, git blame, inline hints, etc.
   *
   * @example
   * const layer = vim.layer.create('my-plugin');
   * vim.layer.setCell(layer, 0, 0, 'X', '#ff0000');
   */
  layer: LayerAPI;

  /**
   * Filetype detection using go-enry (GitHub Linguist).
   *
   * Detects programming language from filename/content.
   *
   * @example
   * const lang = vim.filetype.match({ filename: 'main.rs' });
   * console.log(lang); // 'Rust'
   */
  filetype: FiletypeAPI;

  /**
   * Tree-sitter API for syntax parsing and language injections.
   *
   * Provides Neovim-compatible tree-sitter functionality including:
   * - Parser management per buffer
   * - Language injection support (e.g., JS in Markdown code blocks)
   * - Query-based syntax highlighting
   *
   * @example
   * // Check if a language parser is available
   * if (vim.treesitter.hasParser('javascript')) {
   *   vim.treesitter.getLanguageTree(0, 'javascript');
   * }
   *
   * // Get the language at a specific byte position (useful for injections)
   * const lang = vim.treesitter.languageForRange(100, 200);
   */
  treesitter: TreesitterAPI;

  // Note: vim.loop is not needed - use global fs, fetch, process instead

  /**
   * LSP client interface.
   *
   * Provides high-level API for managing Language Server Protocol clients.
   * Built on process.spawn() with JSON-RPC 2.0 message framing.
   *
   * @example
   * ```typescript
   * const client = await vim.lsp.start({
   *   name: 'tsserver',
   *   cmd: ['typescript-language-server', '--stdio'],
   *   rootDir: '/path/to/project',
   * });
   *
   * client.on('textDocument/publishDiagnostics', (params) => {
   *   console.log('Diagnostics:', params.diagnostics);
   * });
   * ```
   *
   * @since Phase 5
   */
  lsp: LSP;

  /**
   * Tree-sitter integration for syntax parsing.
   *
   * @future Phase 5+ - Not yet implemented
   */
  treesitter?: TreeSitter;

  /**
   * Ex command methods.
   *
   * @example
   * vim.cmd.wincmd('h');           // Navigate to left window
   * vim.cmd.vsplit('file.txt');    // Vertical split
   * vim.cmd.write();               // Save file
   *
   * @example
   * // Set up Cmd+hjkl for window navigation
   * vim.keymap.set('n', '<D-h>', () => vim.cmd.wincmd('h'));
   * vim.keymap.set('n', '<D-j>', () => vim.cmd.wincmd('j'));
   * vim.keymap.set('n', '<D-k>', () => vim.cmd.wincmd('k'));
   * vim.keymap.set('n', '<D-l>', () => vim.cmd.wincmd('l'));
   */
  cmd: VimCmd;

  /**
   * Define syntax highlighting for a highlight group.
   *
   * Ergonomic wrapper for `vim.api.setHighlight()`.
   *
   * @param name - Highlight group name (e.g., 'Comment', 'Keyword')
   * @param opts - Styling options (fg, bg, bold, italic, etc.)
   *
   * @example
   * // Style comments as gray and italic
   * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
   *
   * @example
   * // Define cursor line background
   * vim.highlight('CursorLine', { bg: '#2e2e3e' });
   *
   * @example
   * // Bold keywords
   * vim.highlight('Keyword', { fg: '#c678dd', bold: true });
   */
  highlight(name: HighlightGroup, opts: HighlightOpts): void;

  /**
   * Create a namespace for organizing highlights and extmarks.
   *
   * @param name - Namespace name
   * @returns Namespace ID
   *
   * @example
   * const ns = vim.createNamespace('my-plugin');
   */
  createNamespace?(name: string): Namespace;

  /**
   * Schedule a function to run on the next event loop iteration.
   *
   * @param fn - Function to schedule
   */
  schedule?(fn: () => void): void;

  // Note: vim.defer_fn is not needed - use standard setTimeout() instead

  // =========================================================================
  // Leader Key
  // =========================================================================

  /**
   * The leader key for `<leader>` mappings.
   *
   * Set this BEFORE defining any `<leader>` keymaps.
   * Default is backslash (`\`).
   *
   * @example
   * // Set leader to space (common choice)
   * vim.mapleader = ' ';
   *
   * // Now define leader mappings
   * vim.keymap.set('n', '<leader>gp', () => previewHunk());
   * vim.keymap.set('n', '<leader>w', ':w<CR>');
   */
  mapleader: string;

  // =========================================================================
  // Variable Scopes
  // =========================================================================

  /**
   * Global variables (Vim's `g:` scope).
   *
   * Persist across buffers and sessions.
   *
   * @example
   * vim.g.mapleader = ' ';          // Set leader key
   * vim.g.loaded_netrw = 1;         // Disable netrw
   * vim.g.my_plugin_option = true;  // Custom variable
   */
  g: Record<string, any>;

  /**
   * Buffer-local variables (Vim's `b:` scope).
   *
   * Variables specific to the current buffer.
   *
   * @example
   * vim.b.my_var = 42;
   * console.log(vim.b.my_var); // 42
   */
  b: Record<string, any>;

  /**
   * Buffer-local options (Vim's `bo:` scope).
   *
   * Read/write buffer-specific options like filetype.
   *
   * @example
   * // Get filetype
   * const ft = vim.bo.filetype;
   * console.log(ft); // 'rust'
   *
   * @example
   * // Set filetype
   * vim.bo.filetype = 'markdown';
   */
  bo: {
    /**
     * Detected filetype (e.g., 'rust', 'javascript', 'python').
     * Set automatically based on file extension or content.
     */
    filetype?: string;
    /** Allow other buffer options */
    [key: string]: any;
  };

  /**
   * Window-local variables (Vim's `w:` scope).
   *
   * Variables specific to the current window.
   */
  w: Record<string, any>;

  /**
   * Tabpage-local variables (Vim's `t:` scope).
   *
   * Variables specific to the current tabpage.
   */
  t: Record<string, any>;

  /**
   * Vim variables (Vim's `v:` scope).
   *
   * Special Vim variables, mostly read-only.
   *
   * @example
   * console.log(vim.v.count);    // Count prefix for commands
   * console.log(vim.v.register); // Current register
   */
  v: Record<string, any>;

  /**
   * Environment variables.
   *
   * Access system environment variables.
   *
   * @example
   * const home = vim.env.HOME;
   * const path = vim.env.PATH;
   */
  env: Record<string, string>;

  /**
   * AI Infrastructure Layer.
   *
   * Provides infrastructure for AI features:
   * - `state`: Read-only editor state access
   * - `storage`: Pattern persistence (LMDB + usearch vectors)
   * - `providers`: LLM API abstraction (OpenAI, Anthropic, Ollama)
   * - `utils`: Utility functions (token estimation)
   *
   * NOTE: `vim.ai.native.*` is RESERVED for future LLM-native primitives:
   * - Pattern Space (navigate, compose, introspect)
   * - Context Flow (embedding streams, attention masks)
   * - Reality Interface (perceive, actuate, feedback loops)
   * - Meta-Cognition (uncertainty, reasoning traces)
   *
   * @example
   * // Get buffer content for AI prompt
   * const content = vim.ai.state.buffer();
   *
   * // Get current line for inline completion
   * const line = vim.ai.state.line();
   * const cursor = vim.ai.state.cursor();
   *
   * @example
   * // Configure provider and make request
   * vim.ai.providers.configure({ provider: 'anthropic', apiKey: '...' });
   * const json = vim.ai.providers.buildRequest({
   *   model: 'claude-3-sonnet-20240229',
   *   messages: [{ role: 'user', content: 'Hello!' }]
   * });
   */
  ai: {
    /**
     * Read-only access to editor state.
     * Use for gathering context to send to LLMs.
     */
    state: {
      /** Returns full buffer content as a string */
      buffer(): string;
      /** Returns selected text in visual mode, or empty string */
      selection(): string;
      /** Returns cursor position (0-indexed) */
      cursor(): { row: number; col: number };
      /** Returns current line content */
      line(): string;
      /** Returns line range (0-indexed, end exclusive) */
      lines(start?: number, end?: number): string[];
      /** Returns detected filetype (e.g., 'rust', 'typescript') */
      filetype(): string;
      /** Returns current filename/path */
      filename(): string;
      /** Returns total line count in buffer */
      lineCount(): number;
    };

    /**
     * Storage infrastructure for AI patterns and relationships.
     * Uses LMDB (key-value) + usearch (HNSW vectors).
     */
    storage: {
      /**
       * Pattern persistence with optional embeddings.
       * Stores patterns as JSON with optional vector embeddings for similarity search.
       */
      patterns: {
        /**
         * Save a pattern with optional embedding.
         * @param id - Unique pattern identifier
         * @param json - Pattern data as JSON string
         * @param embedding - Optional embedding vector for similarity search
         * @param tags - Tags for indexing
         * @param successRate - Optional success rate (0-1) for ranking
         */
        save(id: string, json: string, embedding: number[] | null, tags: string[], successRate?: number): boolean;
        /** Get pattern by ID */
        get(id: string): string | null;
        /** Delete pattern and all indexes */
        delete(id: string): boolean;
        /** Find patterns by tag */
        findByTag(tag: string): string[];
        /** Get storage statistics */
        stats(): { vectorCount: number; vectorMemoryBytes: number; vectorCapacity: number };
      };

      /**
       * Graph edges for relationships between patterns.
       * Uses DynamoDB-style key patterns for efficient traversal.
       */
      edges: {
        /** Add a relationship edge */
        add(from: string, rel: string, to: string, metadata?: string): boolean;
        /** Remove an edge */
        remove(from: string, rel: string, to: string): boolean;
        /** Get outgoing edges from a node */
        outgoing(from: string, rel?: string): Array<{ from: string; relationship: string; to: string; metadata: string }>;
        /** Get incoming edges to a node */
        incoming(to: string, rel?: string): Array<{ from: string; relationship: string; to: string; metadata: string }>;
      };

      /**
       * Conversation history persistence.
       * Store and retrieve conversation messages in timestamp order.
       */
      conversations: {
        /**
         * Add a message to a conversation.
         * @param convId - Unique conversation identifier
         * @param timestamp - Unix timestamp in milliseconds
         * @param messageJson - Message as JSON string (e.g., {role, content})
         *
         * @example
         * vim.ai.storage.conversations.add('conv-1', Date.now(), JSON.stringify({
         *   role: 'user',
         *   content: 'Hello!'
         * }));
         */
        add(convId: string, timestamp: number, messageJson: string): boolean;

        /**
         * Get all messages in a conversation (in timestamp order).
         * @param convId - Conversation identifier
         * @returns Array of message JSON strings
         *
         * @example
         * const messages = vim.ai.storage.conversations.get('conv-1');
         * messages.forEach(json => {
         *   const msg = JSON.parse(json);
         *   console.log(`${msg.role}: ${msg.content}`);
         * });
         */
        get(convId: string): string[];
      };
    };

    /**
     * LLM provider abstraction.
     * Supports OpenAI, Anthropic, and Ollama with unified request/response format.
     */
    providers: {
      /**
       * Configure the provider.
       * @example
       * vim.ai.providers.configure({
       *   provider: 'anthropic',
       *   apiKey: process.env.ANTHROPIC_API_KEY,
       * });
       */
      configure(config: { provider: 'openai' | 'anthropic' | 'ollama' | 'custom'; apiKey: string; baseUrl?: string }): boolean;
      /** Build request JSON for the configured provider */
      buildRequest(request: {
        model: string;
        messages: Array<{ role: 'system' | 'user' | 'assistant' | 'tool'; content: string }>;
        temperature?: number;
        maxTokens?: number;
        stream?: boolean;
      }): string;
      /** Get the chat endpoint URL */
      getEndpoint(): string;
      /** Get required headers for API calls */
      getHeaders(): Array<{ name: string; value: string }>;
      /** Parse provider response JSON into unified format */
      parseResponse(json: string): {
        id: string;
        model: string;
        content?: string;
        finishReason: 'stop' | 'length' | 'tool_calls' | 'content_filter' | 'unknown';
        usage: { promptTokens: number; completionTokens: number; totalTokens: number };
      };
    };

    /**
     * Utility functions for AI features.
     */
    utils: {
      /**
       * Estimate tokens for text (heuristic: ~4 chars per token).
       * Useful for context limit checks before sending to LLM.
       */
      estimateTokens(text: string): number;

      /**
       * Get the last error message from AI storage/provider operations.
       * Returns null if no error has occurred.
       *
       * @example
       * const success = vim.ai.storage.patterns.save('id', '{}', null, ['tag'], 0.5);
       * if (!success) {
       *   console.error('Save failed:', vim.ai.utils.getLastError());
       * }
       */
      getLastError(): string | null;
    };
  };
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
