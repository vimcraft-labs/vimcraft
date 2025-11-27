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

// setImmediate polyfill (used internally by Promise resolution in some JS environments)
// Hermes doesn't provide this natively, but Promise.resolve() may use it internally.
// We implement it using setTimeout(fn, 0) for compatibility.
globalThis.setImmediate = function(callback) {
  return setTimeout(callback, 0);
};

globalThis.clearImmediate = function(id) {
  clearTimeout(id);
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
      const value = vimOpt[prop];

      // Special handling for listchars: convert string to object format
      if ((prop === 'listchars' || prop === 'listChars' || prop === 'lcs') && typeof value === 'string') {
        // Convert "tab:> ,trail:-,nbsp:+" to { tab: "> ", trail: "-", nbsp: "+" }
        const result = {};
        for (const part of value.split(',')) {
          const colonIdx = part.indexOf(':');
          if (colonIdx > 0) {
            const key = part.slice(0, colonIdx).trim();
            const val = part.slice(colonIdx + 1);
            result[key] = val;
          }
        }
        return result;
      }

      return value;
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: only accept objects (HashMap type)
      if (prop === 'listchars' || prop === 'listChars' || prop === 'lcs') {
        if (typeof value !== 'object' || value === null) {
          throw new TypeError('vim.opt.listchars only accepts object type, e.g. { tab: "> ", trail: "-" }');
        }
        // Convert object to internal string format (implementation detail)
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
      const value = vimOptLocal[prop];

      // Special handling for listchars: convert string to object format
      if ((prop === 'listchars' || prop === 'listChars' || prop === 'lcs') && typeof value === 'string') {
        const result = {};
        for (const part of value.split(',')) {
          const colonIdx = part.indexOf(':');
          if (colonIdx > 0) {
            const key = part.slice(0, colonIdx).trim();
            const val = part.slice(colonIdx + 1);
            result[key] = val;
          }
        }
        return result;
      }

      return value;
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: only accept objects (HashMap type)
      if (prop === 'listchars' || prop === 'listChars' || prop === 'lcs') {
        if (typeof value !== 'object' || value === null) {
          throw new TypeError('vim.optLocal.listchars only accepts object type, e.g. { tab: "> ", trail: "-" }');
        }
        // Convert object to internal string format (implementation detail)
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
      const value = vimOptGlobal[prop];

      // Special handling for listchars: convert string to object format
      if ((prop === 'listchars' || prop === 'listChars' || prop === 'lcs') && typeof value === 'string') {
        const result = {};
        for (const part of value.split(',')) {
          const colonIdx = part.indexOf(':');
          if (colonIdx > 0) {
            const key = part.slice(0, colonIdx).trim();
            const val = part.slice(colonIdx + 1);
            result[key] = val;
          }
        }
        return result;
      }

      return value;
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      // Special handling for listchars: only accept objects (HashMap type)
      if (prop === 'listchars' || prop === 'listChars' || prop === 'lcs') {
        if (typeof value !== 'object' || value === null) {
          throw new TypeError('vim.optGlobal.listchars only accepts object type, e.g. { tab: "> ", trail: "-" }');
        }
        // Convert object to internal string format (implementation detail)
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

// ============================================================================
// Keymap Callback Registry (React Native pattern)
// ============================================================================
// Keeps callback functions alive in JavaScript to prevent garbage collection
// Zig stores only the callback ID, JavaScript executes the actual function
globalThis._keymapCallbacks = {};
globalThis._nextKeymapId = 1;

// Called by native code when a callback keymap is triggered
globalThis.__handleKeymapCallback = function(id) {
  const callback = globalThis._keymapCallbacks[id];
  if (callback) {
    try {
      callback();
    } catch (e) {
      globalThis.console.log('Keymap callback error:', e);
    }
  }
};

// vim.keymap API - Expose keymap HostObject methods
// Allows users to create custom key mappings (Neovim compatible)
// vim.keymap.set(mode, lhs, rhs, opts)
// mode: string ('n', 'i', 'v', 'c')
// lhs: string (key to map, e.g., 'H', '<leader>w')
// rhs: string or function (command to execute or callback)
// opts: object { noremap: bool, silent: bool, buffer: bool }
// vim.keymap.del(mode, lhs)
// mode: string ('n', 'i', 'v', 'c')
// lhs: string (key to unmap)
vim.keymap = {
  set: function(mode, lhs, rhs, opts) {
    if (typeof rhs === 'function') {
      // Function callback - store in registry and pass ID to native
      const id = globalThis._nextKeymapId++;
      globalThis._keymapCallbacks[id] = rhs;
      return vimKeymap.set(mode, lhs, id, opts);
    } else {
      // String mapping - pass directly to native
      return vimKeymap.set(mode, lhs, rhs, opts);
    }
  },
  del: function(mode, lhs) {
    // TODO: Clean up callback from registry if it was a callback mapping
    return vimKeymap.del(mode, lhs);
  }
};

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
  // === Buffer Functions ===

  // vim.api.getCurrentBuf() -> Buffer
  //   returns: number (buffer handle, 0 = current buffer)
  getCurrentBuf: function() {
    if (typeof vimApiGetCurrentBuf !== 'undefined') {
      return vimApiGetCurrentBuf();
    }
    return 0; // Default to current buffer
  },

  // vim.api.bufLineCount(buffer) -> number
  //   buffer: number (buffer handle, 0 = current)
  //   returns: number (line count)
  bufLineCount: function(buffer) {
    if (typeof vimApiBufLineCount !== 'undefined') {
      return vimApiBufLineCount(buffer);
    }
    throw new Error('bufLineCount not available');
  },

  // vim.api.bufGetLines(buffer, start, end, strict) -> string[]
  //   buffer: number (buffer handle, 0 = current)
  //   start: number (0-indexed start line)
  //   end: number (0-indexed end line, exclusive, -1 = end of file)
  //   strict: boolean (if true, error on out-of-bounds; if false, clamp)
  //   returns: string[] (array of lines without trailing newlines)
  bufGetLines: function(buffer, start, end, strict) {
    if (typeof vimApiBufGetLines !== 'undefined') {
      return vimApiBufGetLines(buffer, start, end, strict);
    }
    throw new Error('bufGetLines not available');
  },

  // vim.api.bufSetLines(buffer, start, end, strict, replacement) -> void
  //   buffer: number (buffer handle, 0 = current)
  //   start: number (0-indexed start line)
  //   end: number (0-indexed end line, exclusive, -1 = end of file)
  //   strict: boolean (if true, error on out-of-bounds; if false, clamp)
  //   replacement: string[] (array of replacement lines)
  bufSetLines: function(buffer, start, end, strict, replacement) {
    if (typeof vimApiBufSetLines !== 'undefined') {
      return vimApiBufSetLines(buffer, start, end, strict, replacement);
    }
    throw new Error('bufSetLines not available');
  },

  // vim.api.bufGetName(buffer) -> string
  //   buffer: number (buffer handle, 0 = current)
  //   returns: string (buffer filename, empty for unnamed)
  bufGetName: function(buffer) {
    if (typeof vimApiBufGetName !== 'undefined') {
      return vimApiBufGetName(buffer);
    }
    return ''; // Default to empty string for unnamed buffer
  },

  // vim.api.bufIsValid(buffer) -> boolean
  //   buffer: number (buffer handle)
  //   returns: boolean (true if buffer exists and is valid)
  bufIsValid: function(buffer) {
    if (typeof vimApiBufIsValid !== 'undefined') {
      return vimApiBufIsValid(buffer);
    }
    return buffer === 0; // Only buffer 0 is valid by default
  },

  // vim.api.setCurrentBuf(buffer) -> void
  //   buffer: number (buffer handle)
  //   Switches to the specified buffer
  setCurrentBuf: function(buffer) {
    if (typeof vimApiSetCurrentBuf !== 'undefined') {
      return vimApiSetCurrentBuf(buffer);
    }
    throw new Error('setCurrentBuf not available');
  },

  // vim.api.listBufs() -> number[]
  //   returns: array of buffer handles (all valid buffers)
  listBufs: function() {
    if (typeof vimApiListBufs !== 'undefined') {
      return vimApiListBufs();
    }
    return [0]; // Default to single buffer
  },

  // vim.api.bufSetName(buffer, name) -> void
  //   buffer: number (buffer handle, 0 = current)
  //   name: string (new buffer filename/path)
  bufSetName: function(buffer, name) {
    if (typeof vimApiBufSetName !== 'undefined') {
      return vimApiBufSetName(buffer, name);
    }
    throw new Error('bufSetName not available');
  },

  // vim.api.bufDelete(buffer, opts) -> void
  //   buffer: number (buffer handle)
  //   opts: object (optional)
  //     - force: boolean (force delete even if modified)
  bufDelete: function(buffer, opts) {
    if (typeof vimApiBufDelete !== 'undefined') {
      return vimApiBufDelete(buffer, opts || {});
    }
    throw new Error('bufDelete not available');
  },

  // vim.api.createBuf(listed, scratch) -> Buffer
  //   listed: boolean (whether buffer appears in buffer list)
  //   scratch: boolean (whether buffer is a scratch buffer)
  //   returns: number (new buffer handle)
  createBuf: function(listed, scratch) {
    if (typeof vimApiCreateBuf !== 'undefined') {
      return vimApiCreateBuf(listed, scratch);
    }
    return 0; // Fallback for headless mode
  },

  // vim.api.bufGetText(buf, start_row, start_col, end_row, end_col) -> string[]
  //   Character-level text retrieval
  bufGetText: function(buffer, start_row, start_col, end_row, end_col) {
    if (typeof vimApiBufGetText !== 'undefined') {
      return vimApiBufGetText(buffer, start_row, start_col, end_row, end_col);
    }
    return [];
  },

  // vim.api.bufSetText(buf, start_row, start_col, end_row, end_col, replacement) -> void
  //   Character-level text replacement
  bufSetText: function(buffer, start_row, start_col, end_row, end_col, replacement) {
    if (typeof vimApiBufSetText !== 'undefined') {
      return vimApiBufSetText(buffer, start_row, start_col, end_row, end_col, replacement);
    }
  },

  // vim.api.bufIsLoaded(buffer) -> boolean
  //   Check if buffer content is loaded in memory
  bufIsLoaded: function(buffer) {
    if (typeof vimApiBufIsLoaded !== 'undefined') {
      return vimApiBufIsLoaded(buffer);
    }
    return buffer === 0;
  },

  // vim.api.bufGetVar(buffer, name) -> any
  //   Get buffer-local variable (b:)
  bufGetVar: function(buffer, name) {
    if (typeof vimApiBufGetVar !== 'undefined') {
      return vimApiBufGetVar(buffer, name);
    }
    return undefined;
  },

  // vim.api.bufSetVar(buffer, name, value) -> void
  //   Set buffer-local variable (b:)
  bufSetVar: function(buffer, name, value) {
    if (typeof vimApiBufSetVar !== 'undefined') {
      return vimApiBufSetVar(buffer, name, value);
    }
  },

  // vim.api.bufDelVar(buffer, name) -> void
  //   Delete buffer-local variable
  bufDelVar: function(buffer, name) {
    if (typeof vimApiBufDelVar !== 'undefined') {
      return vimApiBufDelVar(buffer, name);
    }
  },

  // vim.api.bufGetChangedtick(buffer) -> number
  //   Get buffer change counter (increments on each modification)
  bufGetChangedtick: function(buffer) {
    if (typeof vimApiBufGetChangedtick !== 'undefined') {
      return vimApiBufGetChangedtick(buffer);
    }
    return 0;
  },

  // vim.api.bufGetOffset(buffer, line) -> number
  //   Get byte offset of line start (-1 if invalid)
  bufGetOffset: function(buffer, line) {
    if (typeof vimApiBufGetOffset !== 'undefined') {
      return vimApiBufGetOffset(buffer, line);
    }
    return -1;
  },

  // vim.api.bufCall(buffer, fun) -> any
  //   Execute function with buffer as temporary current buffer
  bufCall: function(buffer, fun) {
    if (typeof vimApiBufCall !== 'undefined') {
      return vimApiBufCall(buffer, fun);
    }
    // Fallback: just call the function
    return fun();
  },

  // === Window Functions ===

  // vim.api.getCurrentWin() -> Window
  //   returns: number (window handle, 0 = current window)
  getCurrentWin: function() {
    if (typeof vimApiGetCurrentWin !== 'undefined') {
      return vimApiGetCurrentWin();
    }
    return 0; // Default to current window
  },

  // vim.api.winGetCursor(window) -> [row, col]
  //   window: number (window handle, 0 = current)
  //   returns: [number, number] (row is 1-indexed, col is 0-indexed per Neovim)
  winGetCursor: function(window) {
    if (typeof vimApiWinGetCursor !== 'undefined') {
      return vimApiWinGetCursor(window);
    }
    throw new Error('winGetCursor not available');
  },

  // vim.api.winSetCursor(window, pos) -> void
  //   window: number (window handle, 0 = current)
  //   pos: [number, number] (row is 1-indexed, col is 0-indexed per Neovim)
  winSetCursor: function(window, pos) {
    if (typeof vimApiWinSetCursor !== 'undefined') {
      return vimApiWinSetCursor(window, pos);
    }
    throw new Error('winSetCursor not available');
  },

  // vim.api.winIsValid(window) -> boolean
  //   window: number (window handle)
  //   returns: boolean (true if window exists and is valid)
  winIsValid: function(window) {
    if (typeof vimApiWinIsValid !== 'undefined') {
      return vimApiWinIsValid(window);
    }
    return window === 0; // Only window 0 is valid by default
  },

  // vim.api.winGetBuf(window) -> Buffer
  //   window: number (window handle, 0 = current)
  //   returns: number (buffer handle in window)
  winGetBuf: function(window) {
    if (typeof vimApiWinGetBuf !== 'undefined') {
      return vimApiWinGetBuf(window);
    }
    return 0; // Default to current buffer
  },

  // vim.api.winGetHeight(window) -> number
  //   window: number (window handle, 0 = current)
  //   returns: number (window height in rows)
  winGetHeight: function(window) {
    if (typeof vimApiWinGetHeight !== 'undefined') {
      return vimApiWinGetHeight(window);
    }
    return 24; // Default terminal height
  },

  // vim.api.winGetWidth(window) -> number
  //   window: number (window handle, 0 = current)
  //   returns: number (window width in columns)
  winGetWidth: function(window) {
    if (typeof vimApiWinGetWidth !== 'undefined') {
      return vimApiWinGetWidth(window);
    }
    return 80; // Default terminal width
  },

  // vim.api.setCurrentWin(window) -> void
  //   window: number (window handle)
  //   Switches to the specified window
  setCurrentWin: function(window) {
    if (typeof vimApiSetCurrentWin !== 'undefined') {
      return vimApiSetCurrentWin(window);
    }
    // No-op in single-window mode
  },

  // vim.api.listWins() -> number[]
  //   returns: array of window handles (all valid windows)
  listWins: function() {
    if (typeof vimApiListWins !== 'undefined') {
      return vimApiListWins();
    }
    return [0]; // Single window mode
  },

  // vim.api.winSetBuf(window, buffer) -> void
  //   window: number (window handle)
  //   buffer: number (buffer handle)
  //   Sets buffer displayed in window
  winSetBuf: function(window, buffer) {
    if (typeof vimApiWinSetBuf !== 'undefined') {
      return vimApiWinSetBuf(window, buffer);
    }
    // No-op in single-window mode
  },

  // vim.api.winSetHeight(window, height) -> void
  //   window: number (window handle)
  //   height: number (new height in rows)
  winSetHeight: function(window, height) {
    if (typeof vimApiWinSetHeight !== 'undefined') {
      return vimApiWinSetHeight(window, height);
    }
    // No-op in single-window mode
  },

  // vim.api.winSetWidth(window, width) -> void
  //   window: number (window handle)
  //   width: number (new width in columns)
  winSetWidth: function(window, width) {
    if (typeof vimApiWinSetWidth !== 'undefined') {
      return vimApiWinSetWidth(window, width);
    }
    // No-op in single-window mode
  },

  // vim.api.winClose(window, force) -> void
  //   window: number (window handle)
  //   force: boolean (force close even if modified)
  winClose: function(window, force) {
    if (typeof vimApiWinClose !== 'undefined') {
      return vimApiWinClose(window, force);
    }
    // No-op in single-window mode (cannot close only window)
  },

  // vim.api.winGetVar(window, name) -> any
  //   Get window-local variable (w:)
  winGetVar: function(window, name) {
    if (typeof vimApiWinGetVar !== 'undefined') {
      return vimApiWinGetVar(window, name);
    }
    return undefined;
  },

  // vim.api.winSetVar(window, name, value) -> void
  //   Set window-local variable (w:)
  winSetVar: function(window, name, value) {
    if (typeof vimApiWinSetVar !== 'undefined') {
      return vimApiWinSetVar(window, name, value);
    }
  },

  // vim.api.winDelVar(window, name) -> void
  //   Delete window-local variable
  winDelVar: function(window, name) {
    if (typeof vimApiWinDelVar !== 'undefined') {
      return vimApiWinDelVar(window, name);
    }
  },

  // vim.api.winCall(window, fun) -> any
  //   Execute function with window as temporary current window
  winCall: function(window, fun) {
    if (typeof vimApiWinCall !== 'undefined') {
      return vimApiWinCall(window, fun);
    }
    // Invalid window returns undefined
    if (window !== 0) return undefined;
    return fun();
  },

  // vim.api.winGetNumber(window) -> number
  //   Get window number (1-indexed, for :wincmd)
  winGetNumber: function(window) {
    if (typeof vimApiWinGetNumber !== 'undefined') {
      return vimApiWinGetNumber(window);
    }
    // Single window is number 1, invalid returns -1
    return window === 0 ? 1 : -1;
  },

  // vim.api.winGetPosition(window) -> [row, col]
  //   Get window position (0-indexed, relative to editor area)
  winGetPosition: function(window) {
    if (typeof vimApiWinGetPosition !== 'undefined') {
      return vimApiWinGetPosition(window);
    }
    // Invalid window returns null
    if (window !== 0) return null;
    return [0, 0]; // Full-screen window at origin
  },

  // === Highlight Functions ===

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
    if (typeof vimApiCreateAutoCommand !== 'undefined') {
      return vimApiCreateAutoCommand(event, opts);
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
    if (typeof vimApiDeleteAutoCommand !== 'undefined') {
      return vimApiDeleteAutoCommand(id);
    }
    throw new Error('delAutocmd not available (headless mode)');
  },

  // vim.api.createAugroup(name, opts)
  //   name: string - Group name
  //   opts: object (optional)
  //     - clear: boolean - Clear all autocommands in group first
  //   returns: string (group name)
  //
  // Example:
  //   vim.api.createAugroup('my_plugin', { clear: true });
  //   vim.api.createAutocmd('BufEnter', {
  //       group: 'my_plugin',
  //       callback: () => {},
  //   });
  createAugroup: function(name, opts) {
    if (typeof vimApiCreateAutoGroup !== 'undefined') {
      return vimApiCreateAutoGroup(name, opts || {});
    }
    throw new Error('createAugroup not available (headless mode)');
  },

  // vim.api.clearAutocmds(opts)
  //   opts: object
  //     - group: string - Clear all autocommands in group
  //
  // Example:
  //   vim.api.clearAutocmds({ group: 'my_plugin' });
  clearAutocmds: function(opts) {
    if (typeof vimApiClearAutoCommands !== 'undefined') {
      return vimApiClearAutoCommands(opts || {});
    }
    throw new Error('clearAutocmds not available (headless mode)');
  },

  // vim.api.createUserCmd(name, callback, opts)
  //   name: string - Command name (must start with uppercase)
  //   callback: function(args) - Command callback
  //     args: object containing:
  //       - name: string (command name)
  //       - args: string (raw arguments string)
  //       - fargs: string[] (arguments split by whitespace)
  //       - bang: boolean (whether ! was used)
  //       - mods: string (command modifiers)
  //       - line1, line2, range: (if range option set)
  //       - count: number (if count option set)
  //       - reg: string (if register option set)
  //   opts: object (optional)
  //     - desc: string (command description)
  //     - bang: boolean (allow ! modifier)
  //     - bar: boolean (allow | separator)
  //     - force: boolean (overwrite existing)
  //     - range: boolean | '%' | number
  //     - count: number
  //     - register: boolean
  //     - nargs: '0' | '1' | '*' | '?' | '+'
  //     - complete: string | function
  //
  // Example:
  //   vim.api.createUserCmd('Greet', (args) => {
  //     console.log(`Hello ${args.args}!`);
  //   }, { desc: 'Greet someone' });
  createUserCmd: function(name, callback, opts) {
    if (typeof createUserCommand !== 'undefined') {
      return createUserCommand(name, callback, opts || {});
    }
    // Stub: log warning instead of crashing (not yet implemented)
    console.log('[vim.api] createUserCmd not yet implemented, skipping:', name);
  },

  // vim.api.delUserCmd(name)
  //   name: string - Command name to delete
  //
  // Example:
  //   vim.api.delUserCmd('Greet');
  delUserCmd: function(name) {
    if (typeof deleteUserCommand !== 'undefined') {
      return deleteUserCommand(name);
    }
    // Stub: not yet implemented
  },

  // vim.api.bufCreateUserCmd(buffer, name, callback, opts)
  //   buffer: number - Buffer number (0 for current)
  //   name: string - Command name
  //   callback: function(args) - Command callback
  //   opts: object (same as createUserCmd)
  //
  // Example:
  //   vim.api.bufCreateUserCmd(0, 'LocalCmd', (args) => {
  //     console.log('Buffer-local command');
  //   });
  bufCreateUserCmd: function(buffer, name, callback, opts) {
    if (typeof bufCreateUserCommand !== 'undefined') {
      return bufCreateUserCommand(buffer, name, callback, opts || {});
    }
    // Stub: not yet implemented
    console.log('[vim.api] bufCreateUserCmd not yet implemented, skipping:', name);
  },

  // vim.api.bufDelUserCmd(buffer, name)
  //   buffer: number - Buffer number (0 for current)
  //   name: string - Command name to delete
  bufDelUserCmd: function(buffer, name) {
    if (typeof bufDeleteUserCommand !== 'undefined') {
      return bufDeleteUserCommand(buffer, name);
    }
    // Stub: not yet implemented
  },

  // vim.api.getUserCommands(opts)
  //   opts: object (optional)
  //     - builtin: boolean (include builtin commands)
  //   returns: array of command info objects
  getUserCommands: function(opts) {
    if (typeof getUserCommands !== 'undefined') {
      return getUserCommands(opts || {});
    }
    // Stub: return empty array (not yet implemented)
    return [];
  },

  // === Mode Functions ===

  // vim.api.getMode() -> { mode: string, blocking: boolean }
  //   returns: mode object with current mode string (n, i, v, c) and blocking state
  getMode: function() {
    if (typeof vimApiGetMode !== 'undefined') {
      return vimApiGetMode();
    }
    return { mode: 'n', blocking: false }; // Default to normal mode
  },

  // vim.api.getOption(name) -> any
  //   name: string - Option name
  //   returns: option value
  getOption: function(name) {
    return vim.opt[name];
  }
};

// ============================================================================
// Neovim-compatible Aliases (nvim_* naming convention)
// ============================================================================
// smear-cursor and other Neovim plugins use nvim_* naming
// These aliases map to the camelCase API above

// Mode
vim.api.nvim_get_mode = function() {
  if (typeof vimApiGetMode !== 'undefined') {
    return vimApiGetMode();
  }
  return { mode: 'n', blocking: false }; // Default to normal mode
};

// Buffer functions
vim.api.nvim_get_current_buf = vim.api.getCurrentBuf;
vim.api.nvim_buf_line_count = vim.api.bufLineCount;
vim.api.nvim_buf_get_lines = vim.api.bufGetLines;
vim.api.nvim_buf_set_lines = vim.api.bufSetLines;
vim.api.nvim_buf_get_name = vim.api.bufGetName;
vim.api.nvim_buf_is_valid = vim.api.bufIsValid;
vim.api.nvim_set_current_buf = vim.api.setCurrentBuf;
vim.api.nvim_list_bufs = vim.api.listBufs;
vim.api.nvim_buf_set_name = vim.api.bufSetName;
vim.api.nvim_buf_delete = vim.api.bufDelete;
vim.api.nvim_create_buf = vim.api.createBuf;
vim.api.nvim_buf_get_text = vim.api.bufGetText;
vim.api.nvim_buf_set_text = vim.api.bufSetText;
vim.api.nvim_buf_is_loaded = vim.api.bufIsLoaded;
vim.api.nvim_buf_get_var = vim.api.bufGetVar;
vim.api.nvim_buf_set_var = vim.api.bufSetVar;
vim.api.nvim_buf_del_var = vim.api.bufDelVar;
vim.api.nvim_buf_get_changedtick = vim.api.bufGetChangedtick;
vim.api.nvim_buf_get_offset = vim.api.bufGetOffset;
vim.api.nvim_buf_call = vim.api.bufCall;

// Window functions
vim.api.nvim_get_current_win = vim.api.getCurrentWin;
vim.api.nvim_win_get_cursor = vim.api.winGetCursor;
vim.api.nvim_win_set_cursor = vim.api.winSetCursor;
vim.api.nvim_win_is_valid = vim.api.winIsValid;
vim.api.nvim_win_get_buf = vim.api.winGetBuf;
vim.api.nvim_win_get_height = vim.api.winGetHeight;
vim.api.nvim_win_get_width = vim.api.winGetWidth;
vim.api.nvim_set_current_win = vim.api.setCurrentWin;
vim.api.nvim_list_wins = vim.api.listWins;
vim.api.nvim_win_set_buf = vim.api.winSetBuf;
vim.api.nvim_win_set_height = vim.api.winSetHeight;
vim.api.nvim_win_set_width = vim.api.winSetWidth;
vim.api.nvim_win_close = vim.api.winClose;
vim.api.nvim_win_get_var = vim.api.winGetVar;
vim.api.nvim_win_set_var = vim.api.winSetVar;
vim.api.nvim_win_del_var = vim.api.winDelVar;
vim.api.nvim_win_call = vim.api.winCall;
vim.api.nvim_win_get_number = vim.api.winGetNumber;
vim.api.nvim_win_get_position = vim.api.winGetPosition;

// Highlight functions
vim.api.nvim_set_hl = vim.api.setHighlight;
vim.api.nvim_get_hl = function(ns_id, opts) {
  // Neovim nvim_get_hl(ns_id, opts) where opts.name is the hl group
  if (opts && opts.name) {
    return vim.api.getHighlight(ns_id, opts.name);
  }
  return vim.api.getHighlight(ns_id, opts);
};

// Autocommand functions
vim.api.nvim_create_autocmd = vim.api.createAutocmd;
vim.api.nvim_del_autocmd = vim.api.delAutocmd;
vim.api.nvim_create_augroup = vim.api.createAugroup;
vim.api.nvim_clear_autocmds = vim.api.clearAutocmds;

// User command functions
vim.api.nvim_create_user_command = vim.api.createUserCmd;
vim.api.nvim_del_user_command = vim.api.delUserCmd;
vim.api.nvim_buf_create_user_command = vim.api.bufCreateUserCmd;
vim.api.nvim_buf_del_user_command = vim.api.bufDelUserCmd;
vim.api.nvim_get_commands = vim.api.getUserCommands;

// Option functions (Neovim style)
vim.api.nvim_get_option_value = function(name, opts) {
  // opts can have: scope ('global'|'local'), buf, win
  if (opts && opts.scope === 'local') {
    return vim.optLocal[name];
  } else if (opts && opts.scope === 'global') {
    return vim.optGlobal[name];
  }
  return vim.opt[name];
};

vim.api.nvim_set_option_value = function(name, value, opts) {
  if (opts && opts.scope === 'local') {
    vim.optLocal[name] = value;
  } else if (opts && opts.scope === 'global') {
    vim.optGlobal[name] = value;
  } else {
    vim.opt[name] = value;
  }
};

Object.freeze(vim.api);

// ============================================================================
// vim.fn - Vimscript Function Wrappers (Neovim compatible)
// ============================================================================
// Provides vim.fn.funcname() style access to Vim functions
// Used by Neovim plugins like smear-cursor

vim.fn = {
  // vim.fn.getwininfo([winid]) -> array of window info objects
  // Returns information about all windows or specific window
  // Each object contains: winid, bufnr, winnr, height, width, wincol, winrow, etc.
  getwininfo: function(winid) {
    const wins = vim.api.listWins();
    const result = [];

    for (const w of wins) {
      if (winid !== undefined && w !== winid) continue;

      const pos = vim.api.winGetPosition(w) || [0, 0];
      const info = {
        winid: w,
        bufnr: vim.api.winGetBuf(w),
        winnr: vim.api.winGetNumber(w),
        height: vim.api.winGetHeight(w),
        width: vim.api.winGetWidth(w),
        winrow: pos[0],
        wincol: pos[1],
        terminal: 0,
        quickfix: 0,
        loclist: 0,
        textoff: 0, // columns used by line numbers, signs, etc.
      };
      result.push(info);
    }

    return result;
  },

  // vim.fn.winsaveview() -> object
  // Returns view information for current window
  winsaveview: function() {
    const pos = vim.api.winGetCursor(0);
    return {
      lnum: pos ? pos[0] : 1,
      col: pos ? pos[1] : 0,
      coladd: 0,
      curswant: pos ? pos[1] : 0,
      topline: 1, // TODO: track scroll position
      topfill: 0,
      leftcol: 0,
      skipcol: 0,
    };
  },

  // vim.fn.winrestview(view) -> void
  // Restores view to saved state
  winrestview: function(view) {
    if (view && view.lnum !== undefined) {
      vim.api.winSetCursor(0, [view.lnum, view.col || 0]);
    }
  },

  // vim.fn.line(expr) -> number
  // Get line number for various expressions
  line: function(expr) {
    if (expr === '.') {
      // Current line
      const pos = vim.api.winGetCursor(0);
      return pos ? pos[0] : 1;
    } else if (expr === '$') {
      // Last line
      return vim.api.bufLineCount(0);
    } else if (expr === 'w0') {
      // First visible line in window
      return 1; // TODO: track viewport
    } else if (expr === 'w$') {
      // Last visible line in window
      return vim.api.winGetHeight(0);
    }
    return 0;
  },

  // vim.fn.col(expr) -> number
  // Get column number for various expressions
  col: function(expr) {
    if (expr === '.') {
      const pos = vim.api.winGetCursor(0);
      return pos ? pos[1] + 1 : 1; // Vim columns are 1-indexed
    } else if (expr === '$') {
      // End of current line
      const pos = vim.api.winGetCursor(0);
      if (pos) {
        const lines = vim.api.bufGetLines(0, pos[0] - 1, pos[0], false);
        return lines && lines[0] ? lines[0].length + 1 : 1;
      }
      return 1;
    }
    return 0;
  },

  // vim.fn.winnr() -> number
  // Get current window number
  winnr: function() {
    return vim.api.winGetNumber(0);
  },

  // vim.fn.bufnr([expr]) -> number
  // Get buffer number
  bufnr: function(expr) {
    if (expr === undefined || expr === '%') {
      return vim.api.getCurrentBuf();
    }
    return -1; // Buffer not found
  },

  // vim.fn.bufname([expr]) -> string
  // Get buffer name
  bufname: function(expr) {
    const bufnr = expr === undefined || expr === '%' ? 0 : expr;
    return vim.api.bufGetName(bufnr);
  },

  // vim.fn.expand(expr) -> string
  // Expand special keywords
  expand: function(expr) {
    if (expr === '%') {
      return vim.api.bufGetName(0);
    } else if (expr === '%:p') {
      return vim.api.bufGetName(0); // Already absolute
    } else if (expr === '%:t') {
      const name = vim.api.bufGetName(0);
      return name.split('/').pop() || '';
    }
    return expr;
  },

  // vim.fn.mode() -> string
  // Get current mode character
  mode: function() {
    const modeInfo = vim.api.nvim_get_mode();
    return modeInfo.mode;
  },

  // vim.fn.has(feature) -> 0|1
  // Check for feature support
  has: function(feature) {
    const supported = [
      'nvim', 'vimcraft', 'timers', 'syntax', 'autocmd',
      'signs', 'virtual_text', 'highlighting',
    ];
    return supported.includes(feature) ? 1 : 0;
  },

  // vim.fn.exists(expr) -> 0|1|2
  // Check if variable/function/etc exists
  exists: function(expr) {
    // Check for functions
    if (expr.startsWith('*')) {
      const fn = expr.slice(1);
      return typeof vim.fn[fn] === 'function' ? 1 : 0;
    }
    // Check for vim.g variables
    if (expr.startsWith('g:')) {
      return vim.g && vim.g[expr.slice(2)] !== undefined ? 1 : 0;
    }
    return 0;
  },
};

Object.freeze(vim.fn);

// ============================================================================
// vim.autocmd - Autocommand API (Neovim compatible)
// ============================================================================
// Provides vim.autocmd.create() style access (alternative to vim.api.createAutocmd)
// Used by Neovim plugins like smear-cursor

vim.autocmd = {
  // vim.autocmd.create(event, opts) -> number (autocmd ID)
  // Wrapper around vim.api.createAutocmd for convenience
  // Supports TWO signatures:
  //   1. Neovim style: vim.autocmd.create(event, { callback, group, pattern, once })
  //   2. smear-cursor style: vim.autocmd.create(group, event, callback)
  create: function(eventOrGroup, optsOrEvent, callbackOrUndef) {
    // Detect signature: if 3rd arg is function, it's smear-cursor style
    if (typeof callbackOrUndef === 'function') {
      // smear-cursor style: (group, event, callback)
      const group = eventOrGroup;
      const event = optsOrEvent;
      const callback = callbackOrUndef;
      return vim.api.createAutocmd(event, { callback: callback, group: group });
    } else {
      // Neovim style: (event, opts)
      return vim.api.createAutocmd(eventOrGroup, optsOrEvent);
    }
  },

  // vim.autocmd.delete(id) -> void
  // Wrapper around vim.api.delAutocmd
  delete: function(id) {
    return vim.api.delAutocmd(id);
  },

  // vim.autocmd.group(name, opts) -> string (group name)
  // Wrapper around vim.api.createAugroup
  group: function(name, opts) {
    return vim.api.createAugroup(name, opts);
  },

  // vim.autocmd.clear(groupOrOpts) -> void
  // Wrapper around vim.api.clearAutocmds
  // Supports TWO signatures:
  //   1. Neovim style: vim.autocmd.clear({ group: 'name' })
  //   2. smear-cursor style: vim.autocmd.clear('groupName')
  clear: function(groupOrOpts) {
    if (typeof groupOrOpts === 'string') {
      // smear-cursor style: just group name
      return vim.api.clearAutocmds({ group: groupOrOpts });
    } else {
      // Neovim style: opts object
      return vim.api.clearAutocmds(groupOrOpts);
    }
  },
};

Object.freeze(vim.autocmd);

// ============================================================================
// vim.cmd - Ex command methods (Neovim 0.8+ style)
// ============================================================================
//
// Direct method calls for Ex commands:
//   vim.cmd.wincmd('h')           // Navigate to left window
//   vim.cmd.vsplit('file.txt')    // Vertical split
//   vim.cmd.write()               // Save file
//   vim.cmd.quit()                // Quit
//
// Supported commands:
//   wincmd(dir)    - Window navigation (h/j/k/l)
//   vsplit([file]) - Vertical split
//   split([file])  - Horizontal split
//   write()        - Save file
//   quit()         - Quit
//   edit([file])   - Open file
//   new()          - New buffer in split
//   vnew()         - New buffer in vsplit
//   only()         - Close other windows
//   close()        - Close current window
//
// Examples:
//   vim.cmd.wincmd('h');
//   vim.cmd.vsplit();
//   vim.keymap.set('n', '<D-h>', () => vim.cmd.wincmd('h'));
//
vim.cmd = {
  // Window navigation
  wincmd: function(direction) {
    if (typeof vimWincmd !== 'undefined') {
      return vimWincmd(direction);
    }
  },

  // Window splits
  vsplit: function(file) {
    if (typeof vimCmdVsplit !== 'undefined') {
      return vimCmdVsplit(file || '');
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':vsplit' + (file ? ' ' + file : '') + '\r');
    }
  },

  split: function(file) {
    if (typeof vimCmdSplit !== 'undefined') {
      return vimCmdSplit(file || '');
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':split' + (file ? ' ' + file : '') + '\r');
    }
  },

  // File operations
  write: function() {
    if (typeof vimCmdWrite !== 'undefined') {
      return vimCmdWrite();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':w\r');
    }
  },

  quit: function() {
    if (typeof vimCmdQuit !== 'undefined') {
      return vimCmdQuit();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':q\r');
    }
  },

  edit: function(file) {
    if (typeof vimCmdEdit !== 'undefined') {
      return vimCmdEdit(file || '');
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':e' + (file ? ' ' + file : '') + '\r');
    }
  },

  // New buffers
  new: function() {
    if (typeof vimCmdNew !== 'undefined') {
      return vimCmdNew();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':new\r');
    }
  },

  vnew: function() {
    if (typeof vimCmdVnew !== 'undefined') {
      return vimCmdVnew();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':vnew\r');
    }
  },

  // Window management
  only: function() {
    if (typeof vimCmdOnly !== 'undefined') {
      return vimCmdOnly();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':only\r');
    }
  },

  close: function() {
    if (typeof vimCmdClose !== 'undefined') {
      return vimCmdClose();
    }
    if (typeof vimE2E !== 'undefined' && vimE2E.keys) {
      vimE2E.keys(':close\r');
    }
  },
};

