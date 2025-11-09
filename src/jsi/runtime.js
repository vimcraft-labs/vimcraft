// console object (for debugging) - make it global for plugins!
globalThis.console = {
  log: function(...args) { consoleLog(...args); }
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
  opt: {
    set cursorLine(value) { setOption('cursorLine', value); },
    get cursorLine() { return true; }
  }
};

// Layer API - these are already registered with clean names by Zig
// No wrapper needed - just use the native functions directly
