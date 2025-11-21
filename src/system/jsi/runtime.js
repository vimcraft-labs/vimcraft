// console object (for debugging) - make it global for plugins!
// React Native approach: Pass raw JavaScript values to native
// Native code will:
//   1. Send raw values to Chrome DevTools (for interactive inspection)
//   2. Convert to strings for text logs (for LLM/file logging)
globalThis.console = {
  log: function(...args) {
    // Pass raw values to native - don't stringify!
    // This allows Chrome DevTools to show expandable objects
    consoleLog(...args);
  }
};

// Timer Registry (React Native pattern - keeps callbacks alive in JS!)
// This prevents garbage collection of timer callbacks
// Make these global so plugins can use setTimeout/setInterval!
globalThis._timerCallbacks = {};
globalThis._nextTimerId = 1;

// Timer functions (setTimeout, setInterval, clearTimeout, clearInterval)
// Make them global so plugins can use them!
globalThis.setTimeout = function(callback, delay) {
  const id = globalThis._nextTimerId++;
  globalThis._timerCallbacks[id] = callback;
  __nativeSetTimeout(id, delay || 0);
  return id;
};

globalThis.setInterval = function(callback, delay) {
  const id = globalThis._nextTimerId++;
  globalThis._timerCallbacks[id] = callback;
  __nativeSetInterval(id, delay || 0);
  return id;
};

globalThis.clearTimeout = function(id) {
  delete globalThis._timerCallbacks[id];
  __nativeClearTimer(id);
};

globalThis.clearInterval = function(id) {
  delete globalThis._timerCallbacks[id];
  __nativeClearTimer(id);
};

// Called by native code when timer fires
globalThis.__handleTimerCallback = function(id) {
  const callback = globalThis._timerCallbacks[id];
  if (callback) {
    try {
      callback();
    } catch (e) {
      globalThis.console.log('Timer callback error:', e);
    }
  }
};

// Animation Frame Registry (React Native Reanimated pattern)
globalThis._animationFrameCallbacks = {};
globalThis._nextAnimationFrameId = 1;

// requestAnimationFrame (browser API + Reanimated worklets)
// Runs callback on next render frame for smooth 60fps animations
globalThis.requestAnimationFrame = function(callback) {
  const id = globalThis._nextAnimationFrameId++;
  globalThis._animationFrameCallbacks[id] = callback;
  __nativeRequestAnimationFrame(id);
  return id;
};

// cancelAnimationFrame (browser API)
globalThis.cancelAnimationFrame = function(id) {
  delete globalThis._animationFrameCallbacks[id];
  // Note: Native side auto-clears after callback runs
};

// Called by native code on render frame
globalThis.__handleAnimationFrame = function(id) {
  const callback = globalThis._animationFrameCallbacks[id];
  if (callback) {
    // Remove callback (animation frame is one-shot)
    delete globalThis._animationFrameCallbacks[id];

    try {
      callback();
    } catch (e) {
      globalThis.console.log('Animation frame callback error:', e);
    }
  }
};

// Performance API (React Native style)
// This enables Chrome DevTools Performance timeline!
globalThis.performance = {
  _marks: {},
  _measures: [],
  now: function() {
    return Date.now(); // Milliseconds since epoch
  },
  mark: function(name) {
    this._marks[name] = this.now();
  },
  measure: function(name, startMark, endMark) {
    const start = this._marks[startMark] || 0;
    const end = endMark ? (this._marks[endMark] || this.now()) : this.now();
    const duration = end - start;
    this._measures.push({ name, duration, startTime: start });
  },
  clearMarks: function(name) {
    if (name) delete this._marks[name];
    else this._marks = {};
  },
  getEntriesByType: function(type) {
    if (type === 'measure') return this._measures;
    return [];
  }
};