Object.freeze(vim.cmd);

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

// ============================================================================
// Global Runtime APIs (Node.js/Browser compatible)
// ============================================================================

// fs - File System API (Node.js-style)
// Provides file operations via Zig's std.fs
//
// fs.readTextFile(path) -> string
//   Read file contents as UTF-8 string
//   Example: const content = fs.readTextFile('/tmp/file.txt');
//
// fs.readFile(path) -> ArrayBuffer
//   Read file contents as binary data
//   Example: const buffer = fs.readFile('/tmp/file.bin');
//
// fs.writeFile(path, data) -> void
//   Write string or ArrayBuffer to file
//   Example: fs.writeFile('/tmp/file.txt', 'Hello World');
//
// fs.exists(path) -> boolean
//   Check if file/directory exists
//   Example: if (fs.exists('/tmp/file.txt')) { ... }
//
// fs.stat(path) -> { size, mtime, isDirectory, isFile }
//   Get file metadata
//   Example: const { size, mtime } = fs.stat('/tmp/file.txt');
//
// fs.readDir(path) -> string[]
//   List directory contents
//   Example: const files = fs.readDir('/tmp');
//
// Path expansion: ~ expands to HOME, relative paths become absolute
if (typeof __fs !== 'undefined') {
  globalThis.fs = __fs;
  Object.freeze(globalThis.fs);
}

