/**
 * Vimcraft JavaScript Runtime
 *
 * This file implements the JavaScript runtime environment for Vimcraft plugins.
 * It provides the vim API, console, timers, and other browser-like APIs.
 *
 * Build Pipeline:
 *   runtime.ts (ES2020) -> esbuild -> runtime.js (ES2017) -> hermesc -> runtime.hbc
 *
 * The bytecode is embedded at compile time for instant loading.
 *
 * Note: Uses ES5-compatible constructor functions (no ES6 classes) for Hermes compatibility.
 *
 * @module runtime
 */

// ============================================================================
// Type Declarations for Native Functions
// ============================================================================
// These are provided by the Hermes C API (hermes_c_api.cpp)

// Console
declare function consoleLog(...args: unknown[]): void;

// Timers
declare function __nativeSetTimeout(id: number, delay: number): void;
declare function __nativeSetInterval(id: number, delay: number): void;
declare function __nativeClearTimer(id: number): void;
declare function __nativeRequestAnimationFrame(id: number): void;

// Vim API native functions
declare function vimApiSetHighlight(ns: number, name: string, opts: object): void;
declare function getAllOptions(): Record<string, unknown>;
declare function getAllOptionsWithScope(scope: string): Record<string, unknown>;
declare const vimOpt: Record<string, unknown>;
declare const vimOptLocal: Record<string, unknown>;
declare const vimOptGlobal: Record<string, unknown>;
declare const vimBo: Record<string, unknown>;
declare const vimCursor: object | undefined;
declare const vimLayer: {
  screenchar(row: number, col: number): number;
  screenFg(row: number, col: number): number | null;
  screenBg(row: number, col: number): number | null;
  suppressCursor(): void;
  unsuppressCursor(): void;
  getViewportInfo(): { top: number; left: number; height: number; width: number };
  getGutterWidth(): number;
  createLayer(name: string, opts: { zIndex: number; opacity?: number; cacheable?: boolean }): void;
  renderVirtualText(name: string, cells: Array<{ row: number; col: number; char: string | number; fg?: number; bg?: number }>): void;
  setLayerOpacity(name: string, opacity: number): void;
  clearLayer(name: string): void;
  destroyLayer(name: string): void;
  drawVirtualText(row: number, col: number, char: number, fg: number | null, bg: number | null): void;
  clearVirtualText(): void;
};
declare const vimMotion: object;
declare const vimKeymap: {
  set(mode: string, lhs: string, rhs: string | number, opts?: object): void;
  del(mode: string, lhs: string): void;
};
declare const vimFiletype: object;
declare const vimTreesitter: object;
declare const vimBuffer: object | undefined;
declare const vimE2E: object | undefined;
declare const vimEventEmitter: {
  on(event: string, callback: (...args: unknown[]) => void): void;
  off(event: string, callback: (...args: unknown[]) => void): void;
  emit(event: string, ...args: unknown[]): void;
  removeAllListeners(event?: string): void;
  listenerCount(event: string): number;
} | undefined;
declare const vimMetrics: object | undefined;
declare const __fs: object | undefined;
declare const __process: {
  platform: string;
  arch: string;
  env: Record<string, string>;
  cwd(): string;
  exit(code?: number): never;
  spawn(cmd: string, args: string[], opts?: object): number;
} | undefined;

// Motion functions (legacy)
declare function moveLeft(): void;
declare function moveRight(): void;
declare function moveUp(): void;
declare function moveDown(): void;
declare function moveToLineStart(): void;
declare function moveToLineEnd(): void;
declare function moveToFirstNonBlank(): void;
declare function moveWordForward(): void;
declare function moveWordBackward(): void;
declare function moveWordEnd(): void;
declare function moveToFileStart(): void;
declare function moveToFileEnd(): void;
declare function moveToViewportTop(): void;
declare function moveToViewportMiddle(): void;
declare function moveToViewportBottom(): void;
declare function scrollHalfPageDown(): void;
declare function scrollHalfPageUp(): void;

// Buffer API native functions
declare function vimApiGetCurrentBuf(): number;
declare function vimApiBufLineCount(buffer: number): number;
declare function vimApiBufGetLines(buffer: number, start: number, end: number, strict: boolean): string[];
declare function vimApiBufSetLines(buffer: number, start: number, end: number, strict: boolean, replacement: string[]): void;
declare function vimApiBufGetName(buffer: number): string;
declare function vimApiBufIsValid(buffer: number): boolean;
declare function vimApiSetCurrentBuf(buffer: number): void;
declare function vimApiListBufs(): number[];
declare function vimApiBufSetName(buffer: number, name: string): void;
declare function vimApiBufDelete(buffer: number, opts: object): void;
declare function vimApiCreateBuf(listed: boolean, scratch: boolean): number;
declare function vimApiBufGetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number): string[];
declare function vimApiBufSetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number, replacement: string[]): void;
declare function vimApiBufIsLoaded(buffer: number): boolean;
declare function vimApiBufGetVar(buffer: number, name: string): unknown;
declare function vimApiBufSetVar(buffer: number, name: string, value: unknown): void;
declare function vimApiBufDelVar(buffer: number, name: string): void;
declare function vimApiBufGetChangedtick(buffer: number): number;
declare function vimApiBufGetOffset(buffer: number, line: number): number;
declare function vimApiBufCall(buffer: number, fun: () => unknown): unknown;

// Window API native functions
declare function vimApiGetCurrentWin(): number;
declare function vimApiWinGetCursor(window: number): [number, number];
declare function vimApiWinSetCursor(window: number, pos: [number, number]): void;
declare function vimApiWinIsValid(window: number): boolean;
declare function vimApiWinGetBuf(window: number): number;
declare function vimApiWinGetHeight(window: number): number;
declare function vimApiWinGetWidth(window: number): number;
declare function vimApiSetCurrentWin(window: number): void;
declare function vimApiListWins(): number[];
declare function vimApiWinSetBuf(window: number, buffer: number): void;
declare function vimApiWinSetHeight(window: number, height: number): void;
declare function vimApiWinSetWidth(window: number, width: number): void;
declare function vimApiWinClose(window: number, force: boolean): void;
declare function vimApiWinGetVar(window: number, name: string): unknown;
declare function vimApiWinSetVar(window: number, name: string, value: unknown): void;
declare function vimApiWinDelVar(window: number, name: string): void;
declare function vimApiWinCall(window: number, fun: () => unknown): unknown;
declare function vimApiWinGetNumber(window: number): number;
declare function vimApiWinGetPosition(window: number): [number, number];

// Floating window API native functions
declare function vimApiOpenWin(buf: number, enter: boolean, config: object): number;
declare function vimApiWinSetConfig(window: number, config: object): void;
declare function vimApiWinGetConfig(window: number): object | null;
declare function vimApiWinHide(window: number): void;
declare function vimApiWinSetOption(window: number, name: string, value: unknown): void;
declare function vimApiWinGetOption(window: number, name: string): unknown;

// Highlight API native functions
declare function vimApiCreateNamespace(name: string): number;
declare function vimApiGetNamespaces(): Record<string, number>;
declare function vimApiBufAddHighlight(buffer: number, ns: number, hlGroup: string, line: number, colStart: number, colEnd: number): number;
declare function vimApiBufClearNamespace(buffer: number, ns: number, lineStart: number, lineEnd: number): void;
declare function vimApiGetHighlight(ns: number, opts: object): object;

// Extmark API native functions
declare function vimApiBufSetExtmark(buffer: number, ns: number, line: number, col: number, opts: object): number;
declare function vimApiBufGetExtmarks(buffer: number, ns: number, start: number | [number, number], end: number | [number, number], opts: object): [number, number, number][] | [number, number, number, object][];
declare function vimApiBufDelExtmark(buffer: number, ns: number, id: number): boolean;
declare function vimApiBufGetExtmarkById(buffer: number, ns: number, id: number, opts: object): [number, number] | [number, number, object] | null;

// Diagnostic API native functions
declare function vimDiagnosticSet(namespace: number, bufnr: number, diagnostics: object[]): void;
declare function vimDiagnosticGet(bufnr?: number, opts?: object): object[];
declare function vimDiagnosticReset(namespace?: number, bufnr?: number): void;
declare function vimDiagnosticCount(bufnr?: number, opts?: object): Record<number, number>;

// Autocmd API native functions
declare function vimApiCreateAutoCommand(events: string | string[], opts: object): number;
declare function vimApiDeleteAutoCommand(id: number): void;
declare function vimApiCreateAutoGroup(name: string, opts: object): number;
declare function vimApiClearAutoCommands(opts: object): void;
declare function vimApiGetMode(): { mode: string; blocking: boolean };

// Command API native functions
declare function createUserCommand(name: string, command: string | ((...args: unknown[]) => void), opts: object): void;
declare function deleteUserCommand(name: string): void;
declare function bufCreateUserCommand(buffer: number, name: string, command: string | ((...args: unknown[]) => void), opts: object): void;
declare function bufDeleteUserCommand(buffer: number, name: string): void;
declare function getUserCommands(opts: object): object;

// Window command natives
declare function vimWincmd(direction: string): void;
declare function vimCmdVsplit(file: string): void;
declare function vimCmdSplit(file: string): void;
declare function vimCmdWrite(): void;
declare function vimCmdQuit(): void;
declare function vimCmdEdit(file: string): void;
declare function vimCmdNew(): void;
declare function vimCmdVnew(): void;
declare function vimCmdOnly(): void;
declare function vimCmdClose(): void;

// Process API native functions
declare function __spawnAsync(cmd: string, args: string[], opts: object): number;
declare function __processWrite(id: number, data: string): boolean;
declare function __processCloseStdin(id: number): boolean;
declare function __processKill(id: number, signal: string | number): boolean;
declare function __spawnPty(cmd: string, args: string[], opts: object): number;
declare function __ptyGetPid(id: number): number;
declare function __ptyWrite(id: number, data: string): boolean;
declare function __ptyResize(id: number, rows: number, cols: number): void;
declare function __ptyKill(id: number, signal: string | number): boolean;

// Fetch API native functions
declare function __nativeFetch(id: number, url: string, options: object): void;
declare function __abortFetch(id: number): void;

// ============================================================================
// Console API
// ============================================================================

interface ConsoleAPI {
  log(...args: unknown[]): void;
}

const consoleAPI: ConsoleAPI = {
  log(...args: unknown[]): void {
    consoleLog(...args);
  }
};

(globalThis as any).console = consoleAPI;

// ============================================================================
// Timer Registry
// ============================================================================

type TimerCallback = () => void;

interface TimerRegistry {
  _timerCallbacks: Record<number, TimerCallback>;
  _nextTimerId: number;
}

const timerRegistry: TimerRegistry = {
  _timerCallbacks: {},
  _nextTimerId: 1
};

(globalThis as any)._timerCallbacks = timerRegistry._timerCallbacks;
(globalThis as any)._nextTimerId = timerRegistry._nextTimerId;

(globalThis as any).setTimeout = (callback: TimerCallback, delay?: number): number => {
  const id = (globalThis as any)._nextTimerId++;
  (globalThis as any)._timerCallbacks[id] = callback;
  __nativeSetTimeout(id, delay || 0);
  return id;
};

(globalThis as any).setInterval = (callback: TimerCallback, delay?: number): number => {
  const id = (globalThis as any)._nextTimerId++;
  (globalThis as any)._timerCallbacks[id] = callback;
  __nativeSetInterval(id, delay || 0);
  return id;
};

(globalThis as any).clearTimeout = (id: number): void => {
  delete (globalThis as any)._timerCallbacks[id];
  __nativeClearTimer(id);
};

(globalThis as any).clearInterval = (id: number): void => {
  delete (globalThis as any)._timerCallbacks[id];
  __nativeClearTimer(id);
};

(globalThis as any).setImmediate = (callback: TimerCallback): number => {
  return (globalThis as any).setTimeout(callback, 0);
};

(globalThis as any).clearImmediate = (id: number): void => {
  (globalThis as any).clearTimeout(id);
};

(globalThis as any).__handleTimerCallback = (id: number): void => {
  const callback = (globalThis as any)._timerCallbacks[id];
  if (callback) {
    try {
      callback();
    } catch (e) {
      consoleAPI.log('Timer callback error:', e);
    }
  }
};

// ============================================================================
// Animation Frame Registry
// ============================================================================

type AnimationFrameCallback = () => void;

(globalThis as any)._animationFrameCallbacks = {} as Record<number, AnimationFrameCallback>;
(globalThis as any)._nextAnimationFrameId = 1;

(globalThis as any).requestAnimationFrame = (callback: AnimationFrameCallback): number => {
  const id = (globalThis as any)._nextAnimationFrameId++;
  (globalThis as any)._animationFrameCallbacks[id] = callback;
  __nativeRequestAnimationFrame(id);
  return id;
};

(globalThis as any).cancelAnimationFrame = (id: number): void => {
  delete (globalThis as any)._animationFrameCallbacks[id];
};

(globalThis as any).__handleAnimationFrame = (id: number): void => {
  const callback = (globalThis as any)._animationFrameCallbacks[id];
  if (callback) {
    delete (globalThis as any)._animationFrameCallbacks[id];
    try {
      callback();
    } catch (e) {
      consoleAPI.log('Animation frame callback error:', e);
    }
  }
};

// ============================================================================
// Performance API
// ============================================================================

interface PerformanceMeasure {
  name: string;
  duration: number;
  startTime: number;
}

interface PerformanceAPI {
  _marks: Record<string, number>;
  _measures: PerformanceMeasure[];
  now(): number;
  mark(name: string): void;
  measure(name: string, startMark: string, endMark?: string): void;
  clearMarks(name?: string): void;
  getEntriesByType(type: string): PerformanceMeasure[];
}

const performanceAPI: PerformanceAPI = {
  _marks: {},
  _measures: [],

  now(): number {
    return Date.now();
  },

  mark(name: string): void {
    this._marks[name] = this.now();
  },

  measure(name: string, startMark: string, endMark?: string): void {
    const start = this._marks[startMark] || 0;
    const end = endMark ? (this._marks[endMark] || this.now()) : this.now();
    const duration = end - start;
    this._measures.push({ name, duration, startTime: start });
  },

  clearMarks(name?: string): void {
    if (name) {
      delete this._marks[name];
    } else {
      this._marks = {};
    }
  },

  getEntriesByType(type: string): PerformanceMeasure[] {
    if (type === 'measure') return this._measures;
    return [];
  }
};