// vim API object - make it global for plugins!
globalThis.vim = {
  // Convenience wrapper for vim.api.setHighlight (Neovim compatibility)
  // vim.highlight("Function", { fg: "#61AFEF", bold: true })
  highlight: function(name, opts) {
    vimApiSetHighlight(0, name, opts);
  },
  // Dynamic options proxy - handles ANY option via HostObject properties
  // Supports both camelCase (JavaScript style) and lowercase (Vim style)
  opt: new Proxy(
    // Pre-populate target with all options for Chrome DevTools
    // This ensures Chrome DevTools can enumerate properties without calling ownKeys
    (() => {
      const target = {
        get [Symbol.toStringTag]() { return 'vim.opt'; }
      };
      // Populate with all options from Zig HostObject
      const allOptions = getAllOptions();
      Object.assign(target, allOptions);
      return target;
    })(),
    {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.opt';
      if (typeof prop === 'symbol') return undefined;
      // Direct HostObject property access (zero-copy JSI)
      return vimOpt[prop];
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: convert object to string format
      if ((prop === 'listchars' || prop === 'lcs') && typeof value === 'object' && value !== null) {
        // Convert { tab: "→·", space: "·", trail: "~" } to "tab:→·,space:·,trail:~"
        const parts = [];
        for (const [key, val] of Object.entries(value)) {
          if (typeof val === 'string' && val.length > 0) {
            parts.push(`${key}:${val}`);
          }
        }
        value = parts.join(',');
      }

      // Direct HostObject property write (zero-copy JSI)
      vimOpt[prop] = value;
      // Note: DO NOT update target here - it creates stale cache
      // Target is refreshed via ownKeys trap when Chrome DevTools enumerates
      // Zig HostObject is the single source of truth
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return vimOpt[prop] !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache (except Symbol.toStringTag getter)
      for (const key of Object.keys(target)) {
        delete target[key];
      }

      // Single JSI call to get ALL set options
      const allOptions = getAllOptions();
      Object.assign(target, allOptions);

      return Object.keys(target);
    },
    getOwnPropertyDescriptor(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      // Fetch fresh value from HostObject
      const value = vimOpt[prop];
      if (value === undefined) return undefined;
      return {
        value: value,
        enumerable: true,
        configurable: true,
        writable: true
      };
    }
  }),
  // Buffer-local options (vim.optLocal)
  // Neovim equivalent: vim.opt_local
  // Gets buffer-local value first, falls back to global
  optLocal: new Proxy(
    // Pre-populate target with all options for Chrome DevTools
    (() => {
      const target = {
        get [Symbol.toStringTag]() { return 'vim.optLocal'; }
      };
      const allOptions = getAllOptionsWithScope('local');
      Object.assign(target, allOptions);
      return target;
    })(),
    {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.optLocal';
      if (typeof prop === 'symbol') return undefined;
      // Direct HostObject property access (zero-copy JSI)
      return vimOptLocal[prop];
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: convert object to string format
      if ((prop === 'listchars' || prop === 'lcs') && typeof value === 'object' && value !== null) {
        const parts = [];
        for (const [key, val] of Object.entries(value)) {
          if (typeof val === 'string' && val.length > 0) {
            parts.push(`${key}:${val}`);
          }
        }
        value = parts.join(',');
      }

      // Direct HostObject property write (zero-copy JSI)
      vimOptLocal[prop] = value;
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return vimOptLocal[prop] !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache (except Symbol.toStringTag getter)
      for (const key of Object.keys(target)) {
        delete target[key];
      }

      // Single JSI call to get ALL set options in local scope
      const allOptions = getAllOptionsWithScope('local');
      Object.assign(target, allOptions);

      return Object.keys(target);
    },
    getOwnPropertyDescriptor(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      // Fetch fresh value from HostObject
      const value = vimOptLocal[prop];
      if (value === undefined) return undefined;
      return {
        value: value,
        enumerable: true,
        configurable: true,
        writable: true
      };
    }
  }),
  // Global options (vim.optGlobal)
  // Neovim equivalent: vim.opt_global
  // Always gets/sets global value (no buffer-local fallback)
  optGlobal: new Proxy(
    // Pre-populate target with all options for Chrome DevTools
    (() => {
      const target = {
        get [Symbol.toStringTag]() { return 'vim.optGlobal'; }
      };
      const allOptions = getAllOptionsWithScope('global');
      Object.assign(target, allOptions);
      return target;
    })(),
    {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.optGlobal';
      if (typeof prop === 'symbol') return undefined;
      // Direct HostObject property access (zero-copy JSI)
      return vimOptGlobal[prop];
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: convert object to string format
      if ((prop === 'listchars' || prop === 'lcs') && typeof value === 'object' && value !== null) {
        const parts = [];
        for (const [key, val] of Object.entries(value)) {
          if (typeof val === 'string' && val.length > 0) {
            parts.push(`${key}:${val}`);
          }
        }
        value = parts.join(',');
      }

      // Direct HostObject property write (zero-copy JSI)
      vimOptGlobal[prop] = value;
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return vimOptGlobal[prop] !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache (except Symbol.toStringTag getter)
      for (const key of Object.keys(target)) {
        delete target[key];
      }

      // Single JSI call to get ALL set options in global scope
      const allOptions = getAllOptionsWithScope('global');
      Object.assign(target, allOptions);

      return Object.keys(target);
    },
    getOwnPropertyDescriptor(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      // Fetch fresh value from HostObject
      const value = vimOptGlobal[prop];
      if (value === undefined) return undefined;
      return {
        value: value,
        enumerable: true,
        configurable: true,
        writable: true
      };
    }
  }),
  // Buffer-local options (vim.bo)
  // Neovim equivalent: vim.bo
  // Provides access to buffer-specific properties like filetype
  bo: new Proxy(
    {
      get [Symbol.toStringTag]() { return 'vim.bo'; }
    },
    {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.bo';
      if (typeof prop === 'symbol') return undefined;
      // Direct HostObject property access (zero-copy JSI)
      return vimBo[prop];
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;
      // Direct HostObject property write (zero-copy JSI)
      vimBo[prop] = value;
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return vimBo[prop] !== undefined;
    },
    ownKeys(target) {
      // Return known buffer options
      return ['filetype'];
    },
    getOwnPropertyDescriptor(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      // Fetch fresh value from HostObject
      const value = vimBo[prop];
      if (value === undefined) return undefined;
      return {
        value: value,
        enumerable: true,
        configurable: true,
        writable: true
      };
    }
  })
};