// process - Process API (Node.js-style)
// Provides process information and subprocess spawning
//
// process.platform -> 'darwin' | 'linux' | 'windows'
//   Get operating system
//   Example: if (process.platform === 'darwin') { ... }
//
// process.arch -> 'arm64' | 'x64' | 'x86'
//   Get CPU architecture
//   Example: console.log(process.arch);
//
// process.env -> { HOME, PATH, USER, ... }
//   Get environment variables (read-only)
//   Example: const home = process.env.HOME;
//
// process.cwd() -> string
//   Get current working directory
//   Example: const cwd = process.cwd();
//
// process.exec(command, args?, options?) -> { stdout, stderr, code }
//   Execute a child process and wait for completion (Promise-based)
//   Example:
//     const result = await process.exec('ls', ['-la']);
//     console.log(result.stdout);
//     console.log('Exit code:', result.code);
//
//   Options:
//     - cwd: string (working directory for subprocess)
//
// process.exit(code?) -> never
//   Exit the editor with given code (default 0)
//   Example: process.exit(1);
//
//   Options (exec):
//     - cwd: string (working directory for subprocess)
//     - env: object (environment variables to set/override)
//     - clearEnv: boolean (if true, don't inherit current environment)
if (typeof __process !== 'undefined') {
  // Wrap __process to add __keys to env for Zig iteration
  const originalExec = __process.spawn;  // Native function is still named spawn
  globalThis.process = Object.assign({}, __process, {
    exec: function(cmd, args, opts) {
      // Prepare options for native - add __keys to env for Zig iteration
      let nativeOpts = opts;
      if (opts && opts.env && typeof opts.env === 'object') {
        // Add __keys array so Zig can iterate over the env object
        // (Hermes doesn't expose Object.keys easily to native code)
        nativeOpts = { ...opts, env: { ...opts.env, __keys: Object.keys(opts.env) } };
      }
      return originalExec.call(__process, cmd, args, nativeOpts);
    }
  });
  Object.freeze(globalThis.process);
}