(globalThis as any).performance = performanceAPI;

// ============================================================================
// Listchars Helper Functions
// ============================================================================

function parseListchars(value: string): Record<string, string> {
  const result: Record<string, string> = {};
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

function serializeListchars(value: Record<string, string>): string {
  const parts: string[] = [];
  for (const [key, val] of Object.entries(value)) {
    if (typeof val === 'string' && val.length > 0) {
      parts.push(`${key}:${val}`);
    }
  }
  return parts.join(',');
}

// ============================================================================
// Vim Options Proxy Factory
// ============================================================================

function createOptionsProxy(
  tagName: string,
  hostObject: Record<string, unknown>,
  getAllFn: () => Record<string, unknown>
): Record<string, unknown> {
  const target = {
    get [Symbol.toStringTag]() { return tagName; }
  };

  const allOptions = getAllFn();
  Object.assign(target, allOptions);

  return new Proxy(target, {
    get(target, prop) {
      if (prop === Symbol.toStringTag) return tagName;
      if (typeof prop === 'symbol') return undefined;

      const value = hostObject[prop as string];

      if ((prop === 'listchars' || prop === 'listChars' || prop === 'lcs') && typeof value === 'string') {
        return parseListchars(value);
      }

      return value;
    },

    set(target, prop, value) {
      if (typeof prop === 'symbol') return false;

      if (prop === 'listchars' || prop === 'listChars' || prop === 'lcs') {
        if (typeof value !== 'object' || value === null) {
          throw new TypeError(`${tagName}.listchars only accepts object type, e.g. { tab: "> ", trail: "-" }`);
        }
        value = serializeListchars(value as Record<string, string>);
      }

      hostObject[prop as string] = value;
      return true;
    },

    has(target, prop) {
      if (typeof prop === 'symbol') return false;
      return hostObject[prop as string] !== undefined;
    },

    ownKeys(target) {
      for (const key of Object.keys(target)) {
        delete (target as any)[key];
      }

      const allOptions = getAllFn();
      Object.assign(target, allOptions);

      return Object.keys(target);
    },

    getOwnPropertyDescriptor(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      const value = hostObject[prop as string];
      if (value === undefined) return undefined;
      return {
        value,
        enumerable: true,
        configurable: true,
        writable: true
      };
    }
  });
}

// ============================================================================
// Vim API Object
// ============================================================================

interface VimAPI {
  // Buffer functions
  getCurrentBuf(): number;
  bufLineCount(buffer: number): number;
  bufGetLines(buffer: number, start: number, end: number, strict: boolean): string[];
  bufSetLines(buffer: number, start: number, end: number, strict: boolean, replacement: string[]): void;
  bufGetName(buffer: number): string;
  bufIsValid(buffer: number): boolean;
  setCurrentBuf(buffer: number): void;
  listBufs(): number[];
  bufSetName(buffer: number, name: string): void;
  bufDelete(buffer: number, opts?: object): void;
  createBuf(listed: boolean, scratch: boolean): number;
  bufGetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number): string[];
  bufSetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number, replacement: string[]): void;
  bufIsLoaded(buffer: number): boolean;
  bufGetVar(buffer: number, name: string): unknown;
  bufSetVar(buffer: number, name: string, value: unknown): void;
  bufDelVar(buffer: number, name: string): void;
  bufGetChangedtick(buffer: number): number;
  bufGetOffset(buffer: number, line: number): number;
  bufCall(buffer: number, fun: () => unknown): unknown;
  bufGetCharAt(buffer: number, row: number, col: number): string;
  bufSetOption(buffer: number, name: string, value: unknown): void;

  // Window functions
  getCurrentWin(): number;
  winGetCursor(window: number): [number, number];
  winSetCursor(window: number, pos: [number, number]): void;
  winIsValid(window: number): boolean;
  winGetBuf(window: number): number;
  winGetHeight(window: number): number;
  winGetWidth(window: number): number;
  setCurrentWin(window: number): void;
  listWins(): number[];
  winSetBuf(window: number, buffer: number): void;
  winSetHeight(window: number, height: number): void;
  winSetWidth(window: number, width: number): void;
  winClose(window: number, force: boolean): void;
  winGetVar(window: number, name: string): unknown;
  winSetVar(window: number, name: string, value: unknown): void;
  winDelVar(window: number, name: string): void;
  winCall(window: number, fun: () => unknown): unknown;
  winGetNumber(window: number): number;
  winGetPosition(window: number): [number, number];

  // Floating window functions
  openWin(buf: number, enter: boolean, config: object): number;
  winSetConfig(window: number, config: object): void;
  winGetConfig(window: number): object | null;
  winHide(window: number): void;

  // Highlight functions
  setHighlight(ns: number, name: string, opts: object): void;
  createNamespace(name: string): number;
  getNamespaces(): Record<string, number>;
  bufAddHighlight(buffer: number, ns: number, hlGroup: string, line: number, colStart: number, colEnd: number): number;
  bufClearNamespace(buffer: number, ns: number, lineStart: number, lineEnd: number): void;
  getHighlight(ns: number, name: string | object): object;

  // Extmark functions
  bufSetExtmark(buffer: number, ns: number, line: number, col: number, opts: object): number;
  bufGetExtmarks(buffer: number, ns: number, start: number | [number, number], end: number | [number, number], opts?: object): [number, number, number][] | [number, number, number, object][];
  bufDelExtmark(buffer: number, ns: number, id: number): boolean;
  bufGetExtmarkById(buffer: number, ns: number, id: number, opts?: object): [number, number] | [number, number, object] | null;

  // Autocmd functions
  createAutocmd(events: string | string[], opts: object): number;
  delAutocmd(id: number): void;
  createAugroup(name: string, opts: object): number;
  clearAutocmds(opts: object): void;

  // Command functions
  createUserCmd(name: string, command: string | ((...args: unknown[]) => void), opts: object): void;
  delUserCmd(name: string): void;
  bufCreateUserCmd(buffer: number, name: string, command: string | ((...args: unknown[]) => void), opts: object): void;
  bufDelUserCmd(buffer: number, name: string): void;
  getUserCommands(opts: object): object;

  // Mode functions
  getMode(): { mode: string; blocking: boolean };
  getOption(name: string): unknown;
}

const vimApi: VimAPI = {
  // Buffer functions
  getCurrentBuf() {
    return typeof vimApiGetCurrentBuf !== 'undefined' ? vimApiGetCurrentBuf() : 0;
  },

  bufLineCount(buffer: number) {
    if (typeof vimApiBufLineCount !== 'undefined') return vimApiBufLineCount(buffer);
    throw new Error('bufLineCount not available');
  },

  bufGetLines(buffer: number, start: number, end: number, strict: boolean) {
    if (typeof vimApiBufGetLines !== 'undefined') return vimApiBufGetLines(buffer, start, end, strict);
    throw new Error('bufGetLines not available');
  },

  bufSetLines(buffer: number, start: number, end: number, strict: boolean, replacement: string[]) {
    if (typeof vimApiBufSetLines !== 'undefined') return vimApiBufSetLines(buffer, start, end, strict, replacement);
    throw new Error('bufSetLines not available');
  },

  bufGetName(buffer: number) {
    return typeof vimApiBufGetName !== 'undefined' ? vimApiBufGetName(buffer) : '';
  },

  bufIsValid(buffer: number) {
    return typeof vimApiBufIsValid !== 'undefined' ? vimApiBufIsValid(buffer) : buffer === 0;
  },

  setCurrentBuf(buffer: number) {
    if (typeof vimApiSetCurrentBuf !== 'undefined') return vimApiSetCurrentBuf(buffer);
    throw new Error('setCurrentBuf not available');
  },

  listBufs() {
    return typeof vimApiListBufs !== 'undefined' ? vimApiListBufs() : [0];
  },

  bufSetName(buffer: number, name: string) {
    if (typeof vimApiBufSetName !== 'undefined') return vimApiBufSetName(buffer, name);
    throw new Error('bufSetName not available');
  },

  bufDelete(buffer: number, opts?: object) {
    if (typeof vimApiBufDelete !== 'undefined') return vimApiBufDelete(buffer, opts || {});
    throw new Error('bufDelete not available');
  },

  createBuf(listed: boolean, scratch: boolean) {
    return typeof vimApiCreateBuf !== 'undefined' ? vimApiCreateBuf(listed, scratch) : 0;
  },

  bufGetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number) {
    return typeof vimApiBufGetText !== 'undefined' ? vimApiBufGetText(buffer, startRow, startCol, endRow, endCol) : [];
  },

  bufSetText(buffer: number, startRow: number, startCol: number, endRow: number, endCol: number, replacement: string[]) {
    if (typeof vimApiBufSetText !== 'undefined') vimApiBufSetText(buffer, startRow, startCol, endRow, endCol, replacement);
  },

  bufIsLoaded(buffer: number) {
    return typeof vimApiBufIsLoaded !== 'undefined' ? vimApiBufIsLoaded(buffer) : buffer === 0;
  },

  bufGetVar(buffer: number, name: string) {
    return typeof vimApiBufGetVar !== 'undefined' ? vimApiBufGetVar(buffer, name) : undefined;
  },

  bufSetVar(buffer: number, name: string, value: unknown) {
    if (typeof vimApiBufSetVar !== 'undefined') vimApiBufSetVar(buffer, name, value);
  },

  bufDelVar(buffer: number, name: string) {
    if (typeof vimApiBufDelVar !== 'undefined') vimApiBufDelVar(buffer, name);
  },

  bufGetChangedtick(buffer: number) {
    return typeof vimApiBufGetChangedtick !== 'undefined' ? vimApiBufGetChangedtick(buffer) : 0;
  },

  bufGetOffset(buffer: number, line: number) {
    return typeof vimApiBufGetOffset !== 'undefined' ? vimApiBufGetOffset(buffer, line) : -1;
  },

  bufCall(buffer: number, fun: () => unknown) {
    return typeof vimApiBufCall !== 'undefined' ? vimApiBufCall(buffer, fun) : fun();
  },

  bufGetCharAt(buffer: number, row: number, col: number) {
    return typeof vimApiBufGetCharAt !== 'undefined' ? vimApiBufGetCharAt(buffer, row, col) : ' ';
  },

  bufSetOption(buffer: number, name: string, value: unknown) {
    if (typeof vimApiBufSetOption !== 'undefined') vimApiBufSetOption(buffer, name, value);
  },

  // Window functions
  getCurrentWin() {
    return typeof vimApiGetCurrentWin !== 'undefined' ? vimApiGetCurrentWin() : 0;
  },

  winGetCursor(window: number) {
    if (typeof vimApiWinGetCursor !== 'undefined') return vimApiWinGetCursor(window);
    throw new Error('winGetCursor not available');
  },

  winSetCursor(window: number, pos: [number, number]) {
    if (typeof vimApiWinSetCursor !== 'undefined') return vimApiWinSetCursor(window, pos);
    throw new Error('winSetCursor not available');
  },

  winIsValid(window: number) {
    return typeof vimApiWinIsValid !== 'undefined' ? vimApiWinIsValid(window) : window === 0;
  },

  winGetBuf(window: number) {
    return typeof vimApiWinGetBuf !== 'undefined' ? vimApiWinGetBuf(window) : 0;
  },

  winGetHeight(window: number) {
    return typeof vimApiWinGetHeight !== 'undefined' ? vimApiWinGetHeight(window) : 24;
  },

  winGetWidth(window: number) {
    return typeof vimApiWinGetWidth !== 'undefined' ? vimApiWinGetWidth(window) : 80;
  },

  setCurrentWin(window: number) {
    if (typeof vimApiSetCurrentWin !== 'undefined') vimApiSetCurrentWin(window);
  },

  listWins() {
    return typeof vimApiListWins !== 'undefined' ? vimApiListWins() : [0];
  },

  winSetBuf(window: number, buffer: number) {
    if (typeof vimApiWinSetBuf !== 'undefined') vimApiWinSetBuf(window, buffer);
  },

  winSetHeight(window: number, height: number) {
    if (typeof vimApiWinSetHeight !== 'undefined') vimApiWinSetHeight(window, height);
  },

  winSetWidth(window: number, width: number) {
    if (typeof vimApiWinSetWidth !== 'undefined') vimApiWinSetWidth(window, width);
  },

  winClose(window: number, force: boolean) {
    if (typeof vimApiWinClose !== 'undefined') vimApiWinClose(window, force);
  },

  winGetVar(window: number, name: string) {
    return typeof vimApiWinGetVar !== 'undefined' ? vimApiWinGetVar(window, name) : undefined;
  },

  winSetVar(window: number, name: string, value: unknown) {
    if (typeof vimApiWinSetVar !== 'undefined') vimApiWinSetVar(window, name, value);
  },

  winDelVar(window: number, name: string) {
    if (typeof vimApiWinDelVar !== 'undefined') vimApiWinDelVar(window, name);
  },

  winCall(window: number, fun: () => unknown) {
    if (typeof vimApiWinCall !== 'undefined') return vimApiWinCall(window, fun);
    if (window !== 0) return undefined;
    return fun();
  },

  winGetNumber(window: number) {
    return typeof vimApiWinGetNumber !== 'undefined' ? vimApiWinGetNumber(window) : 1;
  },

  winGetPosition(window: number) {
    return typeof vimApiWinGetPosition !== 'undefined' ? vimApiWinGetPosition(window) : [0, 0];
  },

  // Floating window functions
  openWin(buf: number, enter: boolean, config: object) {
    if (typeof vimApiOpenWin !== 'undefined') return vimApiOpenWin(buf, enter, config);
    throw new Error('openWin not available');
  },

  winSetConfig(window: number, config: object) {
    if (typeof vimApiWinSetConfig !== 'undefined') vimApiWinSetConfig(window, config);
  },

  winGetConfig(window: number) {
    return typeof vimApiWinGetConfig !== 'undefined' ? vimApiWinGetConfig(window) : null;
  },

  winHide(window: number) {
    if (typeof vimApiWinHide !== 'undefined') vimApiWinHide(window);
  },

  winSetOption(window: number, name: string, value: unknown) {
    if (typeof vimApiWinSetOption !== 'undefined') vimApiWinSetOption(window, name, value);
  },

  winGetOption(window: number, name: string) {
    return typeof vimApiWinGetOption !== 'undefined' ? vimApiWinGetOption(window, name) : null;
  },

  // Highlight functions
  setHighlight(ns: number, name: string, opts: object) {
    vimApiSetHighlight(ns, name, opts);
  },

  createNamespace(name: string) {
    return typeof vimApiCreateNamespace !== 'undefined' ? vimApiCreateNamespace(name) : 0;
  },

  getNamespaces() {
    return typeof vimApiGetNamespaces !== 'undefined' ? vimApiGetNamespaces() : {};
  },

  bufAddHighlight(buffer: number, ns: number, hlGroup: string, line: number, colStart: number, colEnd: number) {
    return typeof vimApiBufAddHighlight !== 'undefined' ? vimApiBufAddHighlight(buffer, ns, hlGroup, line, colStart, colEnd) : 0;
  },

  bufClearNamespace(buffer: number, ns: number, lineStart: number, lineEnd: number) {
    if (typeof vimApiBufClearNamespace !== 'undefined') vimApiBufClearNamespace(buffer, ns, lineStart, lineEnd);
  },

  getHighlight(ns: number, nameOrOpts: string | object) {
    return typeof vimApiGetHighlight !== 'undefined' ? vimApiGetHighlight(ns, nameOrOpts as object) : {};
  },

  // Extmark functions
  bufSetExtmark(buffer: number, ns: number, line: number, col: number, opts: object) {
    return typeof vimApiBufSetExtmark !== 'undefined' ? vimApiBufSetExtmark(buffer, ns, line, col, opts) : 0;
  },

  bufGetExtmarks(buffer: number, ns: number, start: number | [number, number], end: number | [number, number], opts?: object) {
    return typeof vimApiBufGetExtmarks !== 'undefined' ? vimApiBufGetExtmarks(buffer, ns, start, end, opts || {}) : [];
  },

  bufDelExtmark(buffer: number, ns: number, id: number) {
    return typeof vimApiBufDelExtmark !== 'undefined' ? vimApiBufDelExtmark(buffer, ns, id) : false;
  },

  bufGetExtmarkById(buffer: number, ns: number, id: number, opts?: object) {
    return typeof vimApiBufGetExtmarkById !== 'undefined' ? vimApiBufGetExtmarkById(buffer, ns, id, opts || {}) : null;
  },

  // Autocmd functions
  createAutocmd(events: string | string[], opts: object) {
    if (typeof vimApiCreateAutoCommand !== 'undefined') return vimApiCreateAutoCommand(events, opts);
    throw new Error('createAutocmd not available (headless mode)');
  },

  delAutocmd(id: number) {
    if (typeof vimApiDeleteAutoCommand !== 'undefined') return vimApiDeleteAutoCommand(id);
    throw new Error('delAutocmd not available (headless mode)');
  },

  createAugroup(name: string, opts: object) {
    if (typeof vimApiCreateAutoGroup !== 'undefined') return vimApiCreateAutoGroup(name, opts || {});
    throw new Error('createAugroup not available (headless mode)');
  },

  clearAutocmds(opts: object) {
    if (typeof vimApiClearAutoCommands !== 'undefined') return vimApiClearAutoCommands(opts || {});
    throw new Error('clearAutocmds not available (headless mode)');
  },

  // Command functions
  createUserCmd(name: string, command: string | ((...args: unknown[]) => void), opts: object) {
    if (typeof createUserCommand !== 'undefined') return createUserCommand(name, command, opts || {});
    consoleAPI.log('[vim.api] createUserCmd not yet implemented, skipping:', name);
  },

  delUserCmd(name: string) {
    if (typeof deleteUserCommand !== 'undefined') return deleteUserCommand(name);
  },

  bufCreateUserCmd(buffer: number, name: string, command: string | ((...args: unknown[]) => void), opts: object) {
    if (typeof bufCreateUserCommand !== 'undefined') return bufCreateUserCommand(buffer, name, command, opts || {});
    consoleAPI.log('[vim.api] bufCreateUserCmd not yet implemented, skipping:', name);
  },

  bufDelUserCmd(buffer: number, name: string) {
    if (typeof bufDeleteUserCommand !== 'undefined') return bufDeleteUserCommand(buffer, name);
  },

  getUserCommands(opts: object) {
    return typeof getUserCommands !== 'undefined' ? getUserCommands(opts || {}) : {};
  },

  // Mode functions
  getMode() {
    if (typeof vimApiGetMode !== 'undefined') return vimApiGetMode();
    return { mode: 'n', blocking: false };
  },

  getOption(name: string) {
    return (vim as any).opt[name];
  }
};