// vim.cursor API - Expose cursor HostObject methods (if available)
// Allows animated cursor plugins to query and override cursor position
// Direct HostObject access (zero-copy JSI)
// Note: Not available in headless mode (debug protocol)
if (typeof vimCursor !== 'undefined') {
  vim.cursor = vimCursor;
}

// vim.layer API - Expose layer HostObject methods
// Allows plugins to create custom rendering layers (Neovim-style extmarks)
// Direct HostObject access (zero-copy JSI)
vim.layer = vimLayer;

// vim.motion API - Expose motion HostObject methods
// Allows plugins to programmatically trigger cursor movement
// Direct HostObject access (zero-copy JSI)
vim.motion = vimMotion;

// Legacy motion wrappers for backwards compatibility
// TODO: Remove after all examples updated to use vim.motion HostObject
const _legacyMotion = {
  // Character motion (h/j/k/l)
  left: function() { moveLeft(); },
  right: function() { moveRight(); },
  up: function() { moveUp(); },
  down: function() { moveDown(); },

  // Line motion (0/$^)
  toLineStart: function() { moveToLineStart(); },
  toLineEnd: function() { moveToLineEnd(); },
  toFirstNonBlank: function() { moveToFirstNonBlank(); },

  // Word motion (w/b/e)
  wordForward: function() { moveWordForward(); },
  wordBackward: function() { moveWordBackward(); },
  wordEnd: function() { moveWordEnd(); },

  // File motion (gg/G)
  toFileStart: function() { moveToFileStart(); },
  toFileEnd: function() { moveToFileEnd(); },

  // Viewport motion (H/M/L)
  toViewportTop: function() { moveToViewportTop(); },
  toViewportMiddle: function() { moveToViewportMiddle(); },
  toViewportBottom: function() { moveToViewportBottom(); },

  // Scrolling (Ctrl+D/U)
  scrollHalfPageDown: function() { scrollHalfPageDown(); },
  scrollHalfPageUp: function() { scrollHalfPageUp(); },
};

// Freeze to prevent modifications
Object.freeze(vim.motion);

// vim.keymap API - Expose keymap HostObject methods
// Allows users to create custom key mappings (Neovim compatible)
// Direct HostObject access (zero-copy JSI)
// vim.keymap.set(mode, lhs, rhs, opts)
// mode: string ('n', 'i', 'v', 'c')
// lhs: string (key to map, e.g., 'H', '<leader>w')
// rhs: string or function (command to execute or callback)
// opts: object { noremap: bool, silent: bool, buffer: bool }
// vim.keymap.del(mode, lhs)
// mode: string ('n', 'i', 'v', 'c')
// lhs: string (key to unmap)
vim.keymap = vimKeymap;