// ============================================================================
// Fetch API - Async HTTP Client (Browser-style with Promises)
// ============================================================================
// Provides async HTTP requests via libuv thread pool
// React Native pattern: JS manages Promise callbacks, native triggers them
//
// fetch(url, options?) -> Promise<Response>
//   Make an async HTTP request (non-blocking!)
//
//   url: string - Full URL (https://example.com/api)
//
//   options: object (optional)
//     - method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | 'HEAD' | 'OPTIONS'
//     - headers: { 'Content-Type': 'application/json', ... }
//               NOTE: Only common headers supported (Content-Type, Accept, Authorization,
//               User-Agent, X-API-Key, Cache-Control, Cookie, Origin, etc.)
//     - body: string (request body for POST/PUT/PATCH)
//     - signal: AbortSignal (for cancellation support)
//     - maxResponseSize: number (max response size in bytes, default 10MB)
//
//   Response: object
//     - status: number (HTTP status code)
//     - ok: boolean (true if status 200-299)
//     - statusText: string ('OK', 'Not Found', etc.)
//     - text(): string - Get response body as string
//     - json(): object - Parse response body as JSON
//
// Examples:
//   // GET request with async/await
//   const res = await fetch('https://api.example.com/data');
//   const data = res.json();
//
//   // POST with JSON body
//   const res = await fetch('https://api.example.com/data', {
//     method: 'POST',
//     headers: { 'Content-Type': 'application/json' },
//     body: JSON.stringify({ key: 'value' })
//   });
//
//   // Promise chain style
//   fetch('https://api.example.com/data')
//     .then(res => res.json())
//     .then(data => console.log(data))
//     .catch(err => console.error(err));
//
//   // With AbortController for cancellation
//   const controller = new AbortController();
//   setTimeout(() => controller.abort(), 5000); // Cancel after 5s
//   try {
//     const res = await fetch('https://api.example.com/data', {
//       signal: controller.signal
//     });
//   } catch (e) {
//     if (e.name === 'AbortError') console.log('Request was cancelled');
//   }