Object.freeze(vimApi);

// ============================================================================
// vim.fn - Vimscript Function Wrappers
// ============================================================================

const vimFn = {
  getwininfo(winid?: number): object[] {
    const wins = vimApi.listWins();
    const result: object[] = [];

    for (const w of wins) {
      if (winid !== undefined && w !== winid) continue;

      const pos = vimApi.winGetPosition(w) || [0, 0];
      const info = {
        winid: w,
        bufnr: vimApi.winGetBuf(w),
        winnr: vimApi.winGetNumber(w),
        height: vimApi.winGetHeight(w),
        width: vimApi.winGetWidth(w),
        winrow: pos[0],
        wincol: pos[1],
        terminal: 0,
        quickfix: 0,
        loclist: 0,
        textoff: 0,
      };
      result.push(info);
    }

    return result;
  },

  winsaveview(): object {
    const pos = vimApi.winGetCursor(0);
    return {
      lnum: pos ? pos[0] : 1,
      col: pos ? pos[1] : 0,
      coladd: 0,
      curswant: pos ? pos[1] : 0,
      topline: 1,
      topfill: 0,
      leftcol: 0,
      skipcol: 0,
    };
  },

  winrestview(view: { lnum?: number; col?: number }): void {
    if (view && view.lnum !== undefined) {
      vimApi.winSetCursor(0, [view.lnum, view.col || 0]);
    }
  },

  line(expr: string): number {
    if (expr === '.') {
      const pos = vimApi.winGetCursor(0);
      return pos ? pos[0] : 1;
    } else if (expr === '$') {
      return vimApi.bufLineCount(0);
    } else if (expr === 'w0') {
      return 1;
    } else if (expr === 'w$') {
      return vimApi.winGetHeight(0);
    }
    return 0;
  },

  col(expr: string): number {
    if (expr === '.') {
      const pos = vimApi.winGetCursor(0);
      return pos ? pos[1] + 1 : 1;
    } else if (expr === '$') {
      const pos = vimApi.winGetCursor(0);
      if (pos) {
        const lines = vimApi.bufGetLines(0, pos[0] - 1, pos[0], false);
        return lines && lines[0] ? lines[0].length + 1 : 1;
      }
      return 1;
    }
    return 0;
  },

  winnr(): number {
    return vimApi.winGetNumber(0);
  },

  bufnr(expr?: string | number): number {
    if (expr === undefined || expr === '%') {
      return vimApi.getCurrentBuf();
    }
    return -1;
  },

  bufname(expr?: string | number): string {
    const bufnr = expr === undefined || expr === '%' ? 0 : (expr as number);
    return vimApi.bufGetName(bufnr);
  },

  expand(expr: string): string {
    if (expr === '%') {
      return vimApi.bufGetName(0);
    } else if (expr === '%:p') {
      return vimApi.bufGetName(0);
    } else if (expr === '%:t') {
      const name = vimApi.bufGetName(0);
      return name.split('/').pop() || '';
    }
    return expr;
  },

  mode(): string {
    const modeInfo = vimApi.getMode();
    return modeInfo.mode;
  },

  has(feature: string): number {
    const supported = [
      'nvim', 'vimcraft', 'timers', 'syntax', 'autocmd',
      'signs', 'virtual_text', 'highlighting',
    ];
    return supported.includes(feature) ? 1 : 0;
  },

  exists(expr: string): number {
    if (expr.startsWith('*')) {
      const fn = expr.slice(1);
      return typeof (vimFn as any)[fn] === 'function' ? 1 : 0;
    }
    if (expr.startsWith('g:')) {
      return (vim as any).g && (vim as any).g[expr.slice(2)] !== undefined ? 1 : 0;
    }
    return 0;
  },

  // Get current working directory
  getCwd(): string {
    if (typeof __process !== 'undefined' && typeof __process.cwd === 'function') {
      return __process.cwd();
    }
    return '';
  },

  /**
   * Modify filename according to modifiers.
   * :p - full path
   * :h - head (directory)
   * :t - tail (filename)
   * :r - root (remove extension)
   * :e - extension only
   */
  fnameModify(path: string, mods: string): string {
    if (!path) return '';

    let result = path;

    // Parse modifiers - they can be chained like :p:h:t
    const modList = mods.split(':').filter(m => m.length > 0);

    for (const mod of modList) {
      switch (mod) {
        case 'p':
          // Full path - if not absolute, prepend cwd
          if (!result.startsWith('/')) {
            const cwd = vimFn.getCwd();
            result = cwd ? cwd + '/' + result : result;
          }
          break;
        case 'h':
          // Head (directory part)
          const lastSlash = result.lastIndexOf('/');
          if (lastSlash > 0) {
            result = result.substring(0, lastSlash);
          } else if (lastSlash === 0) {
            result = '/';
          } else {
            result = '.';
          }
          break;
        case 't':
          // Tail (filename part)
          const slashIdx = result.lastIndexOf('/');
          if (slashIdx >= 0) {
            result = result.substring(slashIdx + 1);
          }
          break;
        case 'r':
          // Root (remove last extension)
          const dotIdx = result.lastIndexOf('.');
          const slashForR = result.lastIndexOf('/');
          if (dotIdx > slashForR + 1) {
            result = result.substring(0, dotIdx);
          }
          break;
        case 'e':
          // Extension only
          const dotForE = result.lastIndexOf('.');
          const slashForE = result.lastIndexOf('/');
          if (dotForE > slashForE + 1) {
            result = result.substring(dotForE + 1);
          } else {
            result = '';
          }
          break;
      }
    }

    return result;
  },

  fileReadable(path: string): number {
    if (typeof __fs === 'undefined') return 0;

    const fs = __fs as { existsSync?: (path: string) => boolean; statSync?: (path: string) => { isFile(): boolean } | null };
    if (typeof fs.existsSync !== 'function') return 0;

    try {
      if (!fs.existsSync(path)) return 0;
      // Check if it's a file (not directory)
      if (typeof fs.statSync === 'function') {
        const stat = fs.statSync(path);
        return stat && stat.isFile() ? 1 : 0;
      }
      return 1; // If we can't check, assume it's readable
    } catch {
      return 0;
    }
  },

  isDirectory(path: string): number {
    if (typeof __fs === 'undefined') return 0;

    const fs = __fs as { existsSync?: (path: string) => boolean; statSync?: (path: string) => { isDirectory(): boolean } | null };
    if (typeof fs.existsSync !== 'function') return 0;

    try {
      if (!fs.existsSync(path)) return 0;
      if (typeof fs.statSync === 'function') {
        const stat = fs.statSync(path);
        return stat && stat.isDirectory() ? 1 : 0;
      }
      return 0;
    } catch {
      return 0;
    }
  },

  getLine(lnum: number | string): string | string[] {
    // Handle special cases
    if (lnum === '.') {
      const pos = vimApi.winGetCursor(0);
      lnum = pos ? pos[0] : 1;
    } else if (lnum === '$') {
      lnum = vimApi.bufLineCount(0);
    }

    if (typeof lnum !== 'number') {
      lnum = parseInt(lnum as string, 10);
    }

    if (isNaN(lnum) || lnum < 1) return '';

    // vim.fn.getline is 1-indexed, bufGetLines is 0-indexed
    const lines = vimApi.bufGetLines(0, lnum - 1, lnum, false);
    return lines && lines.length > 0 ? lines[0] : '';
  },

  executable(cmd: string): number {
    // Check if command exists in PATH
    // On Unix-like systems, we can check common paths
    if (typeof __fs === 'undefined') return 0;

    const fs = __fs as { existsSync?: (path: string) => boolean };
    if (typeof fs.existsSync !== 'function') return 0;

    // If it's an absolute path, check directly
    if (cmd.startsWith('/')) {
      return fs.existsSync(cmd) ? 1 : 0;
    }

    // Check common binary directories
    const paths = [
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/opt/homebrew/bin',  // macOS ARM homebrew
      '/usr/local/sbin',
      '/usr/sbin',
      '/sbin',
    ];

    // Also check PATH environment variable if available
    if (typeof __process !== 'undefined' && __process.env && __process.env.PATH) {
      const envPaths = __process.env.PATH.split(':');
      for (const p of envPaths) {
        if (p && paths.indexOf(p) === -1) {
          paths.push(p);
        }
      }
    }

    for (const dir of paths) {
      const fullPath = dir + '/' + cmd;
      if (fs.existsSync(fullPath)) {
        return 1;
      }
    }

    return 0;
  },

  // Screen functions (Neovim-compatible)
  // Note: These read from the compositor output grid

  /**
   * Returns the character at screen position [row, col].
   * Uses 0-based indexing (JavaScript convention).
   * Returns 0 for out of range positions.
   */
  screenchar(row: number, col: number): number {
    return vimLayer.screenchar(row, col);
  },

  /**
   * Returns the foreground color at screen position [row, col] as hex (0xRRGGBB).
   * Uses 0-based indexing (JavaScript convention).
   * Returns null if no color is set.
   */
  screenFg(row: number, col: number): number | null {
    return vimLayer.screenFg(row, col);
  },

  /**
   * Returns the background color at screen position [row, col] as hex (0xRRGGBB).
   * Uses 0-based indexing (JavaScript convention).
   * Returns null if no color is set.
   */
  screenBg(row: number, col: number): number | null {
    return vimLayer.screenBg(row, col);
  },
};

Object.freeze(vimFn);

// ============================================================================
// vim.autocmd - Autocommand API
// ============================================================================

