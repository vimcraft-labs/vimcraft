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
  highlight: function(name, opts) {
    const bg = opts.bg || null;
    const fg = opts.fg || null;
    setHighlight(name, bg, fg);
  },
  // Dynamic options proxy - handles ANY option via getOption/setOption
  // Supports both camelCase (JavaScript style) and lowercase (Vim style)
  opt: new Proxy({
    get [Symbol.toStringTag]() { return 'vim.opt'; }
  }, {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.opt';
      if (typeof prop === 'symbol') return undefined;
      // Always fetch from Zig (source of truth)
      return getOption(prop);
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;
      // Write to Zig (source of truth)
      setOption(prop, value);
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return getOption(prop) !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache
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
      // Fetch fresh value from Zig
      const value = getOption(prop);
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
  optLocal: new Proxy({
    get [Symbol.toStringTag]() { return 'vim.optLocal'; }
  }, {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.optLocal';
      if (typeof prop === 'symbol') return undefined;
      // Always fetch from Zig (source of truth)
      return getOptionWithScope(prop, 'local');
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;
      // Write to Zig (source of truth)
      setOptionWithScope(prop, value, 'local');
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return getOptionWithScope(prop, 'local') !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache
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
      // Fetch fresh value from Zig
      const value = getOptionWithScope(prop, 'local');
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
  optGlobal: new Proxy({
    get [Symbol.toStringTag]() { return 'vim.optGlobal'; }
  }, {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return 'vim.optGlobal';
      if (typeof prop === 'symbol') return undefined;
      // Always fetch from Zig (source of truth)
      return getOptionWithScope(prop, 'global');
    },
    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;
      // Write to Zig (source of truth)
      setOptionWithScope(prop, value, 'global');
      return true;
    },
    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return getOptionWithScope(prop, 'global') !== undefined;
    },
    // Fetch fresh snapshot when Chrome DevTools enumerates
    ownKeys(target) {
      // Clear stale cache
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
      // Fetch fresh value from Zig
      const value = getOptionWithScope(prop, 'global');
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

// Layer API - NO wrapper needed!
// The native functions (clearLayer, renderVirtualText) handle dirty tracking internally
// via layer.markDirty() which is smart enough to only mark when actually modified