// ============================================================================
// AbortController / AbortSignal (Browser-compatible cancellation)
// ============================================================================
// ES5-style for Hermes compatibility (no ES6 class syntax)

// DOMException polyfill (minimal for AbortError)
function DOMException(message, name) {
  var error = new Error(message);
  error.name = name || 'DOMException';
  return error;
}

// AbortSignal - Represents a signal that can be used to abort operations
function AbortSignal() {
  this._aborted = false;
  this._reason = undefined;
  this._listeners = [];
}

// AbortSignal properties and methods
Object.defineProperty(AbortSignal.prototype, 'aborted', {
  get: function() { return this._aborted; }
});

Object.defineProperty(AbortSignal.prototype, 'reason', {
  get: function() { return this._reason; }
});

AbortSignal.prototype.addEventListener = function(type, listener) {
  if (type === 'abort') {
    this._listeners.push(listener);
  }
};

AbortSignal.prototype.removeEventListener = function(type, listener) {
  if (type === 'abort') {
    var idx = this._listeners.indexOf(listener);
    if (idx !== -1) this._listeners.splice(idx, 1);
  }
};

AbortSignal.prototype.throwIfAborted = function() {
  if (this._aborted) {
    throw this._reason;
  }
};

// Internal: trigger abort
AbortSignal.prototype._abort = function(reason) {
  if (this._aborted) return;
  this._aborted = true;
  this._reason = reason || new DOMException('The operation was aborted', 'AbortError');
  for (var i = 0; i < this._listeners.length; i++) {
    try {
      this._listeners[i]({ type: 'abort', target: this });
    } catch (e) {
      console.log('[AbortSignal] Listener error:', e);
    }
  }
};