const vimAutocmd = {
  create(eventOrGroup: string | string[], optsOrEvent?: object | string, callbackOrUndef?: () => void): number | number[] {
    if (typeof callbackOrUndef === 'function') {
      // smear-cursor style: (group, event, callback)
      const group = eventOrGroup as string;
      const event = optsOrEvent as string;
      const callback = callbackOrUndef;
      return vimApi.createAutocmd(event, { callback, group });
    } else {
      // Neovim style: (event, opts)
      // Handle array of events by creating multiple autocmds
      if (Array.isArray(eventOrGroup)) {
        const ids: number[] = [];
        for (const event of eventOrGroup) {
          const id = vimApi.createAutocmd(event, optsOrEvent as object);
          ids.push(id);
        }
        return ids.length === 1 ? ids[0] : ids;
      }
      return vimApi.createAutocmd(eventOrGroup, optsOrEvent as object);
    }
  },

  delete(id: number): void {
    vimApi.delAutocmd(id);
  },

  group(name: string, opts?: object): number {
    return vimApi.createAugroup(name, opts || {});
  },

  clear(groupOrOpts: string | object): void {
    if (typeof groupOrOpts === 'string') {
      vimApi.clearAutocmds({ group: groupOrOpts });
    } else {
      vimApi.clearAutocmds(groupOrOpts);
    }
  },
};

Object.freeze(vimAutocmd);

// ============================================================================
// vim.diagnostic - Diagnostic API (Neovim-compatible)
// ============================================================================

/**
 * Diagnostic severity levels
 */
const DiagnosticSeverity = {
  ERROR: 1,
  WARN: 2,
  INFO: 3,
  HINT: 4,
  // Reverse mappings (numeric index -> string)
  1: 'ERROR',
  2: 'WARN',
  3: 'INFO',
  4: 'HINT',
} as const;

interface Diagnostic {
  lnum: number;
  col: number;
  endLnum?: number;
  endCol?: number;
  severity?: number;
  message: string;
  source?: string;
  code?: string;
  bufnr?: number;
}

interface DiagnosticGetOpts {
  namespace?: number;
  lnum?: number;
  severity?: number;
}

interface DiagnosticCountOpts {
  namespace?: number;
}

const vimDiagnostic = {
  /**
   * Diagnostic severity levels (Neovim-compatible)
   */
  severity: DiagnosticSeverity,

  /**
   * Set diagnostics for a buffer under a namespace
   * @param namespace - Namespace ID from vim.api.createNamespace()
   * @param bufnr - Buffer number (0 for current)
   * @param diagnostics - Array of diagnostic objects
   * @param opts - Optional configuration
   */
  set(namespace: number, bufnr: number, diagnostics: Diagnostic[], opts?: object): void {
    vimDiagnosticSet(namespace, bufnr, diagnostics);
  },

  /**
   * Get diagnostics from buffer(s)
   * @param bufnr - Buffer number (undefined for all buffers)
   * @param opts - Filter options (namespace, lnum, severity)
   */
  get(bufnr?: number, opts?: DiagnosticGetOpts): Diagnostic[] {
    return vimDiagnosticGet(bufnr, opts || {});
  },

  /**
   * Clear diagnostics
   * @param namespace - Namespace to clear (undefined for all)
   * @param bufnr - Buffer to clear (undefined for all buffers)
   */
  reset(namespace?: number, bufnr?: number): void {
    vimDiagnosticReset(namespace, bufnr);
  },

  /**
   * Count diagnostics by severity
   * @param bufnr - Buffer number (undefined for all buffers)
   * @param opts - Filter options (namespace)
   * @returns Object with severity keys and counts
   */
  count(bufnr?: number, opts?: DiagnosticCountOpts): Record<number, number> {
    return vimDiagnosticCount(bufnr, opts || {});
  },
};

Object.freeze(vimDiagnostic);
Object.freeze(vimDiagnostic.severity);

// ============================================================================
// vim.cmd - Ex Command Methods
// ============================================================================

const vimCmd = {
  wincmd(direction: string): void {
    if (typeof vimWincmd !== 'undefined') vimWincmd(direction);
  },

  vsplit(file?: string): void {
    if (typeof vimCmdVsplit !== 'undefined') vimCmdVsplit(file || '');
  },

  split(file?: string): void {
    if (typeof vimCmdSplit !== 'undefined') vimCmdSplit(file || '');
  },

  write(): void {
    if (typeof vimCmdWrite !== 'undefined') vimCmdWrite();
  },

  quit(): void {
    if (typeof vimCmdQuit !== 'undefined') vimCmdQuit();
  },

  edit(file?: string): void {
    if (typeof vimCmdEdit !== 'undefined') vimCmdEdit(file || '');
  },

  new(): void {
    if (typeof vimCmdNew !== 'undefined') vimCmdNew();
  },

  vnew(): void {
    if (typeof vimCmdVnew !== 'undefined') vimCmdVnew();
  },

  only(): void {
    if (typeof vimCmdOnly !== 'undefined') vimCmdOnly();
  },

  close(): void {
    if (typeof vimCmdClose !== 'undefined') vimCmdClose();
  },
};

Object.freeze(vimCmd);

// ============================================================================
// Main Vim Object
// ============================================================================

interface VimObject {
  highlight(name: string, opts: object): void;
  opt: Record<string, unknown>;
  optLocal: Record<string, unknown>;
  optGlobal: Record<string, unknown>;
  bo: Record<string, unknown>;
  cursor?: object;
  layer: object;
  motion: object;
  keymap: {
    set(mode: string, lhs: string, rhs: string | (() => void), opts?: object): void;
    del(mode: string, lhs: string): void;
  };
  filetype: object;
  buffer?: object;
  api: VimAPI;
  autocmd: typeof vimAutocmd;
  diagnostic: typeof vimDiagnostic;
  cmd: typeof vimCmd;
  fn: typeof vimFn;
  lsp: object;
  e2e: object;
  g: Record<string, unknown>;
  schedule(callback: () => void): void;
  defer(callback: () => void, delay?: number): void;
  notify(message: string, level?: string): void;
  on?: (event: string, callback: (...args: unknown[]) => void) => void;
  off?: (event: string, callback: (...args: unknown[]) => void) => void;
  emit?: (event: string, ...args: unknown[]) => void;
  removeAllListeners?: (event?: string) => void;
  listenerCount?: (event: string) => number;
  metrics?: object;
  [key: string]: unknown;
}

const vim: VimObject = {
  highlight(name: string, opts: object): void {
    vimApiSetHighlight(0, name, opts);
  },

  opt: createOptionsProxy('vim.opt', vimOpt, getAllOptions),
  optLocal: createOptionsProxy('vim.optLocal', vimOptLocal, () => getAllOptionsWithScope('local')),
  optGlobal: createOptionsProxy('vim.optGlobal', vimOptGlobal, () => getAllOptionsWithScope('global')),

  bo: new Proxy(
    { get [Symbol.toStringTag]() { return 'vim.bo'; } },
    {
      get(target, prop) {
        if (prop === Symbol.toStringTag) return 'vim.bo';
        if (typeof prop === 'symbol') return undefined;
        return vimBo[prop as string];
      },
      set(target, prop, value) {
        if (typeof prop === 'symbol') return false;
        vimBo[prop as string] = value;
        return true;
      },
      has(target, prop) {
        if (typeof prop === 'symbol') return false;
        return vimBo[prop as string] !== undefined;
      },
      ownKeys() {
        return ['filetype'];
      },
      getOwnPropertyDescriptor(target, prop) {
        if (typeof prop === 'symbol') return undefined;
        const value = vimBo[prop as string];
        if (value === undefined) return undefined;
        return { value, enumerable: true, configurable: true, writable: true };
      }
    }
  ),

  layer: vimLayer,
  motion: vimMotion,

  keymap: {
    set(mode: string, lhs: string, rhs: string | (() => void), opts?: object): void {
      if (typeof rhs === 'function') {
        const id = (globalThis as any)._nextKeymapId++;
        (globalThis as any)._keymapCallbacks[id] = rhs;
        vimKeymap.set(mode, lhs, id, opts);
      } else {
        vimKeymap.set(mode, lhs, rhs, opts);
      }
    },
    del(mode: string, lhs: string): void {
      vimKeymap.del(mode, lhs);
    }
  },

  filetype: vimFiletype,
  treesitter: vimTreesitter,
  api: vimApi,
  autocmd: vimAutocmd,
  diagnostic: vimDiagnostic,
  cmd: vimCmd,
  fn: vimFn,
  lsp: {},
  e2e: {},
  g: {},

  schedule(callback: () => void): void {
    (globalThis as any).setTimeout(callback, 0);
  },

  defer(callback: () => void, delay?: number): void {
    (globalThis as any).setTimeout(callback, delay || 0);
  },

  notify(_message: string, _level?: string): void {
    // TODO: Implement notification display
  }
};

// Add optional cursor API
if (typeof vimCursor !== 'undefined') {
  vim.cursor = vimCursor;
}

// Add optional buffer API
if (typeof vimBuffer !== 'undefined') {
  vim.buffer = vimBuffer;
  Object.freeze(vim.buffer);
}

// Add event emitter if available
if (typeof vimEventEmitter !== 'undefined') {
  vim.on = vimEventEmitter.on;
  vim.off = vimEventEmitter.off;
  vim.emit = vimEventEmitter.emit;
  vim.removeAllListeners = vimEventEmitter.removeAllListeners;
  vim.listenerCount = vimEventEmitter.listenerCount;
}

// Add metrics if available
if (typeof vimMetrics !== 'undefined') {
  vim.metrics = vimMetrics;
  Object.freeze(vim.metrics);
}

// Add E2E API if available
if (typeof vimE2E !== 'undefined') {
  vim.e2e = vimE2E;
  Object.freeze(vim.e2e);
}

// Freeze immutable APIs
Object.freeze(vim.motion);
Object.freeze(vim.keymap);
Object.freeze(vim.filetype);
Object.freeze(vim.api);
Object.freeze(vim.diagnostic);

// Make vim global
(globalThis as any).vim = vim;

// ============================================================================
// Keymap Callback Registry
// ============================================================================

(globalThis as any)._keymapCallbacks = {} as Record<number, () => void>;
(globalThis as any)._nextKeymapId = 1;

(globalThis as any).__handleKeymapCallback = (id: number): void => {
  const callback = (globalThis as any)._keymapCallbacks[id];
  if (callback) {
    try {
      callback();
    } catch (e) {
      consoleAPI.log('Keymap callback error:', e);
    }
  } else {
    consoleAPI.log('[Keymap] No callback found for id:', id);
  }
};

// ============================================================================
// Legacy Motion Wrappers
// ============================================================================

const _legacyMotion = {
  left: () => moveLeft(),
  right: () => moveRight(),
  up: () => moveUp(),
  down: () => moveDown(),
  toLineStart: () => moveToLineStart(),
  toLineEnd: () => moveToLineEnd(),
  toFirstNonBlank: () => moveToFirstNonBlank(),
  wordForward: () => moveWordForward(),
  wordBackward: () => moveWordBackward(),
  wordEnd: () => moveWordEnd(),
  toFileStart: () => moveToFileStart(),
  toFileEnd: () => moveToFileEnd(),
  toViewportTop: () => moveToViewportTop(),
  toViewportMiddle: () => moveToViewportMiddle(),
  toViewportBottom: () => moveToViewportBottom(),
  scrollHalfPageDown: () => scrollHalfPageDown(),
  scrollHalfPageUp: () => scrollHalfPageUp(),
};

// ============================================================================
// File System API
// ============================================================================

if (typeof __fs !== 'undefined') {
  (globalThis as any).fs = __fs;
  Object.freeze((globalThis as any).fs);
}

// ============================================================================
// Process API
// ============================================================================

if (typeof __process !== 'undefined') {
  const originalSpawn = __process.spawn;
  (globalThis as any).process = Object.assign({}, __process, {
    exec(cmd: string, args?: string[], opts?: { env?: Record<string, string> }) {
      let nativeOpts = opts;
      if (opts && opts.env && typeof opts.env === 'object') {
        nativeOpts = { ...opts, env: { ...opts.env, __keys: Object.keys(opts.env) } };
      }
      return originalSpawn.call(__process, cmd, args || [], nativeOpts || {});
    }
  });
  Object.freeze((globalThis as any).process);
}

// ============================================================================
// AbortController / AbortSignal (ES5-compatible for Hermes)
// ============================================================================

// DOMException polyfill using Error.call pattern (ES5 inheritance)
interface DOMExceptionPolyfill extends Error {
  name: string;
}

function DOMExceptionPolyfill(this: DOMExceptionPolyfill, message: string, name: string = 'DOMException'): void {
  Error.call(this, message);
  this.message = message;
  this.name = name;
}
DOMExceptionPolyfill.prototype = Object.create(Error.prototype);
DOMExceptionPolyfill.prototype.constructor = DOMExceptionPolyfill;

// AbortSignal using constructor function pattern
interface AbortSignal {
  _aborted: boolean;
  _reason: Error | undefined;
  _listeners: ((ev: { type: string; target: AbortSignal }) => void)[];
  aborted: boolean;
  reason: Error | undefined;
  addEventListener(type: string, listener: (ev: { type: string; target: AbortSignal }) => void): void;
  removeEventListener(type: string, listener: (ev: { type: string; target: AbortSignal }) => void): void;
  throwIfAborted(): void;
  _abort(reason?: Error): void;
}

interface AbortSignalConstructor {
  new (): AbortSignal;
  (): AbortSignal;
  prototype: AbortSignal;
  timeout(ms: number): AbortSignal;
}

const AbortSignal = function(this: AbortSignal): void {
  this._aborted = false;
  this._reason = undefined;
  this._listeners = [];
} as unknown as AbortSignalConstructor;

Object.defineProperty(AbortSignal.prototype, 'aborted', {
  get: function(this: AbortSignal): boolean { return this._aborted; },
  enumerable: true,
  configurable: true
});

Object.defineProperty(AbortSignal.prototype, 'reason', {
  get: function(this: AbortSignal): Error | undefined { return this._reason; },
  enumerable: true,
  configurable: true
});

AbortSignal.prototype.addEventListener = function(this: AbortSignal, type: string, listener: (ev: { type: string; target: AbortSignal }) => void): void {
  if (type === 'abort') {
    this._listeners.push(listener);
  }
};

AbortSignal.prototype.removeEventListener = function(this: AbortSignal, type: string, listener: (ev: { type: string; target: AbortSignal }) => void): void {
  if (type === 'abort') {
    const idx = this._listeners.indexOf(listener);
    if (idx !== -1) this._listeners.splice(idx, 1);
  }
};

