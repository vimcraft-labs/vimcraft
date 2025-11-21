// Vimcraft TypeScript Type Definitions
// Auto-generated types for Vimcraft editor configuration

// ============================================
// User Command Types (Neovim-compatible with TypeScript enhancements)
// ============================================

/**
 * Base command arguments (always present in callback)
 */
interface CommandArgsBase {
  /** The command name that was invoked */
  name: string;
  /** Raw arguments string (everything after command name) */
  args: string;
  /** Arguments split by whitespace */
  fargs: string[];
  /** Whether ! was used (e.g., :MyCmd!) */
  bang: boolean;
  /** Command modifiers string (e.g., "silent", "vertical") */
  mods: string;
}

/**
 * Range information (present when range/count option specified)
 */
interface CommandRangeArgs {
  /** Start line of range (1-indexed) */
  line1: number;
  /** End line of range (1-indexed) */
  line2: number;
  /** Range type: 0=none, 1=one line, 2=two lines */
  range: 0 | 1 | 2;
}

/**
 * Count information (present when count option specified)
 */
interface CommandCountArgs {
  /** Count value (e.g., 5 in :5MyCmd) */
  count: number;
}

/**
 * Register information (present when register: true)
 */
interface CommandRegisterArgs {
  /** Register name (e.g., "a" for "a register) */
  reg: string;
}

/**
 * Command options - controls command behavior and callback argument types
 */
interface UserCommandOpts {
  /** Command description (shown in :command output) */
  desc?: string;
  /** Allow bang modifier (:MyCmd!) */
  bang?: boolean;
  /** Allow bar separator (:MyCmd | other) */
  bar?: boolean;
  /** Force overwrite existing command */
  force?: boolean;
  /**
   * Range specification:
   * - true or '%': Defaults to whole file
   * - number: Default count value
   */
  range?: boolean | '%' | number;
  /**
   * Count specification:
   * - number: Default count value
   */
  count?: number;
  /** Accept register argument */
  register?: boolean;
  /**
   * Number of arguments:
   * - '0': No arguments
   * - '1': Exactly one argument
   * - '*': Any number (0+)
   * - '?': Zero or one
   * - '+': One or more
   */
  nargs?: '0' | '1' | '*' | '?' | '+';
  /**
   * Completion function or built-in type
   */
  complete?: string | ((argLead: string, cmdLine: string, cursorPos: number) => string[]);
}

/**
 * Infer callback argument type from options
 * TypeScript magic: adds range/count/register args only when options specify them
 */
type InferCommandArgs<Opts extends UserCommandOpts> = CommandArgsBase
  & (Opts extends { range: any } ? CommandRangeArgs : {})
  & (Opts extends { count: number } ? CommandCountArgs : {})
  & (Opts extends { register: true } ? CommandRegisterArgs : {});

/**
 * Full command arguments (when all options enabled)
 */
type CommandArgs = CommandArgsBase & CommandRangeArgs & CommandCountArgs & CommandRegisterArgs;

