(() => {
  'use strict';

  /**
   * Codex Smear Cursor
   * ------------------
   * JavaScript port of sphamba/smear-cursor.nvim tailored for Vimcraft.
   * This file follows the original plugin's architecture (config -> color -> math -> animation -> draw -> events)
   * while using the renderer APIs exposed by the Hermes runtime.
   *
   * Layered design:
   *   - Config: user-tunable physics + rendering options
   *   - Math helpers: vector and interpolation utilities
   *   - Physics: spring simulation that powers the smear
   *   - Renderer: converts the smear volume into terminal cells
   *   - Controller: cursor polling, animation loop, enable/disable hooks
   */

  const LAYER_NAME = 'codex_smear_cursor';
  const Z_INDEX = 260;
  const BASE_INTERVAL_MS = 17; // ~60fps baseline

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------
  const LOG_LEVELS = /** @type {const} */ ({
    error: 0,
    warn: 1,
    info: 2,
    debug: 3,
  });

  let logLevel = LOG_LEVELS.warn;

  const logger = {
    setLevel(name) {
      logLevel = LOG_LEVELS[name] ?? LOG_LEVELS.warn;
    },
    debug(...args) {
      if (logLevel >= LOG_LEVELS.debug) console.log('[codex-smear][debug]', ...args);
    },
    info(...args) {
      if (logLevel >= LOG_LEVELS.info) console.log('[codex-smear][info]', ...args);
    },
    warn(...args) {
      if (logLevel >= LOG_LEVELS.warn) console.log('[codex-smear][warn]', ...args);
    },
    error(...args) {
      if (logLevel >= LOG_LEVELS.error) console.log('[codex-smear][error]', ...args);
    },
  };

  // ---------------------------------------------------------------------------
  // Configuration (mirrors smear_cursor/config.lua where practical)
  // ---------------------------------------------------------------------------
  const DEFAULT_CONFIG = {
    enabled: true,
    cursor_color: 0xff8800,
    stiffness: 0.6,
    trailing_stiffness: 0.45,
    anticipation: 0.2,
    damping: 0.85,
    trailing_exponent: 3,
    distance_stop_animating: 0.1,
    max_length: 25,
    volume_reduction_exponent: 0.3,
    minimum_volume_factor: 0.7,
    time_interval: 17,
    never_draw_over_target: false,
    hide_target_hack: false,
    fast_stiffness: 0.9,
    fast_trailing_stiffness: 0.55,
    fast_movement_threshold: 6,
    fast_damping: 0.75,
    logging: 'warn',
  };

  const config = { ...DEFAULT_CONFIG };

  function mergeConfig(opts = {}) {
    const previousEnabled = config.enabled;
    for (const [key, value] of Object.entries(opts)) {
      if (key in config) {
        config[key] = value;
      }
    }
    logger.setLevel(config.logging);
    return previousEnabled;
  }

  logger.setLevel(config.logging);

  // ---------------------------------------------------------------------------
  // Math helpers (port of lua/smear_cursor/math.lua essentials)
  // ---------------------------------------------------------------------------
  const MathHelpers = {
    getCenter(corners) {
      return {
        row: (corners[0].row + corners[1].row + corners[2].row + corners[3].row) / 4,
        col: (corners[0].col + corners[1].col + corners[2].col + corners[3].col) / 4,
      };
    },

    normalize(vec) {
      const length = Math.sqrt(vec.row * vec.row + vec.col * vec.col);
      if (length === 0) return { row: 0, col: 0 };
      return { row: vec.row / length, col: vec.col / length };
    },

    distanceSquared(a, b) {
      const dx = a.col - b.col;
      const dy = a.row - b.row;
      return dx * dx + dy * dy;
    },

    distance(a, b) {
      return Math.sqrt(this.distanceSquared(a, b));
    },
  };

  // ---------------------------------------------------------------------------
  // Core animation state (matches smear_cursor.animation)
  // ---------------------------------------------------------------------------
  const state = {
    layerCreated: false,
    running: false,
    animating: false,
    frameHandle: null,
    lastTimestamp: 0,
    animationStart: 0,
    currentTimeout: 300,
    lastMovementDistance: 0,
    target: { row: 0, col: 0 },
    currentCorners: [
      { row: 0, col: 0 },
      { row: 0, col: 1 },
      { row: 1, col: 1 },
      { row: 1, col: 0 },
    ],
    targetCorners: [
      { row: 0, col: 0 },
      { row: 0, col: 1 },
      { row: 1, col: 1 },
      { row: 1, col: 0 },
    ],
    velocityCorners: [
      { row: 0, col: 0 },
      { row: 0, col: 0 },
      { row: 0, col: 0 },
      { row: 0, col: 0 },
    ],
    stiffnesses: [0, 0, 0, 0],
  };

  function cloneCorner(src) {
    return { row: src.row, col: src.col };
  }

  function setCorners(corners, row, col) {
    corners[0] = { row, col };
    corners[1] = { row, col: col + 1 };
    corners[2] = { row: row + 1, col: col + 1 };
    corners[3] = { row: row + 1, col };
  }

  function resetVelocity() {
    for (let i = 0; i < 4; i++) {
      state.velocityCorners[i].row = 0;
      state.velocityCorners[i].col = 0;
    }
  }

  function setInitialVelocity() {
    for (let i = 0; i < 4; i++) {
      state.velocityCorners[i].row =
        (state.currentCorners[i].row - state.targetCorners[i].row) * config.anticipation;
      state.velocityCorners[i].col =
        (state.currentCorners[i].col - state.targetCorners[i].col) * config.anticipation;
    }
  }

  function setStiffnesses() {
    const targetCenter = MathHelpers.getCenter(state.targetCorners);
    const distances = [];
    let minDistance = Infinity;
    let maxDistance = 0;

    for (let i = 0; i < 4; i++) {
      const corner = state.currentCorners[i];
      const dx = corner.col - targetCenter.col;
      const dy = corner.row - targetCenter.row;
      const distance = Math.sqrt(dx * dx + dy * dy);
      distances[i] = distance;
      minDistance = Math.min(minDistance, distance);
      maxDistance = Math.max(maxDistance, distance);
    }

    const isFast = state.lastMovementDistance > config.fast_movement_threshold;
    const head = isFast ? config.fast_stiffness : config.stiffness;
    const tail = isFast ? config.fast_trailing_stiffness : config.trailing_stiffness;

    if (maxDistance === minDistance) {
      for (let i = 0; i < 4; i++) {
        state.stiffnesses[i] = head;
      }
      return;
    }

    for (let i = 0; i < 4; i++) {
      const x = (distances[i] - minDistance) / (maxDistance - minDistance);
      const stiffness = head + (tail - head) * Math.pow(x, config.trailing_exponent);
      state.stiffnesses[i] = Math.min(1, stiffness);
    }
  }

  function getAnimationTimeout(distance) {
    if (distance < 3) return 220;
    if (distance < 8) return 520;
    if (distance < 15) return 820;
    return 1000;
  }

  // ---------------------------------------------------------------------------
  // Renderer (port of smear_cursor.draw)
  // ---------------------------------------------------------------------------
  function shrinkVolume(corners) {
    const center = MathHelpers.getCenter(corners);
    const topVector = {
      row: corners[1].row - corners[0].row,
      col: corners[1].col - corners[0].col,
    };
    const sideVector = {
      row: corners[3].row - corners[0].row,
      col: corners[3].col - corners[0].col,
    };

    const volume = Math.abs(topVector.col * sideVector.row - topVector.row * sideVector.col);
    if (volume <= 0) return corners;

    let factor = Math.pow(1 / volume, config.volume_reduction_exponent / 2);
    factor = Math.max(config.minimum_volume_factor, factor);

    const shrunk = [];
    for (let i = 0; i < 4; i++) {
      const cornerToTarget = {
        row: state.targetCorners[i].row - corners[i].row,
        col: state.targetCorners[i].col - corners[i].col,
      };
      const centerToCorner = {
        row: corners[i].row - center.row,
        col: corners[i].col - center.col,
      };
      const normal = MathHelpers.normalize({
        row: cornerToTarget.col,
        col: -cornerToTarget.row,
      });
      const projection = centerToCorner.row * normal.row + centerToCorner.col * normal.col;
      const shift = projection * (1 - factor);
      shrunk.push({
        row: corners[i].row - normal.row * shift,
        col: corners[i].col - normal.col * shift,
      });
    }

    return shrunk;
  }

  const VERTICAL_DOWN_CHARS = ['█', '▇', '▆', '▅', '▄', '▃', '▂', '▁', ' '];
  const VERTICAL_UP_CHARS = ['█', '🮆', '🮅', '🮄', '▀', '🮃', '🮂', '▔', ' '];
  const HORIZONTAL_RIGHT_CHARS = ['█', '🮋', '🮊', '🮉', '▐', '🮈', '🮇', '▕', ' '];
  const HORIZONTAL_LEFT_CHARS = ['█', '▉', '▊', '▋', '▌', '▍', '▎', '▏', ' '];
  const DIAGONAL_SE_CHARS = ['█', '▟', '▞', '▝', '▘', ' '];
  const DIAGONAL_SW_CHARS = ['█', '▙', '▚', '▖', '▗', ' '];
  const DIAGONAL_NE_CHARS = ['█', '▜', '▝', '▘', '▗', ' '];
  const DIAGONAL_NW_CHARS = ['█', '▛', '▖', '▘', '▝', ' '];
  const SAMPLE_OFFSETS = [0.2113, 0.7887];

  function detectOrientation(dirRow, dirCol) {
    const absRow = Math.abs(dirRow);
    const absCol = Math.abs(dirCol);
    if (absRow < 1e-4 && absCol < 1e-4) return 'vertical';
    if (absRow > absCol * 1.5) return 'vertical';
    if (absCol > absRow * 1.5) return 'horizontal';
    return 'diagonal';
  }

  function pointInQuad(row, col, corners) {
    let sign = 0;
    for (let i = 0; i < 4; i++) {
      const c1 = corners[i];
      const c2 = corners[(i + 1) % 4];
      const edgeX = c2.col - c1.col;
      const edgeY = c2.row - c1.row;
      const cross = edgeX * (row - c1.row) - edgeY * (col - c1.col);
      if (Math.abs(cross) < 1e-6) continue;
      const currentSign = Math.sign(cross);
      if (sign === 0) {
        sign = currentSign;
      } else if (currentSign !== sign) {
        return false;
      }
    }
    return true;
  }

  function cellCoverage(row, col, corners) {
    let coverage = 0;
    for (let i = 0; i < SAMPLE_OFFSETS.length; i++) {
      for (let j = 0; j < SAMPLE_OFFSETS.length; j++) {
        const sampleRow = row + SAMPLE_OFFSETS[i];
        const sampleCol = col + SAMPLE_OFFSETS[j];
        if (pointInQuad(sampleRow, sampleCol, corners)) {
          coverage += 0.25;
        }
      }
    }
    return Math.min(1, coverage);
  }

  function adjustColor(color, coverage) {
    const cov = Math.max(0, Math.min(1, coverage));
    const factor = 0.35 + cov * 0.65;
    const r = Math.min(255, Math.round(((color >> 16) & 0xff) * factor));
    const g = Math.min(255, Math.round(((color >> 8) & 0xff) * factor));
    const b = Math.min(255, Math.round((color & 0xff) * factor));
    return (r << 16) | (g << 8) | b;
  }

  function pickCharacterFromList(list, coverage) {
    const cov = Math.max(0, Math.min(1, coverage));
    if (cov <= 0.01) return null;
    const maxIndex = list.length - 1;
    const index = Math.min(maxIndex, Math.max(0, Math.floor((1 - cov) * maxIndex)));
    return list[index];
  }

  function chooseBlockCharacter(orientation, coverage, row, col, targetRow, targetCol) {
    const cov = Math.max(0, Math.min(1, coverage));
    if (cov <= 0.01) return null;

    if (orientation === 'vertical') {
      const cellCenterRow = row + 0.5;
      const isAbove = cellCenterRow < targetRow;
      const list = isAbove ? VERTICAL_UP_CHARS : VERTICAL_DOWN_CHARS;
      return pickCharacterFromList(list, cov);
    } else if (orientation === 'horizontal') {
      const cellCenterCol = col + 0.5;
      const isLeft = cellCenterCol < targetCol;
      const list = isLeft ? HORIZONTAL_LEFT_CHARS : HORIZONTAL_RIGHT_CHARS;
      return pickCharacterFromList(list, cov);
    }

    const relativeRow = row + 0.5 - targetRow;
    const relativeCol = col + 0.5 - targetCol;
    let list = DIAGONAL_SE_CHARS;
    if (relativeRow < 0 && relativeCol >= 0) {
      list = DIAGONAL_NE_CHARS;
    } else if (relativeRow >= 0 && relativeCol < 0) {
      list = DIAGONAL_SW_CHARS;
    } else if (relativeRow < 0 && relativeCol < 0) {
      list = DIAGONAL_NW_CHARS;
    }
    return pickCharacterFromList(list, cov);
  }

  function render(corners) {
    if (!state.layerCreated) return;

    const gutterWidth = typeof getGutterWidth === 'function' ? getGutterWidth() : 0;

    let minRow = Infinity;
    let maxRow = -Infinity;
    let minCol = Infinity;
    let maxCol = -Infinity;

    for (let i = 0; i < 4; i++) {
      const corner = corners[i];
      minRow = Math.min(minRow, corner.row);
      maxRow = Math.max(maxRow, corner.row);
      minCol = Math.min(minCol, corner.col);
      maxCol = Math.max(maxCol, corner.col);
    }

    minRow = Math.min(minRow, state.target.row);
    maxRow = Math.max(maxRow, state.target.row + 1);
    minCol = Math.min(minCol, state.target.col);
    maxCol = Math.max(maxCol, state.target.col + 1);

    const startRow = Math.floor(minRow) - 1;
    const endRow = Math.ceil(maxRow) + 1;
    const startCol = Math.floor(minCol) - 1;
    const endCol = Math.ceil(maxCol) + 1;

    const targetCenterRow = state.target.row + 0.5;
    const targetCenterCol = state.target.col + 0.5;
    const targetCenter = MathHelpers.getCenter(state.targetCorners);
    const currentCenter = MathHelpers.getCenter(state.currentCorners);
    const orientation = detectOrientation(
      targetCenter.row - currentCenter.row,
      targetCenter.col - currentCenter.col
    );

    const cells = [];
    for (let row = startRow; row < endRow; row++) {
      for (let col = startCol; col < endCol; col++) {
        if (config.never_draw_over_target) {
          const cursorRow = Math.floor(state.target.row);
          const cursorCol = Math.floor(state.target.col);
          if (row === cursorRow && col === cursorCol) {
            continue;
          }
        }

        const coverage = cellCoverage(row, col, corners);
        if (coverage <= 0) continue;

        const character = chooseBlockCharacter(
          orientation,
          coverage,
          row,
          col,
          targetCenterRow,
          targetCenterCol
        );
        if (!character) continue;

        const color = adjustColor(config.cursor_color, coverage);

        cells.push({
          row,
          col: col + gutterWidth,
          char: character.codePointAt(0),
          fg: color,
          bg: color,
        });
      }
    }

    renderVirtualText(LAYER_NAME, cells);
  }

  // ---------------------------------------------------------------------------
  // Animation loop
  // ---------------------------------------------------------------------------
  function changeTargetPosition(row, col) {
    const head = state.currentCorners[0];
    const dx = row - head.row;
    const dy = col - head.col;
    const distance = Math.sqrt(dx * dx + dy * dy);

    if (distance < 0.35) {
      logger.debug('jumping without animation (distance too small)');
      state.target = { row, col };
      setCorners(state.currentCorners, row, col);
      setCorners(state.targetCorners, row, col);
      resetVelocity();
      clearLayerSafe();
      stopAnimation();
      return;
    }

    state.target = { row, col };
    setCorners(state.targetCorners, row, col);
    state.lastMovementDistance = distance;
    state.currentTimeout = getAnimationTimeout(distance);
    setStiffnesses();
    if (!state.animating) {
      setInitialVelocity();
    }
    startAnimation();
  }

  function pollCursorPosition() {
    if (!config.enabled) return;
    let pos = null;

    try {
      pos = getCursorPosition();
    } catch (err) {
      logger.error('getCursorPosition failed:', err.toString());
      return;
    }

    if (!pos) return;

    const row = Math.floor(pos.row);
    const col = Math.floor(pos.col);
    const targetRow = Math.floor(state.target.row);
    const targetCol = Math.floor(state.target.col);

    if (row !== targetRow || col !== targetCol) {
      changeTargetPosition(row, col);
    }
  }

  function startAnimation() {
    if (state.animating) return;
    state.animating = true;
    state.animationStart = Date.now();
    state.lastTimestamp = 0;

    if (config.hide_target_hack && typeof setCursorRenderPosition === 'function') {
      setCursorRenderPosition(-1, -1);
    }
  }

  function stopAnimation(clear = false) {
    if (!state.animating) return;
    state.animating = false;
    state.lastTimestamp = 0;
    if (config.hide_target_hack && typeof clearCursorRenderPosition === 'function') {
      clearCursorRenderPosition();
    }
    if (clear) clearLayerSafe();
  }

  function updatePhysics() {
    let headIndex = 0;
    let minDistanceSquared = Infinity;
    const now = Date.now();

    let delta = BASE_INTERVAL_MS;
    if (state.lastTimestamp !== 0) {
      delta = now - state.lastTimestamp;
    }
    state.lastTimestamp = now;
    const correction = delta / BASE_INTERVAL_MS;

    const isFast = state.lastMovementDistance > config.fast_movement_threshold;
    const damping = isFast ? config.fast_damping : config.damping;
    const velocityFactor = Math.exp(Math.log(1 - damping) * correction);
    const dampingCorrection = 1 / (1 + 2.5 * velocityFactor);

    for (let i = 0; i < 4; i++) {
      const current = state.currentCorners[i];
      const target = state.targetCorners[i];
      const velocity = state.velocityCorners[i];

      const dx = target.col - current.col;
      const dy = target.row - current.row;
      const distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < minDistanceSquared) {
        minDistanceSquared = distanceSquared;
        headIndex = i;
      }

      const stiffness =
        1 - Math.exp(Math.log(1 - state.stiffnesses[i] * dampingCorrection) * correction);
      velocity.col += dx * stiffness;
      velocity.row += dy * stiffness;
      current.col += velocity.col;
      current.row += velocity.row;
      velocity.col *= velocityFactor;
      velocity.row *= velocityFactor;
    }

    let maxLength = 0;
    for (let i = 0; i < 4; i++) {
      if (i === headIndex) continue;
      const dx = state.currentCorners[i].col - state.currentCorners[headIndex].col;
      const dy = state.currentCorners[i].row - state.currentCorners[headIndex].row;
      const distance = Math.sqrt(dx * dx + dy * dy);
      maxLength = Math.max(maxLength, distance);
    }

    if (maxLength > config.max_length) {
      const factor = config.max_length / maxLength;
      for (let i = 0; i < 4; i++) {
        if (i === headIndex) continue;
        state.currentCorners[i].row =
          state.currentCorners[headIndex].row +
          (state.currentCorners[i].row - state.currentCorners[headIndex].row) * factor;
        state.currentCorners[i].col =
          state.currentCorners[headIndex].col +
          (state.currentCorners[i].col - state.currentCorners[headIndex].col) * factor;
      }
    }
  }

  function clearLayerSafe() {
    if (!state.layerCreated) return;
    try {
      clearLayer(LAYER_NAME);
    } catch (err) {
      logger.error('clearLayer failed:', err.toString());
    }
  }

  function animate() {
    if (!config.enabled || !state.animating) {
      stopAnimation(true);
      return;
    }

    const elapsed = Date.now() - state.animationStart;
    if (elapsed > state.currentTimeout) {
      logger.debug('animation timeout reached, forcing stop');
      setCorners(state.currentCorners, state.target.row, state.target.col);
      resetVelocity();
      stopAnimation(true);
      return;
    }

    const targetCenter = MathHelpers.getCenter(state.targetCorners);
    const currentCenter = MathHelpers.getCenter(state.currentCorners);
    const centerDistance = MathHelpers.distance(targetCenter, currentCenter);

    if (centerDistance <= config.distance_stop_animating) {
      logger.debug('center reached target, stopping animation');
      setCorners(state.currentCorners, state.target.row, state.target.col);
      resetVelocity();
      stopAnimation(true);
      return;
    }

    updatePhysics();

    const rowDiff = Math.abs(targetCenter.row - currentCenter.row);
    const colDiff = Math.abs(targetCenter.col - currentCenter.col);
    const straight = rowDiff < 0.125 || colDiff < 0.125;
    const drawn = straight ? state.currentCorners : shrinkVolume(state.currentCorners);

    clearLayerSafe();
    render(drawn);
  }

  function animationLoop() {
    if (!state.running) return;

    try {
      pollCursorPosition();
      if (state.animating) {
        animate();
      }
    } catch (err) {
      logger.error('animation loop error:', err.toString());
    }

    state.frameHandle = requestAnimationFrame(animationLoop);
  }

  function startLoop() {
    if (state.running) return;
    ensureLayer();
    initializeCursorPosition();
    state.running = true;
    state.frameHandle = requestAnimationFrame(animationLoop);
  }

  function stopLoop() {
    if (!state.running) return;
    state.running = false;
    if (state.frameHandle !== null && typeof cancelAnimationFrame === 'function') {
      cancelAnimationFrame(state.frameHandle);
    }
    state.frameHandle = null;
  }

  // ---------------------------------------------------------------------------
  // Platform bindings (events/init)
  // ---------------------------------------------------------------------------
  function ensureLayer() {
    if (state.layerCreated) return;
    try {
      createLayer(LAYER_NAME, { z_index: Z_INDEX, opacity: 1.0, cacheable: false });
      state.layerCreated = true;
      logger.info('virtual layer created:', LAYER_NAME);
    } catch (err) {
      // If the layer already exists, we still mark it as created
      state.layerCreated = true;
      logger.warn('createLayer failed (likely already exists):', err.toString());
    }
  }

  function initializeCursorPosition() {
    try {
      const pos = getCursorPosition();
      if (!pos) return;
      state.target = { row: pos.row, col: pos.col };
      for (let i = 0; i < 4; i++) {
        state.currentCorners[i] = cloneCorner(state.targetCorners[i]);
      }
      setCorners(state.currentCorners, pos.row, pos.col);
      setCorners(state.targetCorners, pos.row, pos.col);
      resetVelocity();
    } catch (err) {
      logger.warn('initializeCursorPosition failed:', err.toString());
    }
  }

  function enable() {
    if (config.enabled) return;
    config.enabled = true;
    logger.info('enabled');
    startLoop();
  }

  function disable() {
    if (!config.enabled) return;
    config.enabled = false;
    logger.info('disabled');
    stopAnimation(true);
    stopLoop();
  }

  function toggle() {
    if (config.enabled) {
      disable();
    } else {
      enable();
    }
  }

  function setup(opts = {}) {
    const previousEnabled = mergeConfig(opts);
    if (config.enabled && !previousEnabled) {
      startLoop();
    } else if (!config.enabled && previousEnabled) {
      disable();
    } else if (config.enabled && !state.running) {
      startLoop();
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------
  const api = {
    setup,
    enable,
    disable,
    toggle,
    config,
  };

  // Expose globally (compatibility with legacy scripts)
  globalThis.CodexSmearCursor = api;
  if (!globalThis.SmearCursor) {
    globalThis.SmearCursor = api;
  }

  // Auto start using defaults, mirroring smear_cursor.init.lua behaviour
  setup();
})();