AbortSignal.prototype.throwIfAborted = function(this: AbortSignal): void {
  if (this._aborted) {
    throw this._reason;
  }
};

AbortSignal.prototype._abort = function(this: AbortSignal, reason?: Error): void {
  if (this._aborted) return;
  this._aborted = true;
  this._reason = reason || new (DOMExceptionPolyfill as any)('The operation was aborted', 'AbortError');
  for (const listener of this._listeners) {
    try {
      listener({ type: 'abort', target: this });
    } catch (e) {
      consoleAPI.log('[AbortSignal] Listener error:', e);
    }
  }
};

AbortSignal.timeout = function(ms: number): AbortSignal {
  const controller = new (AbortController as any)();
  (globalThis as any).setTimeout(() => {
    controller.abort(new (DOMExceptionPolyfill as any)('The operation timed out', 'TimeoutError'));
  }, ms);
  return controller.signal;
};

// AbortController using constructor function pattern
interface AbortController {
  _signal: AbortSignal;
  signal: AbortSignal;
  abort(reason?: Error): void;
}

interface AbortControllerConstructor {
  new (): AbortController;
  (): AbortController;
  prototype: AbortController;
}

const AbortController = function(this: AbortController): void {
  this._signal = new (AbortSignal as any)();
} as unknown as AbortControllerConstructor;

Object.defineProperty(AbortController.prototype, 'signal', {
  get: function(this: AbortController): AbortSignal { return this._signal; },
  enumerable: true,
  configurable: true
});

AbortController.prototype.abort = function(this: AbortController, reason?: Error): void {
  this._signal._abort(reason);
};

(globalThis as any).AbortController = AbortController;
(globalThis as any).AbortSignal = AbortSignal;
(globalThis as any).DOMException = DOMExceptionPolyfill;

// ============================================================================
// Fetch API
// ============================================================================

interface FetchCallbackEntry {
  resolve: (response: object) => void;
  reject: (error: Error) => void;
  signal?: AbortSignal;
  abortListener?: () => void;
}

(globalThis as any)._fetchCallbacks = {} as Record<number, FetchCallbackEntry>;
(globalThis as any)._nextFetchId = 1;

(globalThis as any).__handleFetchCallback = (id: number, result: { success?: boolean; error?: string; status?: number; statusText?: string; body?: string }): void => {
  const callbacks = (globalThis as any)._fetchCallbacks[id] as FetchCallbackEntry | undefined;
  delete (globalThis as any)._fetchCallbacks[id];

  if (!callbacks) return;

  const { resolve, reject, signal, abortListener } = callbacks;

  if (signal && abortListener) {
    signal.removeEventListener('abort', abortListener);
  }

  if (signal && signal.aborted) {
    reject(signal.reason || new DOMExceptionPolyfill('The operation was aborted', 'AbortError'));
    return;
  }

  if (result.error) {
    if (result.error.includes('cancelled') || result.error.includes('canceled')) {
      reject(new DOMExceptionPolyfill('The operation was aborted', 'AbortError'));
    } else {
      reject(new Error(result.error));
    }
    return;
  }

  if (!result.success) {
    reject(new Error(result.error || 'Fetch failed'));
    return;
  }

  const response = {
    status: result.status,
    ok: result.status! >= 200 && result.status! < 300,
    statusText: result.statusText,
    _body: result.body,
    text() {
      return this._body;
    },
    json() {
      return JSON.parse(this._body);
    }
  };

  resolve(response);
};

if (typeof __nativeFetch !== 'undefined') {
  (globalThis as any).fetch = (url: string, options?: { method?: string; headers?: object; body?: string; signal?: AbortSignal; maxResponseSize?: number }): Promise<object> => {
    return new Promise((resolve, reject) => {
      const opts = options || {};
      const signal = opts.signal;

      if (signal && signal.aborted) {
        reject(signal.reason || new DOMExceptionPolyfill('The operation was aborted', 'AbortError'));
        return;
      }

      const id = (globalThis as any)._nextFetchId++;

      let abortListener: (() => void) | undefined;
      if (signal) {
        abortListener = () => {
          if (typeof __abortFetch !== 'undefined') {
            __abortFetch(id);
          }
          const callbacks = (globalThis as any)._fetchCallbacks[id] as FetchCallbackEntry | undefined;
          if (callbacks) {
            delete (globalThis as any)._fetchCallbacks[id];
            callbacks.reject(signal.reason || new DOMExceptionPolyfill('The operation was aborted', 'AbortError'));
          }
        };
        signal.addEventListener('abort', abortListener);
      }

      (globalThis as any)._fetchCallbacks[id] = { resolve, reject, signal, abortListener };

      try {
        __nativeFetch(id, url, {
          method: opts.method,
          headers: opts.headers,
          body: opts.body,
          maxResponseSize: opts.maxResponseSize
        });
      } catch (e) {
        delete (globalThis as any)._fetchCallbacks[id];
        if (signal && abortListener) {
          signal.removeEventListener('abort', abortListener);
        }
        reject(e);
      }
    });
  };
}

// ============================================================================
// Async Subprocess API
// ============================================================================

interface ProcessCallbackEntry {
  onStdout: ((data: string) => void) | null;
  onStderr: ((data: string) => void) | null;
  onExit: ((code: number, signal: string) => void) | null;
}

(globalThis as any)._processCallbacks = {} as Record<number, ProcessCallbackEntry>;

(globalThis as any).__handleProcessEvent = (id: number, event: string, data: { data?: string; code?: number; signal?: string }): void => {
  const callbacks = (globalThis as any)._processCallbacks[id] as ProcessCallbackEntry | undefined;
  if (!callbacks) return;

  try {
    if (event === 'stdout' && callbacks.onStdout) {
      callbacks.onStdout(data.data!);
    } else if (event === 'stderr' && callbacks.onStderr) {
      callbacks.onStderr(data.data!);
    } else if (event === 'exit') {
      if (callbacks.onExit) {
        callbacks.onExit(data.code!, data.signal!);
      }
      delete (globalThis as any)._processCallbacks[id];
    }
  } catch (e) {
    consoleAPI.log('[process.spawn] Callback error:', e);
  }
};

if (typeof __spawnAsync !== 'undefined') {
  const existingProcess = (globalThis as any).process || {};

  (globalThis as any).process = Object.assign({}, existingProcess, {
    spawn(cmd: string, args?: string[], opts?: { cwd?: string; env?: Record<string, string>; stdin?: string }) {
      if (typeof cmd !== 'string' || cmd.length === 0) {
        throw new Error('spawn requires a command string');
      }

      const nativeOpts: any = opts ? { ...opts } : {};
      if (nativeOpts.env && typeof nativeOpts.env === 'object') {
        nativeOpts.env = { ...nativeOpts.env, __keys: Object.keys(nativeOpts.env) };
      }

      let id: number;
      try {
        id = __spawnAsync(cmd, args || [], nativeOpts);
      } catch (e: any) {
        throw new Error('Failed to spawn process: ' + (e && e.message ? e.message : String(e)));
      }

      if (id === undefined || id === null) {
        throw new Error('Failed to spawn process: unknown error');
      }

      (globalThis as any)._processCallbacks[id] = {
        onStdout: null,
        onStderr: null,
        onExit: null,
      };

      const stdinDisabled = opts && (opts.stdin === 'null' || opts.stdin === 'ignore');

      const childProcess = {
        pid: id,
        stdin: {
          write(data: string): boolean {
            if (stdinDisabled) {
              consoleAPI.log('[process.spawn] Warning: Cannot write to stdin - process spawned with stdin disabled');
              return false;
            }
            if (typeof data !== 'string') {
              data = String(data);
            }
            return __processWrite(id, data);
          },
          end(): boolean {
            if (stdinDisabled) {
              consoleAPI.log('[process.spawn] Warning: Cannot close stdin - process spawned with stdin disabled');
              return false;
            }
            return __processCloseStdin(id);
          }
        },
        kill(signal?: string | number): boolean {
          let sigNum: number | string = 15;
          if (typeof signal === 'number') {
            sigNum = signal;
          } else if (typeof signal === 'string') {
            return __processKill(id, signal);
          }
          return __processKill(id, sigNum);
        },
        onStdout(callback: (data: string) => void) {
          if ((globalThis as any)._processCallbacks[id]) {
            (globalThis as any)._processCallbacks[id].onStdout = callback;
          }
          return this;
        },
        onStderr(callback: (data: string) => void) {
          if ((globalThis as any)._processCallbacks[id]) {
            (globalThis as any)._processCallbacks[id].onStderr = callback;
          }
          return this;
        },
        onExit(callback: (code: number, signal: string) => void) {
          if ((globalThis as any)._processCallbacks[id]) {
            (globalThis as any)._processCallbacks[id].onExit = callback;
          }
          return this;
        },
      };

      return childProcess;
    }
  });
}

// ============================================================================
// PTY (Pseudo-Terminal) API
// ============================================================================

interface PtyCallbackEntry {
  onData: ((data: string) => void) | null;
  onExit: ((code: number, signal: string) => void) | null;
}

(globalThis as any)._ptyCallbacks = {} as Record<number, PtyCallbackEntry>;

(globalThis as any).__handlePtyEvent = (id: number, event: string, data: { data?: string; code?: number; signal?: string }): void => {
  const callbacks = (globalThis as any)._ptyCallbacks[id] as PtyCallbackEntry | undefined;
  if (!callbacks) return;

  try {
    if (event === 'data' && callbacks.onData) {
      callbacks.onData(data.data!);
    } else if (event === 'exit') {
      if (callbacks.onExit) {
        callbacks.onExit(data.code!, data.signal!);
      }
      delete (globalThis as any)._ptyCallbacks[id];
    }
  } catch (e) {
    consoleAPI.log('[process.spawnPty] Callback error:', e);
  }
};

if (typeof __spawnPty !== 'undefined') {
  const existingProcess = (globalThis as any).process || {};

  (globalThis as any).process = Object.assign({}, existingProcess, {
    spawnPty(cmd: string, args?: string[], opts?: { cwd?: string; rows?: number; cols?: number; term?: string; timeout?: number; env?: Record<string, string>; clearEnv?: boolean }) {
      if (typeof cmd !== 'string' || cmd.length === 0) {
        throw new Error('spawnPty requires a command string');
      }

      const nativeOpts: any = opts ? { ...opts } : {};
      if (nativeOpts.env && typeof nativeOpts.env === 'object') {
        nativeOpts.envArray = Object.keys(nativeOpts.env).map(key => `${key}=${String(nativeOpts.env[key])}`);
        delete nativeOpts.env;
      }

      let id: number;
      try {
        id = __spawnPty(cmd, args || [], nativeOpts);
      } catch (e: any) {
        throw new Error('Failed to spawn PTY: ' + (e && e.message ? e.message : String(e)));
      }

      if (id === undefined || id === null) {
        throw new Error('Failed to spawn PTY: unknown error');
      }

      const pid = __ptyGetPid(id);

      (globalThis as any)._ptyCallbacks[id] = {
        onData: null,
        onExit: null,
      };

      const ptyProcess = {
        pid,
        write(data: string): boolean {
          if (typeof data !== 'string') {
            data = String(data);
          }
          return __ptyWrite(id, data);
        },
        resize(rows: number, cols: number): void {
          __ptyResize(id, rows, cols);
        },
        kill(signal?: string | number): boolean {
          let sigNum: number | string = 15;
          if (typeof signal === 'number') {
            sigNum = signal;
          } else if (typeof signal === 'string') {
            return __ptyKill(id, signal);
          }
          return __ptyKill(id, sigNum);
        },
        onData(callback: (data: string) => void) {
          if ((globalThis as any)._ptyCallbacks[id]) {
            (globalThis as any)._ptyCallbacks[id].onData = callback;
          }
          return this;
        },
        onExit(callback: (code: number, signal: string) => void) {
          if ((globalThis as any)._ptyCallbacks[id]) {
            (globalThis as any)._ptyCallbacks[id].onExit = callback;
          }
          return this;
        },
      };

      return ptyProcess;
    }
  });
}

// ============================================================================
// LSP Client (Full Implementation) - ES5 compatible for Hermes
// ============================================================================

// LspFramer using constructor function pattern (ES5 compatible)
interface LspFramerInstance {
  _buffer: string;
  _contentLength: number;
  _onMessage: ((msg: object) => void) | null;
  onMessage(callback: (msg: object) => void): void;
  feed(data: string): void;
  _parseMessages(): void;
}

interface LspFramerConstructor {
  new (): LspFramerInstance;
  (): LspFramerInstance;
  prototype: LspFramerInstance;
  encode(message: object): string;
}

const LspFramer = function(this: LspFramerInstance): void {
  this._buffer = '';
  this._contentLength = -1;
  this._onMessage = null;
} as unknown as LspFramerConstructor;

LspFramer.prototype.onMessage = function(this: LspFramerInstance, callback: (msg: object) => void): void {
  this._onMessage = callback;
};

LspFramer.prototype.feed = function(this: LspFramerInstance, data: string): void {
  this._buffer += data;
  this._parseMessages();
};

LspFramer.prototype._parseMessages = function(this: LspFramerInstance): void {
  while (true) {
    if (this._contentLength === -1) {
      const headerEnd = this._buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) return;

      const headers = this._buffer.substring(0, headerEnd);
      const match = headers.match(/Content-Length:\s*(\d+)/i);
      if (!match) {
        consoleAPI.log('[LSP] Malformed header, skipping:', headers.substring(0, 100));
        this._buffer = this._buffer.substring(headerEnd + 4);
        continue;
      }

      this._contentLength = parseInt(match[1], 10);
      this._buffer = this._buffer.substring(headerEnd + 4);
    }

    // LSP Content-Length is in bytes, not characters
    // Find how many characters correspond to contentLength bytes
    let charCount = 0;
    let byteCount = 0;
    while (charCount < this._buffer.length && byteCount < this._contentLength) {
      const codePoint = this._buffer.codePointAt(charCount)!;
      // Calculate UTF-8 byte length for this code point
      if (codePoint <= 0x7F) {
        byteCount += 1;
      } else if (codePoint <= 0x7FF) {
        byteCount += 2;
      } else if (codePoint <= 0xFFFF) {
        byteCount += 3;
      } else {
        byteCount += 4;
        charCount++; // Skip surrogate pair's second half
      }
      charCount++;
    }

    // Not enough bytes yet
    if (byteCount < this._contentLength) return;

    const body = this._buffer.substring(0, charCount);
    this._buffer = this._buffer.substring(charCount);
    this._contentLength = -1;

    try {
      const message = JSON.parse(body);
      if (this._onMessage) {
        this._onMessage(message);
      }
    } catch (e: any) {
      consoleAPI.log('[LSP] Invalid JSON:', e.message, body.substring(0, 100));
    }
  }
};