Object.freeze(vim.keymap);

// vim.filetype API - Filetype detection (Neovim compatible)
// Uses go-enry for GitHub Linguist-based language detection (697 languages)
// Direct HostObject access (zero-copy JSI)
// vim.filetype.match(opts)
// opts: { filename: string } or { buf: number }
// returns: string (language like "Rust", "JavaScript") or null (unknown)
vim.filetype = vimFiletype;

Object.freeze(vim.filetype);

// vim.buffer API - Buffer content access (zero-copy External ArrayBuffer)
// Direct HostObject access (zero-copy JSI)
//
// vim.buffer.getContent() -> ArrayBuffer
//   Returns entire buffer as External ArrayBuffer (zero-copy!)
//   Usage:
//     const ab = vim.buffer.getContent();          // ArrayBuffer
//     const view = new Uint8Array(ab);             // View into native memory
//     const text = new TextDecoder().decode(view); // Convert to string
//
// vim.buffer.getLineContent(line_num) -> ArrayBuffer
//   Returns single line as External ArrayBuffer (zero-copy!)
//   Usage:
//     const ab = vim.buffer.getLineContent(5);     // Line 5
//     const view = new Uint8Array(ab);
//     const text = new TextDecoder().decode(view);
//
// vim.buffer.getLength() -> number (byte length)
// vim.buffer.getLineCount() -> number (line count)
//
// ⚠️  IMPORTANT: ArrayBuffers are SNAPSHOTS!
//    Invalidated when buffer is modified (insert/delete/realloc)
//    Safe pattern: Copy immediately with new Uint8Array(ab).slice()
//
// Performance: 25x faster than string marshaling (80μs vs 2ms for 1MB)
// Only register buffer API if vimBuffer exists (Editor mode, not EditorContext)
if (typeof vimBuffer !== 'undefined') {
  vim.buffer = vimBuffer;
  Object.freeze(vim.buffer);
}

