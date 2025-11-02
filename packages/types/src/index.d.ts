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
  /** Bold text */
  bold?: boolean;
  /** Italic text */
  italic?: boolean;
  /** Underline text */
  underline?: boolean;
}

/**
 * Editor options (vim.opt)
 */
export interface VimOptions {
  /** Enable cursor line highlighting */
  cursorline: boolean;

  // Future options
  // number?: boolean;
  // relativenumber?: boolean;
  // tabstop?: number;
  // shiftwidth?: number;
  // expandtab?: boolean;
}

/**
 * Main vim global interface
 */
export interface Vim {
  /**
   * Define syntax highlighting for a group
   * @param name - Highlight group name (e.g., 'CursorLine', 'LineNr')
   * @param opts - Styling options (bg, fg, bold, etc.)
   *
   * @example
   * vim.highlight('CursorLine', { bg: '#2b2b2b' });
   * vim.highlight('Comment', { fg: '#6c6c6c', italic: true });
   */
  highlight(name: string, opts: HighlightOpts): void;

  /**
   * Editor options
   *
   * @example
   * vim.opt.cursorline = true;
   */
  opt: VimOptions;
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