// Static method
LspFramer.encode = function(message: object): string {
  const body = JSON.stringify(message);
  // LSP requires Content-Length in bytes (UTF-8), not string length
  // TextEncoder.encode() returns UTF-8 bytes
  const encoder = new TextEncoder();
  const byteLength = encoder.encode(body).length;
  return 'Content-Length: ' + byteLength + '\r\n\r\n' + body;
};

interface LspClientOptions {
  name?: string;
  cmd: string[];
  rootDir?: string;
  capabilities?: object;
  settings?: object;
  onAttach?: (client: LspClientInstance, bufnr: number) => void;
  onExit?: (code: number, signal: string) => void;
  /** Default request timeout in milliseconds (default: 30000) */
  requestTimeout?: number;
}

interface PendingRequest {
  resolve: (result: any) => void;
  reject: (error: Error) => void;
  method: string;
  /** Timer ID for request timeout */
  timeoutId?: any;
}

// LspClient using constructor function pattern (ES5 compatible)
interface LspClientInstance {
  name: string;
  cmd: string[];
  rootDir: string | null;
  capabilities: object;
  settings: object;
  onAttach: ((client: LspClientInstance, bufnr: number) => void) | null;
  onExitCallback: ((code: number, signal: string) => void) | null;
  /** Request timeout in milliseconds */
  requestTimeout: number;
  _id: number;
  _requestId: number;
  _pendingRequests: Record<number, PendingRequest>;
  _handlers: Record<string, (params: object) => void>;
  _framer: LspFramerInstance;
  _process: any;
  _initialized: boolean;
  _stopping: boolean;
  _serverCapabilities: object;
  _attachedBuffers: Record<number, boolean>;
  id: number;
  serverCapabilities: object;
  initialized: boolean;
  stopping: boolean;
  attachedBuffers: number[];
  start(): Promise<LspClientInstance>;
  request(method: string, params?: object, options?: { timeout?: number }): Promise<any>;
  notify(method: string, params?: object): void;
  on(method: string, callback: (params: object) => void): LspClientInstance;
  stop(): void;
  supports(capability: string): boolean;
  attachBuffer(bufnr: number): void;
  detachBuffer(bufnr: number): void;
  hasBuffer(bufnr: number): boolean;
  _buildCapabilities(): object;
  _deepMerge(target: any, source: any): object;
  _handleExit(code: number, signal: string): void;
  _handleMessage(msg: any): void;
  _handleResponse(msg: any): void;
  _handleServerRequest(msg: any): void;
  _handleNotification(msg: any): void;
  _sendResponse(id: number, result: any): void;
  _sendError(id: number, code: number, message: string): void;
  _send(msg: object): void;
}

interface LspClientConstructor {
  new (opts: LspClientOptions): LspClientInstance;
  (opts: LspClientOptions): LspClientInstance;
  prototype: LspClientInstance;
  _nextId: number;
  _clients: LspClientInstance[];
}

const LspClient = function(this: LspClientInstance, opts: LspClientOptions): void {
  this.name = opts.name || 'lsp';
  this.cmd = opts.cmd;
  this.rootDir = opts.rootDir || null;
  this.capabilities = opts.capabilities || {};
  this.settings = opts.settings || {};
  this.onAttach = opts.onAttach || null;
  this.onExitCallback = opts.onExit || null;
  // Default timeout: 30 seconds
  this.requestTimeout = opts.requestTimeout !== undefined ? opts.requestTimeout : 30000;
  this._id = LspClient._nextId++;
  this._requestId = 1;
  this._pendingRequests = {};
  this._handlers = {};
  this._framer = new (LspFramer as any)();
  this._process = null;
  this._initialized = false;
  this._stopping = false;
  this._serverCapabilities = {};
  this._attachedBuffers = {};
} as unknown as LspClientConstructor;

// Static properties
LspClient._nextId = 1;
LspClient._clients = [];

// Getters using Object.defineProperty
Object.defineProperty(LspClient.prototype, 'id', {
  get: function(this: LspClientInstance): number { return this._id; },
  enumerable: true,
  configurable: true
});

Object.defineProperty(LspClient.prototype, 'serverCapabilities', {
  get: function(this: LspClientInstance): object { return this._serverCapabilities; },
  enumerable: true,
  configurable: true
});

Object.defineProperty(LspClient.prototype, 'initialized', {
  get: function(this: LspClientInstance): boolean { return this._initialized; },
  enumerable: true,
  configurable: true
});

Object.defineProperty(LspClient.prototype, 'stopping', {
  get: function(this: LspClientInstance): boolean { return this._stopping; },
  enumerable: true,
  configurable: true
});

Object.defineProperty(LspClient.prototype, 'attachedBuffers', {
  get: function(this: LspClientInstance): number[] {
    return Object.keys(this._attachedBuffers).map(k => parseInt(k, 10));
  },
  enumerable: true,
  configurable: true
});

LspClient.prototype.start = function(this: LspClientInstance): Promise<LspClientInstance> {
  const self = this;
  if (this._stopping) {
    return Promise.reject(new Error('LSP client is stopping'));
  }
  if (this._process) {
    return Promise.reject(new Error('LSP client already started'));
  }

  const cmd = this.cmd[0];
  const args = this.cmd.slice(1);
  const spawnOpts: any = {};
  if (this.rootDir) {
    spawnOpts.cwd = this.rootDir;
  }

  this._process = (globalThis as any).process.spawn(cmd, args, spawnOpts);
  this._process.onStdout(function(data: string) { self._framer.feed(data); });
  this._process.onStderr(function(data: string) { consoleAPI.log('[LSP:' + self.name + '] stderr:', data); });
  this._process.onExit(function(code: number, signal: string) { self._handleExit(code, signal); });

  this._framer.onMessage(function(msg: object) { self._handleMessage(msg); });

  return this.request('initialize', {
    processId: null,
    rootUri: this.rootDir ? 'file://' + this.rootDir : null,
    rootPath: this.rootDir || null,
    capabilities: this._buildCapabilities(),
    initializationOptions: this.settings,
    trace: 'off',
  }).then(function(initResult: any) {
    self._serverCapabilities = initResult.capabilities || {};
    self.notify('initialized', {});
    self._initialized = true;
    return self;
  });
};

LspClient.prototype._buildCapabilities = function(this: LspClientInstance): object {
  const defaults = {
    textDocument: {
      synchronization: { dynamicRegistration: false, willSave: false, willSaveWaitUntil: false, didSave: true },
      completion: { dynamicRegistration: false, completionItem: { snippetSupport: false, documentationFormat: ['plaintext'] } },
      hover: { dynamicRegistration: false, contentFormat: ['plaintext'] },
      definition: { dynamicRegistration: false },
      references: { dynamicRegistration: false },
      publishDiagnostics: { relatedInformation: true },
    },
    workspace: { workspaceFolders: false, configuration: false },
  };
  return this._deepMerge(defaults, this.capabilities);
};

LspClient.prototype._deepMerge = function(this: LspClientInstance, target: any, source: any): object {
  const result: any = {};
  for (const key in target) {
    if (Object.prototype.hasOwnProperty.call(target, key)) {
      result[key] = target[key];
    }
  }
  for (const key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
        result[key] = this._deepMerge(result[key] || {}, source[key]);
      } else {
        result[key] = source[key];
      }
    }
  }
  return result;
};

LspClient.prototype._handleExit = function(this: LspClientInstance, code: number, signal: string): void {
  consoleAPI.log('[LSP:' + this.name + '] exited: code=' + code + ' signal=' + signal);

  // Clear all pending request timeouts and reject them
  for (const id in this._pendingRequests) {
    if (Object.prototype.hasOwnProperty.call(this._pendingRequests, id)) {
      const pending = this._pendingRequests[id];
      if (pending.timeoutId) {
        (globalThis as any).clearTimeout(pending.timeoutId);
      }
      pending.reject(new Error('LSP server exited'));
    }
  }
  this._pendingRequests = {};
  this._process = null;
  this._initialized = false;
  this._stopping = false;  // Reset so client could potentially be restarted

  const idx = LspClient._clients.indexOf(this);
  if (idx >= 0) {
    LspClient._clients.splice(idx, 1);
  }

  if (this.onExitCallback) {
    try {
      this.onExitCallback(code, signal);
    } catch (e) {
      consoleAPI.log('[LSP:' + this.name + '] onExit callback error:', e);
    }
  }
};

LspClient.prototype._handleMessage = function(this: LspClientInstance, msg: any): void {
  if ('id' in msg) {
    if ('method' in msg) {
      this._handleServerRequest(msg);
    } else {
      this._handleResponse(msg);
    }
  } else if ('method' in msg) {
    this._handleNotification(msg);
  }
};

LspClient.prototype._handleResponse = function(this: LspClientInstance, msg: any): void {
  const pending = this._pendingRequests[msg.id];
  if (!pending) {
    consoleAPI.log('[LSP:' + this.name + '] Unknown response id:', msg.id);
    return;
  }

  // Clear timeout if set
  if (pending.timeoutId) {
    (globalThis as any).clearTimeout(pending.timeoutId);
  }

  delete this._pendingRequests[msg.id];

  if (msg.error) {
    pending.reject(new Error(msg.error.message || 'LSP error ' + msg.error.code));
  } else {
    pending.resolve(msg.result);
  }
};

LspClient.prototype._handleServerRequest = function(this: LspClientInstance, msg: any): void {
  if (msg.method === 'window/showMessage') {
    const params = msg.params || {};
    const types = ['', 'Error', 'Warning', 'Info', 'Log'];
    consoleAPI.log('[LSP:' + this.name + '] ' + (types[params.type] || '') + ': ' + params.message);
    this._sendResponse(msg.id, null);
  } else if (msg.method === 'workspace/configuration') {
    this._sendResponse(msg.id, []);
  } else if (msg.method === 'client/registerCapability') {
    this._sendResponse(msg.id, null);
  } else {
    this._sendError(msg.id, -32601, 'Method not found: ' + msg.method);
  }
};

LspClient.prototype._handleNotification = function(this: LspClientInstance, msg: any): void {
  const handler = this._handlers[msg.method];
  if (handler) {
    try {
      handler(msg.params || {});
    } catch (e) {
      consoleAPI.log('[LSP:' + this.name + '] Handler error for ' + msg.method + ':', e);
    }
  } else if (msg.method === 'textDocument/publishDiagnostics') {
    const params = msg.params || {};
    const diags = params.diagnostics || [];
    if (diags.length > 0) {
      consoleAPI.log('[LSP:' + this.name + '] ' + diags.length + ' diagnostics for ' + params.uri);
    }
  } else if (msg.method === 'window/logMessage' || msg.method === 'window/showMessage') {
    const params = msg.params || {};
    consoleAPI.log('[LSP:' + this.name + '] ' + params.message);
  }
};

LspClient.prototype._sendResponse = function(this: LspClientInstance, id: number, result: any): void {
  this._send({ jsonrpc: '2.0', id, result });
};

LspClient.prototype._sendError = function(this: LspClientInstance, id: number, code: number, message: string): void {
  this._send({ jsonrpc: '2.0', id, error: { code, message } });
};

LspClient.prototype._send = function(this: LspClientInstance, msg: object): void {
  if (!this._process) {
    if (this._stopping) {
      throw new Error('LSP client is stopping');
    }
    throw new Error('LSP client not started');
  }
  const encoded = LspFramer.encode(msg);
  this._process.stdin.write(encoded);
};

LspClient.prototype.request = function(this: LspClientInstance, method: string, params?: object, options?: { timeout?: number }): Promise<any> {
  const self = this;
  const id = this._requestId++;
  const msg = { jsonrpc: '2.0', id, method, params: params || {} };
  const timeout = (options && options.timeout !== undefined) ? options.timeout : self.requestTimeout;

  return new Promise(function(resolve, reject) {
    let timeoutId: any = null;

    // Set up timeout if enabled (timeout > 0)
    if (timeout > 0) {
      timeoutId = (globalThis as any).setTimeout(function() {
        const pending = self._pendingRequests[id];
        if (pending) {
          delete self._pendingRequests[id];
          reject(new Error('LSP request timeout: ' + method + ' (waited ' + timeout + 'ms)'));
        }
      }, timeout);
    }

    self._pendingRequests[id] = { resolve, reject, method, timeoutId };

    try {
      self._send(msg);
    } catch (e) {
      if (timeoutId) {
        (globalThis as any).clearTimeout(timeoutId);
      }
      delete self._pendingRequests[id];
      reject(e);
    }
  });
};

LspClient.prototype.notify = function(this: LspClientInstance, method: string, params?: object): void {
  this._send({ jsonrpc: '2.0', method, params: params || {} });
};

LspClient.prototype.on = function(this: LspClientInstance, method: string, callback: (params: object) => void): LspClientInstance {
  this._handlers[method] = callback;
  return this;
};

LspClient.prototype.stop = function(this: LspClientInstance): void {
  const self = this;

  // Guard against multiple stop() calls
  if (this._stopping) {
    return;
  }
  this._stopping = true;

  // Clear all pending request timeouts to avoid leaks
  for (const id in this._pendingRequests) {
    const pending = this._pendingRequests[id];
    if (pending && pending.timeoutId) {
      (globalThis as any).clearTimeout(pending.timeoutId);
    }
    if (pending) {
      pending.reject(new Error('LSP client stopped'));
    }
  }
  this._pendingRequests = {};

  if (this._process) {
    this.request('shutdown', {}, { timeout: 5000 }).then(function() {
      self.notify('exit', {});
      (globalThis as any).setTimeout(function() {
        if (self._process) {
          self._process.kill('SIGTERM');
        }
      }, 1000);
    }).catch(function() {
      if (self._process) {
        self._process.kill('SIGTERM');
      }
    });
  }
};