// Static factory for timed abort
AbortSignal.timeout = function(ms) {
  var controller = new AbortController();
  setTimeout(function() {
    controller.abort(new DOMException('The operation timed out', 'TimeoutError'));
  }, ms);
  return controller.signal;
};

// AbortController - Controls an AbortSignal
function AbortController() {
  this._signal = new AbortSignal();
}

Object.defineProperty(AbortController.prototype, 'signal', {
  get: function() { return this._signal; }
});

AbortController.prototype.abort = function(reason) {
  this._signal._abort(reason);
};

// Make AbortController/AbortSignal globally available
globalThis.AbortController = AbortController;
globalThis.AbortSignal = AbortSignal;
globalThis.DOMException = DOMException;

// Fetch callback registry (React Native pattern)
globalThis._fetchCallbacks = {};
globalThis._nextFetchId = 1;

// Called by native code when fetch completes
globalThis.__handleFetchCallback = function(id, result) {
  const callbacks = globalThis._fetchCallbacks[id];
  delete globalThis._fetchCallbacks[id];

  if (!callbacks) {
    return;
  }

  const { resolve, reject, signal, abortListener } = callbacks;

  // Clean up abort listener to prevent memory leak
  if (signal && abortListener) {
    signal.removeEventListener('abort', abortListener);
  }

  // Check if aborted after completion (race condition edge case)
  if (signal && signal.aborted) {
    reject(signal.reason || new DOMException('The operation was aborted', 'AbortError'));
    return;
  }

  if (result.error) {
    // Check if it was a cancellation
    if (result.error.includes('cancelled') || result.error.includes('canceled')) {
      reject(new DOMException('The operation was aborted', 'AbortError'));
    } else {
      reject(new Error(result.error));
    }
    return;
  }

  if (!result.success) {
    reject(new Error(result.error || 'Fetch failed'));
    return;
  }

  // Create Response object
  const response = {
    status: result.status,
    ok: result.status >= 200 && result.status < 300,
    statusText: result.statusText,
    _body: result.body,

    // Response methods
    text: function() {
      return this._body;
    },
    json: function() {
      return JSON.parse(this._body);
    }
  };

  resolve(response);
};