declare global {
  /**
   * Vim API namespace - Neovim-compatible API for editor configuration
   */
  const vim: {
    /**
     * Set highlight group colors
     * @param name - Highlight group name (e.g., "Normal", "CursorLine")
     * @param opts - Highlight options
     */
    highlight(name: string, opts: {
      fg?: string;
      bg?: string;
      bold?: boolean;
      italic?: boolean;
      underline?: boolean;
    }): void;

    /**
     * Editor options (vim.opt interface)
     * Supports both reading and writing via property access
     */
    opt: {
      // Display options
      number: boolean;
      relativenumber: boolean;
      cursorline: boolean;
      cursorcolumn: boolean;
      signcolumn: string; // "yes" | "no" | "auto" | "auto:1-9"
      colorcolumn: string;
      wrap: boolean;
      linebreak: boolean;
      list: boolean;
      listchars: string | {
        tab?: string;
        space?: string;
        trail?: string;
        eol?: string;
        nbsp?: string;
      }; // String format: "tab:→·,space:·,trail:~,eol:↵" or Object format: { tab: "→·", space: "·" }
      scrolloff: number;
      sidescrolloff: number;

      // Editing options
      tabstop: number;
      shiftwidth: number;
      expandtab: boolean;
      autoindent: boolean;
      smartindent: boolean;
      textwidth: number;

      // Behavior options
      mouse: string;
      clipboard: string;
      undolevels: number;
      timeout: boolean;
      timeoutlen: number;
      updatetime: number;

      // Search options
      ignorecase: boolean;
      smartcase: boolean;
      hlsearch: boolean;
      incsearch: boolean;

      // UI options
      laststatus: number; // 0=never, 1=only if multiple windows, 2=always, 3=global
      showcmd: boolean;
      showmode: boolean;
      ruler: boolean;

      // Shorthand aliases
      nu: boolean; // alias for number
      rnu: boolean; // alias for relativenumber
      cul: boolean; // alias for cursorline
      cuc: boolean; // alias for cursorcolumn
      scl: string; // alias for signcolumn
      cc: string; // alias for colorcolumn
      lcs: string | {
        tab?: string;
        space?: string;
        trail?: string;
        eol?: string;
        nbsp?: string;
      }; // alias for listchars
      ts: number; // alias for tabstop
      sw: number; // alias for shiftwidth
      et: boolean; // alias for expandtab
      ai: boolean; // alias for autoindent
      si: boolean; // alias for smartindent
      tw: number; // alias for textwidth
      ic: boolean; // alias for ignorecase
      scs: boolean; // alias for smartcase
      hls: boolean; // alias for hlsearch
      is: boolean; // alias for incsearch
      to: boolean; // alias for timeout
      tm: number; // alias for timeoutlen
      ul: number; // alias for undolevels
      cb: string; // alias for clipboard
      so: number; // alias for scrolloff
      siso: number; // alias for sidescrolloff
      lbr: boolean; // alias for linebreak
      sc: boolean; // alias for showcmd
      smd: boolean; // alias for showmode
      ru: boolean; // alias for ruler
    };

    /**
     * Motion API - Programmatic cursor movement
     */
    motion: {
      left(): void;
      right(): void;
      up(): void;
      down(): void;
      wordForward(): void;
      wordBackward(): void;
      lineStart(): void;
      lineEnd(): void;
      firstNonBlank(): void;
      fileStart(): void;
      fileEnd(): void;
      pageDown(): void;
      pageUp(): void;
    };

    /**
     * Layer API - Manage virtual text layers for overlays
     */
    layer: {
      /**
       * Create a new layer
       * @param name - Unique layer name
       * @param zIndex - Z-order (0-1000, higher = on top)
       * @returns Layer ID
       */
      create(name: string, zIndex: number): number;

      /**
       * Set text on a layer at a specific position
       * @param layerId - Layer ID from create()
       * @param row - Row (0-indexed)
       * @param col - Column (0-indexed)
       * @param text - Text to display
       * @param fg - Foreground color (hex string)
       * @param bg - Background color (hex string)
       */
      setText(
        layerId: number,
        row: number,
        col: number,
        text: string,
        fg?: string,
        bg?: string
      ): void;

      /**
       * Clear all text from a layer
       * @param layerId - Layer ID
       */
      clear(layerId: number): void;

      /**
       * Enable or disable a layer
       * @param layerId - Layer ID
       * @param enabled - Whether layer should be visible
       */
      setEnabled(layerId: number, enabled: boolean): void;

      /**
       * Mark layer as dirty (needs re-render)
       * @param layerId - Layer ID
       */
      markDirty(layerId: number): void;
    };

    /**
     * Get current gutter width (line numbers + signs)
     * Useful for positioning virtual text
     */
    getGutterWidth(): number;

    /**
     * Get current cursor position
     * @returns {row: number, col: number}
     */
    getCursor(): { row: number; col: number };

    /**
     * Timer functions (Neovim-compatible)
     */
    defer_fn(callback: () => void, delay: number): number;
    loop: {
      /**
       * Create a timer that executes callback at specified interval
       * @param callback - Function to execute
       * @param interval - Interval in milliseconds
       * @returns Timer ID
       */
      new_timer(): {
        start(interval: number, repeat: number, callback: () => void): void;
        stop(): void;
        close(): void;
      };
    };

    /**
     * Animation frame callback (60fps)
     * @param callback - Function to execute on each frame
     * @returns Request ID (for cancellation)
     */
    requestAnimationFrame(callback: (timestamp: number) => void): number;

    /**
     * Cancel animation frame
     * @param id - Request ID from requestAnimationFrame
     */
    cancelAnimationFrame(id: number): void;

    /**
     * Performance Metrics API (only available with --metrics flag)
     * Provides startup time, plugin load times, and other performance data
     * All properties return 0 or empty array if metrics are disabled
     */
    metrics?: {
      /**
       * Time from process start to first render (milliseconds)
       */
      readonly startupTime: number;

      /**
       * Time to initialize Hermes JavaScript runtime (milliseconds)
       */
      readonly hermesInitTime: number;

      /**
       * Time to load configuration files (milliseconds)
       */
      readonly configLoadTime: number;

      /**
       * Time since process started (milliseconds)
       */
      readonly uptime: number;

      /**
       * Number of plugins loaded
       */
      readonly pluginCount: number;

      /**
       * Plugin load times with names
       */
      readonly pluginLoadTimes: Array<{
        name: string;
        duration_ms: number;
      }>;
    };

    /**
     * Neovim-compatible API functions
     */
    api: {
      // ============================================
      // User Commands
      // ============================================

      /**
       * Create a user command with type-safe callback arguments
       *
       * @example
       * // Basic command - callback gets CommandArgsBase
       * vim.api.createUserCommand('Greet', (args) => {
       *   console.log(`Hello from ${args.name}, args: ${args.args}`);
       * });
       *
       * @example
       * // With range - callback gets CommandArgsBase & CommandRangeArgs
       * vim.api.createUserCommand('Format', (args) => {
       *   // TypeScript knows args.line1 and args.line2 exist!
       *   formatLines(args.line1, args.line2);
       * }, { range: '%' });
       *
       * @example
       * // With register - callback gets CommandArgsBase & CommandRegisterArgs
       * vim.api.createUserCommand('Yank', (args) => {
       *   // TypeScript knows args.reg exists!
       *   yankToRegister(args.reg);
       * }, { register: true });
       */
      createUserCommand<Opts extends UserCommandOpts>(
        name: string,
        callback: (args: InferCommandArgs<Opts>) => void,
        opts?: Opts
      ): void;

      /**
       * Delete a user command
       * @param name - Command name to delete
       */
      delUserCommand(name: string): void;

      /**
       * Create a buffer-local user command
       * @param buffer - Buffer number (0 for current buffer)
       * @param name - Command name (must start with uppercase)
       * @param callback - Command callback
       * @param opts - Command options
       */
      bufCreateUserCommand<Opts extends UserCommandOpts>(
        buffer: number,
        name: string,
        callback: (args: InferCommandArgs<Opts>) => void,
        opts?: Opts
      ): void;

      /**
       * Delete a buffer-local user command
       * @param buffer - Buffer number (0 for current buffer)
       * @param name - Command name to delete
       */
      bufDelUserCommand(buffer: number, name: string): void;

      /**
       * Get list of user commands
       * @param opts - Filter options
       * @returns Array of command info objects
       */
      getUserCommands(opts?: { builtin?: boolean }): Array<{
        name: string;
        definition: string;
        nargs: string;
        range: string;
        complete: string;
        bang: boolean;
        bar: boolean;
        register: boolean;
        buffer: number;
      }>;

      // ============================================
      // Autocommands (existing)
      // ============================================

      /**
       * Create an autocommand
       * @param event - Event name or array of event names
       * @param opts - Autocommand options
       * @returns Autocommand ID
       */
      createAutocmd(
        event: string | string[],
        opts: {
          pattern?: string | string[];
          callback?: () => void;
          command?: string;
          group?: string;
          once?: boolean;
          nested?: boolean;
          desc?: string;
        }
      ): number;

      /**
       * Delete an autocommand by ID
       * @param id - Autocommand ID from createAutocmd
       */
      delAutocmd(id: number): void;

      /**
       * Create an autocommand group
       * @param name - Group name
       * @param opts - Group options
       * @returns Group name
       */
      createAugroup(name: string, opts?: { clear?: boolean }): string;

      /**
       * Clear autocommands matching criteria
       * @param opts - Filter options
       */
      clearAutocmds(opts: {
        event?: string | string[];
        group?: string;
        pattern?: string | string[];
        buffer?: number;
      }): void;
    };
  };

  /**
   * Console API - Logging to Chrome DevTools or terminal
   */
  const console: {
    log(...args: any[]): void;
    error(...args: any[]): void;
    warn(...args: any[]): void;
    info(...args: any[]): void;
    debug(...args: any[]): void;
  };

  /**
   * Timer functions (Node.js-compatible)
   */
  function setTimeout(callback: () => void, delay: number): number;
  function setInterval(callback: () => void, interval: number): number;
  function clearTimeout(id: number): void;
  function clearInterval(id: number): void;
}

export {};