LspClient.prototype.supports = function(this: LspClientInstance, capability: string): boolean {
  const parts = capability.split('.');
  let obj: any = this._serverCapabilities;
  for (const part of parts) {
    if (obj && typeof obj === 'object' && part in obj) {
      obj = obj[part];
    } else {
      return false;
    }
  }
  return !!obj;
};

LspClient.prototype.attachBuffer = function(this: LspClientInstance, bufnr: number): void {
  if (this._attachedBuffers[bufnr]) return;
  this._attachedBuffers[bufnr] = true;
  if (this.onAttach) {
    try {
      this.onAttach(this, bufnr);
    } catch (e) {
      consoleAPI.log('[LSP:' + this.name + '] onAttach error:', e);
    }
  }
};

LspClient.prototype.detachBuffer = function(this: LspClientInstance, bufnr: number): void {
  delete this._attachedBuffers[bufnr];
};

LspClient.prototype.hasBuffer = function(this: LspClientInstance, bufnr: number): boolean {
  return !!this._attachedBuffers[bufnr];
};

// Helper to construct proper file:// URI from buffer name
function bufferToFileUri(bufnr: number): string {
  let path = vim.api.bufGetName(bufnr);
  // If path is relative, prepend cwd
  if (path && !path.startsWith('/')) {
    const cwd = vimFn.getCwd();
    if (cwd) {
      path = cwd + '/' + path;
    }
  }
  return 'file://' + path;
}