// Global fetch function (Browser-compatible, async)
if (typeof __nativeFetch !== 'undefined') {
  globalThis.fetch = function(url, options) {
    return new Promise((resolve, reject) => {
      const opts = options || {};
      const signal = opts.signal;

      // Check if already aborted before starting
      if (signal && signal.aborted) {
        reject(signal.reason || new DOMException('The operation was aborted', 'AbortError'));
        return;
      }

      const id = globalThis._nextFetchId++;

      // Set up abort listener before storing callback
      let abortListener = null;
      if (signal) {
        abortListener = () => {
          // Try to cancel the in-flight request
          if (typeof __abortFetch !== 'undefined') {
            __abortFetch(id);
          }
          // Clean up callback and reject
          const callbacks = globalThis._fetchCallbacks[id];
          if (callbacks) {
            delete globalThis._fetchCallbacks[id];
            callbacks.reject(signal.reason || new DOMException('The operation was aborted', 'AbortError'));
          }
        };
        signal.addEventListener('abort', abortListener);
      }

      // Store callback with abortListener for cleanup
      globalThis._fetchCallbacks[id] = { resolve, reject, signal, abortListener };

      try {
        // Pass options to native
        __nativeFetch(id, url, {
          method: opts.method,
          headers: opts.headers,
          body: opts.body,
          maxResponseSize: opts.maxResponseSize
        });
      } catch (e) {
        delete globalThis._fetchCallbacks[id];
        if (signal && abortListener) {
          signal.removeEventListener('abort', abortListener);
        }
        reject(e);
      }
    });
  };
}

// ============================================================================
// Async Subprocess API - Persistent Processes with stdio Pipes
// ============================================================================
// Provides async subprocess spawning for LSP servers, formatters, etc.
// React Native pattern: JS manages event callbacks, native triggers them
//
// process.spawn(cmd, args?, opts?) -> ChildProcess
//   Spawn a persistent subprocess with stdio pipes (non-blocking!)
//
//   cmd: string - Command to execute (e.g., 'node', 'python')
//   args: string[] - Arguments (optional)
//   opts: object (optional)
//     - cwd: string - Working directory for subprocess
//
//   ChildProcess: object
//     - pid: number - Process ID
//     - stdin: { write(data) -> boolean, end() -> boolean } - Write to/close stdin
//     - kill(signal?) -> boolean - Kill process (default: SIGTERM)
//     - onStdout(callback) - Handle stdout data
//     - onStderr(callback) - Handle stderr data
//     - onExit(callback) - Handle process exit
//
// Examples:
//   // Spawn LSP server
//   const lsp = process.spawn('typescript-language-server', ['--stdio']);
//   lsp.onStdout((data) => console.log('LSP:', data));
//   lsp.onStderr((data) => console.error('LSP error:', data));
//   lsp.onExit((code, signal) => console.log('LSP exited:', code));
//   lsp.stdin.write(JSON.stringify(initRequest) + '\n');
//
//   // Formatter that needs EOF to process input
//   const prettier = process.spawn('prettier', ['--stdin-filepath', 'file.js']);
//   prettier.onStdout((formatted) => console.log(formatted));
//   prettier.stdin.write(code);
//   prettier.stdin.end();  // Signal EOF - prettier processes and outputs
//
//   // Kill with signal
//   lsp.kill('SIGTERM');
//   lsp.kill(9);  // SIGKILL