// vim.api - Neovim-compatible API functions
// Provides compatibility layer for Neovim plugins
vim.api = {
  // vim.api.setHighlight(ns_id, name, opts)
  //   ns_id: number (namespace ID, 0 for global)
  //   name: string (highlight group name, e.g., "Function", "@function", "ui.text")
  //   opts: object (highlight definition)
  //     - fg: string (foreground color, "#ff0000" or "124")
  //     - bg: string (background color)
  //     - sp: string (special color for underline)
  //     - bold: boolean
  //     - italic: boolean
  //     - underline: boolean
  //     - undercurl: boolean
  //     - strikethrough: boolean
  //     - link: string (link to another group, e.g., "Function")
  //
  // Examples:
  //   vim.api.setHighlight(0, "Function", { fg: "#61AFEF", bold: true });
  //   vim.api.setHighlight(0, "@function", { link: "Function" });
  //   vim.api.setHighlight(0, "ui.text.focus", { fg: "#FFFFFF", bg: "#3E4452" });
  setHighlight: function(ns_id, name, opts) {
    vimApiSetHighlight(ns_id, name, opts);
  },

  // vim.api.getHighlight(ns_id, name)
  //   ns_id: number (namespace ID, 0 for global)
  //   name: string (highlight group name)
  //   returns: object (highlight definition) or undefined
  //
  // Example:
  //   const hl = vim.api.getHighlight(0, "Function");
  //   // Returns: { fg: "#61afef", bold: true }
  getHighlight: function(ns_id, name) {
    return vimApiGetHighlight(ns_id, name);
  },

  // vim.api.createAutocmd(event, opts)
  //   event: string | string[] - Event name(s) to trigger on
  //   opts: object - Configuration options
  //     - callback: function (required) - Callback function called when event fires
  //     - pattern: string - File pattern to match (e.g., "*.js", "*.ts")
  //     - group: string - Autocommand group name
  //     - once: boolean - Remove autocommand after first execution
  //     - desc: string - Description for :autocmd listing
  //   returns: number (autocmd ID for deletion)
  //
  // Events:
  //   BufEnter, BufLeave, BufRead, BufWrite, BufWritePre, BufWritePost,
  //   FileType, InsertEnter, InsertLeave, ModeChanged, CursorMoved, etc.
  //
  // Examples:
  //   vim.api.createAutocmd('BufEnter', {
  //       pattern: '*.js',
  //       callback: (ev) => console.log('Entered JS file:', ev.file),
  //   });
  //
  //   vim.api.createAutocmd(['BufRead', 'BufNewFile'], {
  //       pattern: ['*.ts', '*.tsx'],
  //       group: 'typescript',
  //       callback: (ev) => { /* setup TypeScript */ },
  //   });
  createAutocmd: function(event, opts) {
    if (typeof vimApiCreateAutocmd !== 'undefined') {
      return vimApiCreateAutocmd(event, opts);
    }
    throw new Error('createAutocmd not available (headless mode)');
  },

  // vim.api.delAutocmd(id)
  //   id: number - Autocommand ID (returned by createAutocmd)
  //
  // Example:
  //   const id = vim.api.createAutocmd('BufEnter', { callback: () => {} });
  //   vim.api.delAutocmd(id);
  delAutocmd: function(id) {
    if (typeof vimApiDelAutocmd !== 'undefined') {
      return vimApiDelAutocmd(id);
    }
    throw new Error('delAutocmd not available (headless mode)');
  },

  // vim.api.createAugroup(name, opts)
  //   name: string - Group name
  //   opts: object (optional)
  //     - clear: boolean - Clear all autocmds in group first
  //   returns: string (group name)
  //
  // Example:
  //   vim.api.createAugroup('my_plugin', { clear: true });
  //   vim.api.createAutocmd('BufEnter', {
  //       group: 'my_plugin',
  //       callback: () => {},
  //   });
  createAugroup: function(name, opts) {
    if (typeof vimApiCreateAugroup !== 'undefined') {
      return vimApiCreateAugroup(name, opts || {});
    }
    throw new Error('createAugroup not available (headless mode)');
  },

  // vim.api.clearAutocmds(opts)
  //   opts: object
  //     - group: string - Clear all autocmds in group
  //
  // Example:
  //   vim.api.clearAutocmds({ group: 'my_plugin' });
  clearAutocmds: function(opts) {
    if (typeof vimApiClearAutocmds !== 'undefined') {
      return vimApiClearAutocmds(opts || {});
    }
    throw new Error('clearAutocmds not available (headless mode)');
  }
};

Object.freeze(vim.api);

// Event API - Expose vimEventEmitter methods on vim object
// Allows plugins to use vim.on('BufWritePre', callback) syntax
// Direct HostObject method forwarding (zero-copy JSI)
if (typeof vimEventEmitter !== 'undefined') {
  vim.on = vimEventEmitter.on;
  vim.off = vimEventEmitter.off;
  vim.emit = vimEventEmitter.emit;
  vim.removeAllListeners = vimEventEmitter.removeAllListeners;
  vim.listenerCount = vimEventEmitter.listenerCount;
}

// vim.metrics API - Performance metrics (only available with --metrics flag)
// Provides startup time, plugin load times, and other performance data
// Direct HostObject property access (zero-copy JSI)
//
// vim.metrics.startupTime     -> number (ms from process start to first render)
// vim.metrics.hermesInitTime  -> number (ms to initialize Hermes runtime)
// vim.metrics.configLoadTime  -> number (ms to load config files)
// vim.metrics.uptime          -> number (ms since process started)
// vim.metrics.pluginCount     -> number (plugins loaded)
// vim.metrics.pluginLoadTimes -> Array<{name: string, duration_ms: number}>
//
// Example:
//   console.log('Startup:', vim.metrics.startupTime, 'ms');
//   console.log('Hermes init:', vim.metrics.hermesInitTime, 'ms');
//   console.log('Config load:', vim.metrics.configLoadTime, 'ms');
//   console.log('Plugins:', vim.metrics.pluginLoadTimes);
//
// Note: All properties return 0 or empty array if metrics are disabled
if (typeof vimMetrics !== 'undefined') {
  vim.metrics = vimMetrics;
  Object.freeze(vim.metrics);
}