// vim.lsp API
const vimLsp = {
  start(opts: LspClientOptions): Promise<LspClientInstance> {
    consoleAPI.log('[LSP] vim.lsp.start called with:', opts.name, opts.cmd);
    if (!opts || !opts.cmd || !Array.isArray(opts.cmd) || opts.cmd.length === 0) {
      return Promise.reject(new Error('vim.lsp.start requires opts.cmd array'));
    }

    const client = new (LspClient as any)(opts) as LspClientInstance;
    LspClient._clients.push(client);
    consoleAPI.log('[LSP] Client created, starting...');

    // Attach current buffer IMMEDIATELY so hover() can find it before async start completes
    // This is important because FileType autocmd fires synchronously and user may
    // press K before the LSP server finishes initializing
    const currentBuf = vim.api.getCurrentBuf();
    client.attachBuffer(currentBuf);
    consoleAPI.log('[LSP] Buffer', currentBuf, 'attached to client', client.name);

    return client.start().then(function(c) {
      consoleAPI.log('[LSP] Client', c.name, 'initialized, attached buffers:', Object.keys(c._attachedBuffers));

      // Send didOpen for all attached buffers now that server is ready
      for (const bufnrStr in c._attachedBuffers) {
        const bufnr = parseInt(bufnrStr, 10);
        const uri = bufferToFileUri(bufnr);
        const lines = vim.api.bufGetLines(bufnr, 0, -1, false);
        const text = lines.join('\n');
        // Detect language from file extension
        const bufName = vim.api.bufGetName(bufnr);
        let languageId = 'plaintext';
        if (bufName.endsWith('.ts') || bufName.endsWith('.tsx')) {
          languageId = 'typescript';
        } else if (bufName.endsWith('.js') || bufName.endsWith('.jsx')) {
          languageId = 'javascript';
        } else if (bufName.endsWith('.json')) {
          languageId = 'json';
        }

        consoleAPI.log('[LSP:' + c.name + '] Sending didOpen for buffer', bufnr, 'uri:', uri);
        c.notify('textDocument/didOpen', {
          textDocument: {
            uri: uri,
            languageId: languageId,
            version: 1,
            text: text
          }
        });
      }

      return c;
    }).catch(function(e) {
      // Kill the process if it was spawned but initialization failed
      if (client._process) {
        try {
          client._process.kill('SIGTERM');
        } catch (killErr) {
          // Ignore kill errors
        }
        client._process = null;
      }
      const idx = LspClient._clients.indexOf(client);
      if (idx >= 0) {
        LspClient._clients.splice(idx, 1);
      }
      throw e;
    });
  },

  getClients(filter?: { bufnr?: number; name?: string }): LspClientInstance[] {
    let clients = LspClient._clients.slice();

    if (filter) {
      if (typeof filter.bufnr === 'number') {
        const bufnr = filter.bufnr;
        clients = clients.filter(function(c) { return c.hasBuffer(bufnr); });
      }
      if (typeof filter.name === 'string') {
        const name = filter.name;
        clients = clients.filter(function(c) { return c.name === name; });
      }
    }

    return clients;
  },

  stopClient(clientOrId: number | LspClientInstance, force?: boolean): void {
    let client: LspClientInstance | undefined;
    if (typeof clientOrId === 'number') {
      for (const c of LspClient._clients) {
        if (c.id === clientOrId) {
          client = c;
          break;
        }
      }
    } else {
      client = clientOrId;
    }

    if (client) {
      if (force) {
        // Force kill: clean up immediately without graceful shutdown
        client._stopping = true;

        // Clear all pending request timeouts
        for (const id in client._pendingRequests) {
          const pending = client._pendingRequests[id];
          if (pending && pending.timeoutId) {
            (globalThis as any).clearTimeout(pending.timeoutId);
          }
          if (pending) {
            pending.reject(new Error('LSP client force killed'));
          }
        }
        client._pendingRequests = {};

        // Kill process
        if (client._process) {
          try {
            client._process.kill('SIGKILL');
          } catch (e) {
            // Ignore kill errors
          }
          client._process = null;
        }

        // Remove from clients list
        const idx = LspClient._clients.indexOf(client);
        if (idx >= 0) {
          LspClient._clients.splice(idx, 1);
        }

        client._initialized = false;
      } else {
        client.stop();
      }
    }
  },

  getClientById(id: number): LspClientInstance | undefined {
    for (const c of LspClient._clients) {
      if (c.id === id) return c;
    }
    return undefined;
  },

  // ========== Buffer-level notification helpers ==========

  /**
   * Send textDocument/didOpen notification to all clients attached to buffer
   */
  bufDidOpen(bufnr: number, uri: string, languageId: string, text: string): void {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    for (const client of clients) {
      client.notify('textDocument/didOpen', {
        textDocument: {
          uri: uri,
          languageId: languageId,
          version: 1,
          text: text
        }
      });
    }
  },

  /**
   * Send textDocument/didChange notification to all clients attached to buffer
   */
  bufDidChange(bufnr: number, uri: string, version: number, text: string): void {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    for (const client of clients) {
      client.notify('textDocument/didChange', {
        textDocument: { uri: uri, version: version },
        contentChanges: [{ text: text }]
      });
    }
  },

  /**
   * Send textDocument/didClose notification to all clients attached to buffer
   */
  bufDidClose(bufnr: number, uri: string): void {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    for (const client of clients) {
      client.notify('textDocument/didClose', {
        textDocument: { uri: uri }
      });
    }
  },

  /**
   * Send textDocument/didSave notification to all clients attached to buffer
   */
  bufDidSave(bufnr: number, uri: string, text?: string): void {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    for (const client of clients) {
      const params: any = { textDocument: { uri: uri } };
      if (text !== undefined) {
        params.text = text;
      }
      client.notify('textDocument/didSave', params);
    }
  },

  // ========== Buffer-level request helpers ==========

  /**
   * Request hover information at a position
   */
  bufHover(bufnr: number, uri: string, line: number, character: number): Promise<any> {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    if (clients.length === 0) {
      return Promise.resolve(null);
    }
    return clients[0].request('textDocument/hover', {
      textDocument: { uri: uri },
      position: { line: line, character: character }
    });
  },

  /**
   * Request definition location at a position
   */
  bufDefinition(bufnr: number, uri: string, line: number, character: number): Promise<any> {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    if (clients.length === 0) {
      return Promise.resolve(null);
    }
    return clients[0].request('textDocument/definition', {
      textDocument: { uri: uri },
      position: { line: line, character: character }
    });
  },

  /**
   * Request references at a position
   */
  bufReferences(bufnr: number, uri: string, line: number, character: number, includeDeclaration?: boolean): Promise<any> {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    if (clients.length === 0) {
      return Promise.resolve(null);
    }
    return clients[0].request('textDocument/references', {
      textDocument: { uri: uri },
      position: { line: line, character: character },
      context: { includeDeclaration: includeDeclaration !== false }
    });
  },

  LspClient,
  LspFramer,

  /**
   * Find first client attached to buffer that supports the given capability
   * @internal
   */
  _findClientWithCapability(bufnr: number, capability: string): LspClientInstance | null {
    const clients = vimLsp.getClients({ bufnr: bufnr });
    for (const client of clients) {
      if (client.supports(capability)) {
        return client;
      }
    }
    // Fall back to first client if none explicitly support capability
    // (server may not have advertised all capabilities)
    return clients.length > 0 ? clients[0] : null;
  },

  // ========== vim.lsp.util - Floating window utilities (Neovim compatible) ==========
  util: {
    /**
     * Track the current preview floating window (for auto-close on cursor move)
     * @internal
     */
    _previewWinId: null as number | null,
    _previewBufId: null as number | null,
    _closeAutocommandIds: null as number[] | null,

    /**
     * Computes floating window config with smart position clamping
     * @param width - Desired window width
     * @param height - Desired window height
     * @param opts - Options for positioning
     * @returns Configuration object for vim.api.openWin
     */
    makeFloatingPopupOptions(width: number, height: number, opts?: {
      relative?: 'cursor' | 'editor' | 'mouse';
      anchorBias?: 'auto' | 'above' | 'below';
      offsetX?: number;
      offsetY?: number;
      border?: string;
      focusable?: boolean;
      zindex?: number;
    }): object {
      opts = opts || {};
      const relative = opts.relative || 'cursor';
      const anchorBias = opts.anchorBias || 'auto';
      const offsetX = opts.offsetX || 0;
      const offsetY = opts.offsetY || 0;

      // Get terminal dimensions (winGetHeight/Width(0) now returns terminal size directly)
      const winHeight = vim.api.winGetHeight(0);
      const winWidth = vim.api.winGetWidth(0);

      // Get cursor position in window (1-indexed row, 0-indexed col)
      const cursor = vim.api.winGetCursor(0);
      const cursorRow = cursor[0]; // 1-indexed
      const cursorCol = cursor[1]; // 0-indexed

      // Calculate lines above and below cursor
      const linesAbove = cursorRow - 1; // Rows above cursor (0-indexed)
      const linesBelow = winHeight - cursorRow;

      // Account for border height (2 = top + bottom border)
      const borderHeight = opts.border && opts.border !== 'none' ? 2 : 0;
      const borderWidth = opts.border && opts.border !== 'none' ? 2 : 0;

      // Determine anchor position (above or below cursor)
      let anchorBelow: boolean;
      if (anchorBias === 'below') {
        // Explicit below bias: place below if fits, otherwise place below anyway (will clamp)
        anchorBelow = true;
      } else if (anchorBias === 'above') {
        // Explicit above bias: place above if fits, otherwise place above anyway (will clamp)
        anchorBelow = false;
      } else {
        // 'auto' - prefer below, flip above only if doesn't fit below
        if (height + borderHeight <= linesBelow) {
          // Fits below, place below (preferred)
          anchorBelow = true;
        } else if (height + borderHeight <= linesAbove) {
          // Doesn't fit below but fits above, flip to above
          anchorBelow = false;
        } else {
          // Doesn't fit either side, pick side with more space
          anchorBelow = linesBelow >= linesAbove;
        }
      }

      // Clamp height to available space
      let clampedHeight: number;
      let row: number;
      let anchor: string;

      if (anchorBelow) {
        // Position below cursor with 1-row gap
        anchor = 'NW';
        clampedHeight = Math.max(1, Math.min(height, linesBelow - borderHeight - 1));
        row = 2 + offsetY; // 2 rows below cursor (1 row gap)
      } else {
        // Position above cursor with 1-row gap
        anchor = 'SW';
        clampedHeight = Math.max(1, Math.min(height, linesAbove - borderHeight - 1));
        row = -1 + offsetY; // 1 row above cursor (SW anchor places bottom edge here)
      }

      // Handle horizontal positioning - left-aligned, 1 col after cursor
      let col = 1 + offsetX; // Start 1 column after cursor
      if (cursorCol + 1 + width + borderWidth + offsetX > winWidth) {
        // Not enough space on the right, anchor to the left of cursor instead
        anchor = anchor.charAt(0) + 'E'; // Change W to E
        col = 0 + offsetX; // At cursor position (right edge of popup)
      } else {
        anchor = anchor.charAt(0) + 'W';
      }

      // Clamp width to available space
      const clampedWidth = Math.max(1, Math.min(width, winWidth - borderWidth));

      return {
        relative: relative,
        anchor: anchor,
        row: row,
        col: col,
        width: clampedWidth,
        height: clampedHeight,
        style: 'minimal',
        border: opts.border || 'none',
        focusable: opts.focusable !== undefined ? opts.focusable : false,
        zindex: opts.zindex || 50
      };
    },

    /**
     * Opens a floating preview window with smart positioning and auto-close
     * @param contents - Array of lines to display
     * @param syntax - Syntax type ('markdown', 'text', etc.)
     * @param opts - Options for the floating window
     * @returns [bufnr, winid] tuple
     */
    openFloatingPreview(contents: string[], syntax?: string, opts?: {
      height?: number;
      width?: number;
      maxWidth?: number;
      maxHeight?: number;
      wrap?: boolean;
      border?: string;
      focusable?: boolean;
      focusId?: string;
      closeEvents?: string[];
      relative?: 'cursor' | 'editor' | 'mouse';
      anchorBias?: 'auto' | 'above' | 'below';
      offsetX?: number;
      offsetY?: number;
      zindex?: number;
      padding?: number;
    }): [number, number] {
      opts = opts || {};

      // Close existing preview window if any
      vimLsp.util.closePreviewWindow();

      // Strip markdown code fences if present (handles plugins that pass raw markdown)
      // Check if first line is a code fence like ```typescript or ```
      if (contents.length > 0 && /^\s*```\w*\s*$/.test(contents[0])) {
        // Extract language from fence for syntax highlighting
        // Always use the fence language since we're stripping the markdown wrapper
        const langMatch = contents[0].match(/```(\w+)/);
        if (langMatch) {
          syntax = langMatch[1];
        }
        // Remove opening fence
        contents = contents.slice(1);
        // Remove closing fence if present
        if (contents.length > 0 && /^\s*```\s*$/.test(contents[contents.length - 1])) {
          contents = contents.slice(0, -1);
        }
        // Remove any leading/trailing empty lines
        while (contents.length > 0 && contents[0].trim() === '') {
          contents = contents.slice(1);
        }
        while (contents.length > 0 && contents[contents.length - 1].trim() === '') {
          contents = contents.slice(0, -1);
        }
      }

      // Compute dimensions
      const maxWidth = opts.maxWidth || 80;
      const maxHeight = opts.maxHeight || 24;

      // Calculate content width (longest line)
      let contentWidth = 1;
      for (let i = 0; i < contents.length; i++) {
        if (contents[i].length > contentWidth) {
          contentWidth = contents[i].length;
        }
      }

      // Add padding if specified (add spaces to each line)
      const padding = opts.padding || 0;
      if (padding > 0) {
        const paddedContents: string[] = [];
        const padStr = ' '.repeat(padding);
        for (let i = 0; i < contents.length; i++) {
          paddedContents.push(padStr + contents[i] + padStr);
        }
        contents = paddedContents;
        contentWidth += padding * 2;
      }

      const width = opts.width || Math.min(maxWidth, contentWidth);
      const height = opts.height || Math.min(maxHeight, contents.length);

      // Create buffer
      const bufnr = vim.api.createBuf(false, true);
      vim.api.bufSetLines(bufnr, 0, -1, false, contents);

      // Set syntax/filetype for tree-sitter highlighting
      if (syntax) {
        vim.api.bufSetOption(bufnr, 'filetype', syntax);
      }

      // Get floating window options with smart positioning
      const floatOpts = vimLsp.util.makeFloatingPopupOptions(width, height, {
        relative: opts.relative,
        anchorBias: opts.anchorBias,
        offsetX: opts.offsetX,
        offsetY: opts.offsetY,
        border: opts.border,
        focusable: opts.focusable,
        zindex: opts.zindex
      });

      // Open the window
      const winid = vim.api.openWin(bufnr, false, floatOpts);

      // Set conceal options for markdown (hide ``` code fence markers like Neovim)
      if (syntax === 'markdown') {
        vim.api.winSetOption(winid, 'conceallevel', 2);
        vim.api.winSetOption(winid, 'concealcursor', 'n');
      }

      // Track for auto-close
      vimLsp.util._previewWinId = winid;
      vimLsp.util._previewBufId = bufnr;

      // Set up auto-close on cursor move
      const closeEvents = opts.closeEvents || ['CursorMoved', 'CursorMovedI', 'InsertCharPre'];
      if (closeEvents.length > 0) {
        const result = vim.autocmd.create(closeEvents, {
          once: true,
          callback: function() {
            vimLsp.util.closePreviewWindow();
          }
        });
        // Normalize to array
        vimLsp.util._closeAutocommandIds = Array.isArray(result) ? result : [result];
      }

      return [bufnr, winid];
    },

    /**
     * Closes the current preview floating window
     */
    closePreviewWindow(): void {
      // Remove autocommands if set
      if (vimLsp.util._closeAutocommandIds !== null) {
        for (const id of vimLsp.util._closeAutocommandIds) {
          try {
            vim.autocmd.del(id);
          } catch (e) {
            // Ignore if already deleted
          }
        }
        vimLsp.util._closeAutocommandIds = null;
      }

      // Close window if valid
      if (vimLsp.util._previewWinId !== null) {
        try {
          if (vim.api.winIsValid(vimLsp.util._previewWinId)) {
            vim.api.winClose(vimLsp.util._previewWinId, true);
          }
        } catch (e) {
          // Ignore close errors
        }
        vimLsp.util._previewWinId = null;
      }

      // Delete buffer if valid
      if (vimLsp.util._previewBufId !== null) {
        try {
          if (vim.api.bufIsValid(vimLsp.util._previewBufId)) {
            vim.api.bufDelete(vimLsp.util._previewBufId, { force: true });
          }
        } catch (e) {
          // Ignore delete errors
        }
        vimLsp.util._previewBufId = null;
      }
    }
  },

  // ========== vim.lsp.handlers - Customizable response handlers ==========
  // Plugins can override these to customize how LSP results are displayed
  // Example: vim.lsp.handlers['textDocument/hover'] = function(result, ctx) { ... }
  handlers: {
    /**
     * Default handler for textDocument/hover
     * Displays hover content in a floating window with smart positioning
     */
    'textDocument/hover': function(result: any, ctx: { bufnr: number; client: LspClientInstance }) {
      if (!result || !result.contents) {
        return;
      }

      // Extract text from hover contents
      let text = '';
      const contents = result.contents;

      if (typeof contents === 'string') {
        text = contents;
      } else if (contents.value) {
        // MarkupContent: { kind: 'markdown'|'plaintext', value: string }
        text = contents.value;
      } else if (Array.isArray(contents)) {
        // MarkedString[]
        text = contents.map(function(c: any) {
          return typeof c === 'string' ? c : (c.value || '');
        }).join('\n');
      }

      if (!text) {
        return;
      }

      // Extract language from code fence if present (e.g., ```typescript)
      const langMatch = text.match(/```(\w+)/);
      const codeLang = langMatch ? langMatch[1] : null;

      // Strip markdown code fences completely
      // Remove all code fences (```lang and ```) along with surrounding newlines
      text = text
        .replace(/^\s*```\w*\s*\n?/gm, '')  // Opening fences: ```typescript, ```ts, ```
        .replace(/\n?\s*```\s*$/gm, '')      // Closing fences
        .trim();

      // Split into lines
      let lines = text.split('\n');

      // Filter out empty/whitespace-only lines at start and end
      while (lines.length > 0 && lines[0].trim() === '') {
        lines.shift();
      }
      while (lines.length > 0 && lines[lines.length - 1].trim() === '') {
        lines.pop();
      }

      // Check if we have any content left
      if (lines.length === 0) {
        return;
      }

      // Use detected language for syntax highlighting if available
      // Since we stripped the code fences, content is no longer markdown
      const syntax = codeLang || 'text';

      // Use the utility function for smart positioning and auto-close
      vimLsp.util.openFloatingPreview(lines, syntax, {
        maxWidth: 80,
        maxHeight: 24,
        border: 'rounded',
        focusable: false,
        closeEvents: ['CursorMoved', 'CursorMovedI', 'InsertCharPre', 'BufLeave'],
        anchorBias: 'auto',  // Prefer below, flip above if no room
        zindex: 100,
        padding: 1  // 1 space padding between border and content
      });
    },

    /**
     * Default handler for textDocument/definition
     * Jumps to the definition location
     */
    'textDocument/definition': function(result: any, ctx: { bufnr: number; client: LspClientInstance }) {
      if (!result) return;

      // Handle array of locations or single location
      const locations = Array.isArray(result) ? result : [result];
      if (locations.length === 0) return;

      const loc = locations[0];
      const uri = loc.uri || (loc.targetUri);
      const range = loc.range || (loc.targetSelectionRange);

      if (!uri || !range) return;

      // Convert file:// URI to path
      const path = uri.replace('file://', '');
      const line = range.start.line + 1;  // LSP is 0-indexed, Vim is 1-indexed
      const col = range.start.character;

      // Open file and jump to position
      consoleAPI.log('[LSP] Jumping to', path, 'line', line, 'col', col);
      // TODO: Implement file open and cursor positioning
      // vim.cmd('edit ' + path);
      // vim.api.winSetCursor(0, [line, col]);
    },

    /**
     * Default handler for textDocument/references
     * Shows references in quickfix or floating window
     */
    'textDocument/references': function(result: any, ctx: { bufnr: number; client: LspClientInstance }) {
      if (!result || !Array.isArray(result) || result.length === 0) {
        consoleAPI.log('[LSP] No references found');
        return;
      }

      consoleAPI.log('[LSP] Found', result.length, 'references');
      // TODO: Display in quickfix list or floating window
    },

    /**
     * Default handler for textDocument/signatureHelp
     */
    'textDocument/signatureHelp': function(result: any, ctx: { bufnr: number; client: LspClientInstance }) {
      if (!result || !result.signatures || result.signatures.length === 0) {
        return;
      }

      const sig = result.signatures[result.activeSignature || 0];
      const label = sig.label;

      // Build signature content
      const lines = [label];
      if (sig.documentation) {
        const doc = typeof sig.documentation === 'string'
          ? sig.documentation
          : sig.documentation.value || '';
        if (doc) {
          lines.push('', doc);
        }
      }

      // Use the utility function for smart positioning and auto-close
      // Signature help content is also markdown/plaintext
      vimLsp.util.openFloatingPreview(lines, 'markdown', {
        maxWidth: 80,
        maxHeight: 10,
        border: 'rounded',
        focusable: false,
        closeEvents: ['CursorMoved', 'CursorMovedI', 'InsertCharPre'],
        anchorBias: 'above',  // Signature help typically appears above cursor
        zindex: 100,
        padding: 1  // 1 space padding between border and content
      });
    }
  } as { [key: string]: (result: any, ctx: { bufnr: number; client: LspClientInstance }) => void },

  // vim.lsp.buf - buffer-level LSP operations
  // Following Neovim's vim.lsp.buf pattern
  buf: {
    // Navigation methods

    /**
     * Request hover information at cursor position
     * Result is passed to vim.lsp.handlers['textDocument/hover'] for display
     */
    hover(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'hoverProvider');

      if (!client) {
        return Promise.resolve(null);
      }

      if (!client.initialized) {
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1; // 0-indexed
      const col = cursor[1];

      return client.request('textDocument/hover', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col }
      }).then(function(result: any) {
        // Call handler to display result
        const handler = vimLsp.handlers['textDocument/hover'];
        if (handler) {
          handler(result, { bufnr: bufnr, client: client });
        }
        return result;
      });
    },

    /**
     * Jump to definition of symbol under cursor
     * Result is passed to vim.lsp.handlers['textDocument/definition'] for navigation
     */
    definition(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'definitionProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      return client.request('textDocument/definition', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col }
      }).then(function(result: any) {
        const handler = vimLsp.handlers['textDocument/definition'];
        if (handler) {
          handler(result, { bufnr: bufnr, client: client });
        }
        return result;
      });
    },

    /**
     * Find all references to symbol under cursor
     * Result is passed to vim.lsp.handlers['textDocument/references'] for display
     */
    references(opts?: { includeDeclaration?: boolean }): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'referencesProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      const includeDeclaration = opts && opts.includeDeclaration !== undefined
        ? opts.includeDeclaration
        : true;

      return client.request('textDocument/references', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col },
        context: { includeDeclaration: includeDeclaration }
      }).then(function(result: any) {
        const handler = vimLsp.handlers['textDocument/references'];
        if (handler) {
          handler(result, { bufnr: bufnr, client: client });
        }
        return result;
      });
    },

    /**
     * Jump to implementation of symbol under cursor
     */
    implementation(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'implementationProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      return client.request('textDocument/implementation', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col }
      });
    },

    /**
     * Jump to type definition of symbol under cursor
     */
    typeDefinition(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'typeDefinitionProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      return client.request('textDocument/typeDefinition', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col }
      });
    },

    // Editing methods

    /**
     * Format current buffer using LSP
     */
    formatting(opts?: { tabSize?: number; insertSpaces?: boolean }): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'documentFormattingProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const tabSize = opts && opts.tabSize !== undefined ? opts.tabSize : 4;
      const insertSpaces = opts && opts.insertSpaces !== undefined ? opts.insertSpaces : true;

      return client.request('textDocument/formatting', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        options: {
          tabSize: tabSize,
          insertSpaces: insertSpaces
        }
      });
    },

    /**
     * Rename symbol under cursor
     */
    rename(newName?: string): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'renameProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      // If no name provided, this would typically show a prompt
      // For now, just return early if no name
      if (!newName) {
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      return client.request('textDocument/rename', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col },
        newName: newName
      });
    },

    /**
     * Request code actions at cursor position
     */
    codeAction(opts?: { only?: string[] }): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'codeActionProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      const context: any = { diagnostics: [] };
      if (opts && opts.only) {
        context.only = opts.only;
      }

      return client.request('textDocument/codeAction', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        range: {
          start: { line: line, character: col },
          end: { line: line, character: col }
        },
        context: context
      });
    },

    // Helper methods

    /**
     * Request signature help (parameter hints)
     * Result is passed to vim.lsp.handlers['textDocument/signatureHelp'] for display
     */
    signatureHelp(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'signatureHelpProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      const win = vim.api.getCurrentWin();
      const cursor = vim.api.winGetCursor(win);
      const line = cursor[0] - 1;
      const col = cursor[1];

      return client.request('textDocument/signatureHelp', {
        textDocument: { uri: bufferToFileUri(bufnr) },
        position: { line: line, character: col }
      }).then(function(result: any) {
        const handler = vimLsp.handlers['textDocument/signatureHelp'];
        if (handler) {
          handler(result, { bufnr: bufnr, client: client });
        }
        return result;
      });
    },

    /**
     * Request document symbols (outline)
     */
    documentSymbol(): Promise<any> {
      const bufnr = vim.api.getCurrentBuf();
      const client = vimLsp._findClientWithCapability(bufnr, 'documentSymbolProvider');
      if (!client) {
        consoleAPI.log('[LSP] No client attached to buffer', bufnr);
        return Promise.resolve(null);
      }
      if (!client.initialized) {
        consoleAPI.log('[LSP] Client', client.name, 'is still initializing...');
        return Promise.resolve(null);
      }

      return client.request('textDocument/documentSymbol', {
        textDocument: { uri: bufferToFileUri(bufnr) }
      });
    }
  }
};

vim.lsp = vimLsp;

// ============================================================================
// Vim Option Enums
// ============================================================================

(globalThis as any).LastStatus = Object.freeze({
  Never: 0,
  OnlyIfMultipleWindows: 1,
  Always: 2,
  Global: 3,
});

// Export for testing
export { vim, vimApi, vimFn, vimAutocmd, vimCmd, vimLsp, LspClient, LspFramer, _legacyMotion };