// Async process callback registry (React Native pattern)
globalThis._processCallbacks = {};

// Called by native code when process events occur
globalThis.__handleProcessEvent = function(id, event, data) {
  const callbacks = globalThis._processCallbacks[id];
  if (!callbacks) return;

  try {
    if (event === 'stdout' && callbacks.onStdout) {
      callbacks.onStdout(data.data);
    } else if (event === 'stderr' && callbacks.onStderr) {
      callbacks.onStderr(data.data);
    } else if (event === 'exit') {
      if (callbacks.onExit) {
        callbacks.onExit(data.code, data.signal);
      }
      // Clean up callbacks on exit
      delete globalThis._processCallbacks[id];
    }
  } catch (e) {
    console.log('[process.spawn] Callback error:', e);
  }
};

// Add spawn to process object if native functions available
if (typeof __spawnAsync !== 'undefined') {
  // Extend existing process object or create new one
  const existingProcess = globalThis.process || {};

  globalThis.process = Object.assign({}, existingProcess, {
    spawn: function(cmd, args, opts) {
      if (typeof cmd !== 'string' || cmd.length === 0) {
        throw new Error('spawn requires a command string');
      }

      // Prepare options for native - add __keys to env for Zig iteration
      const nativeOpts = opts ? { ...opts } : {};
      if (nativeOpts.env && typeof nativeOpts.env === 'object') {
        // Add __keys array so Zig can iterate over the env object
        // (Hermes doesn't expose Object.keys easily to native code)
        nativeOpts.env = { ...nativeOpts.env, __keys: Object.keys(nativeOpts.env) };
      }

      // Spawn the process, get back ID
      // Note: __spawnAsync will throw if spawn fails (via hermes_throw_error)
      // We wrap in try/catch to re-throw with cleaner message
      let id;
      try {
        id = __spawnAsync(cmd, args || [], nativeOpts);
      } catch (e) {
        // Native threw an error, re-throw with context
        throw new Error('Failed to spawn process: ' + (e && e.message ? e.message : String(e)));
      }

      if (id === undefined || id === null) {
        throw new Error('Failed to spawn process: unknown error');
      }

      // Initialize callbacks for this process
      globalThis._processCallbacks[id] = {
        onStdout: null,
        onStderr: null,
        onExit: null,
      };

      // Track if stdin was disabled (for better error messages)
      const stdinDisabled = opts && (opts.stdin === 'null' || opts.stdin === 'ignore');

      // Create ChildProcess object
      const childProcess = {
        pid: id,

        stdin: {
          write: function(data) {
            if (stdinDisabled) {
              console.log('[process.spawn] Warning: Cannot write to stdin - process spawned with stdin: "' + opts.stdin + '"');
              return false;
            }
            if (typeof data !== 'string') {
              data = String(data);
            }
            return __processWrite(id, data);
          },
          end: function() {
            if (stdinDisabled) {
              console.log('[process.spawn] Warning: Cannot close stdin - process spawned with stdin: "' + opts.stdin + '"');
              return false;
            }
            return __processCloseStdin(id);
          }
        },

        kill: function(signal) {
          // Convert signal name to number if needed
          let sigNum = 15; // Default SIGTERM
          if (typeof signal === 'number') {
            sigNum = signal;
          } else if (typeof signal === 'string') {
            // Pass string to native, it will handle conversion
            return __processKill(id, signal);
          }
          return __processKill(id, sigNum);
        },

        onStdout: function(callback) {
          if (globalThis._processCallbacks[id]) {
            globalThis._processCallbacks[id].onStdout = callback;
          }
          return this;
        },

        onStderr: function(callback) {
          if (globalThis._processCallbacks[id]) {
            globalThis._processCallbacks[id].onStderr = callback;
          }
          return this;
        },

        onExit: function(callback) {
          if (globalThis._processCallbacks[id]) {
            globalThis._processCallbacks[id].onExit = callback;
          }
          return this;
        },
      };

      return childProcess;
    }
  });

  // Re-freeze if it was frozen before
  if (Object.isFrozen(existingProcess)) {
    Object.freeze(globalThis.process);
  }
}

// ============================================================================
// Vim Option Enums (Runtime Constants)
// ============================================================================
// These are available globally for TypeScript configs without imports
// Usage: vim.opt.laststatus = LastStatus.Never;

/**
 * Status line display mode (vim.opt.laststatus)
 * Controls when the status line is shown
 */
globalThis.LastStatus = Object.freeze({
  /** Never show status line (laststatus=0) */
  Never: 0,
  /** Only if there are multiple windows (laststatus=1) */
  OnlyIfMultipleWindows: 1,
  /** Always show status line (laststatus=2, default) */
  Always: 2,
  /** Global status line - always show only in last window (laststatus=3) */
  Global: 3,
});

// ============================================================================
// vim.e2e API - E2E Testing and Plugin Development Debugging
// ============================================================================
//
// Provides a first-class TypeScript API for:
// 1. E2E tests - Full stack testing with real editor state
// 2. Plugin development - Interactive debugging during development
//
// API Overview:
//
// State Queries (synchronous):
//   vim.e2e.getCursor()        -> { line, col }
//   vim.e2e.getMode()          -> "NORMAL" | "INSERT" | "VISUAL" | "COMMAND"
//   vim.e2e.getState()         -> { mode, cursor, visual, buffer, registers }
//   vim.e2e.getBufferContent() -> string
//   vim.e2e.getLine(n)         -> string
//
// Commands:
//   vim.e2e.keys(keystrokes)   -> void (simulates typing)
//
// Test Structure:
//   vim.e2e.describe(name, fn) -> void (create test suite)
//   vim.e2e.test(name, fn)     -> void (add test case)
//   vim.e2e.runAll()           -> { passed, failed, total }
//
// Assertions:
//   vim.e2e.assert.equal(actual, expected, msg?)
//   vim.e2e.assert.mode(expected)
//   vim.e2e.assert.cursorAt(line, col)
//   vim.e2e.assert.bufferContains(text)
//
// Example:
//   vim.e2e.describe("Motion API", () => {
//     vim.e2e.test("right() moves cursor right", () => {
//       const before = vim.e2e.getCursor();
//       vim.motion.right();
//       const after = vim.e2e.getCursor();
//       vim.e2e.assert.equal(after.col, before.col + 1);
//     });
//   });
//   vim.e2e.runAll();
//
if (typeof vimE2E !== 'undefined') {
  vim.e2e = vimE2E;
  Object.freeze(vim.e2e);
}
