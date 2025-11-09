// smear.js - Smooth cursor animation plugin for OpenVim
// Port of smear-cursor.nvim with 1:1 architecture replication

console.log('[smear] Loading smear-cursor plugin...');

const LAYER_NAME = 'smear_cursor';
const Z_INDEX = 250;
const BASE_TIME_INTERVAL = 17; // 60fps target

// Configuration - Adaptive physics: bouncy for slow, responsive for fast!
const config = {
  cursor_color: 0xff8800,

  // Base stiffness (for slow movements)
  stiffness: 0.25,                   // Fluid motion
  trailing_stiffness: 0.08,          // Dramatic trail

  // Fast movement boost - MODERATE (gap-filling does the heavy lifting!)
  fast_stiffness: 0.5,               // Moderate boost (2x faster)
  fast_trailing_stiffness: 0.25,     // Tighter trail (3x faster)
  fast_movement_threshold: 5,        // Distance > 5 = fast

  damping: 0.4,                      // Bouncy!
  fast_damping: 0.6,                 // Slightly higher for fast
  trailing_exponent: 5,              // Bunched effect
  never_draw_over_target: false,     // DISABLED - hide_target_hack handles cursor hiding!
  hide_target_hack: true,            // Hides cursor during animation
  gamma: 1,

  anticipation: 0.5,                 // BIG BOUNCE!
  distance_stop_animating: 0.1,
  max_length: 20,                    // Nice length
  volume_reduction_exponent: 0.5,
  minimum_volume_factor: 0.3,
  enabled: true,
  time_interval: 17,
};

// Animation state (matching Neovim exactly)
let animating = false;
let timer = null;
let previous_time = 0;
let animation_start_time = 0;
let target_position = {row: 0, col: 0};
let current_corners = [
  {row: 0, col: 0}, // top-left
  {row: 0, col: 1}, // top-right
  {row: 1, col: 1}, // bottom-right
  {row: 1, col: 0}, // bottom-left
];
let target_corners = [
  {row: 0, col: 0},
  {row: 0, col: 1},
  {row: 1, col: 1},
  {row: 1, col: 0},
];
let velocity_corners = [
  {row: 0, col: 0},
  {row: 0, col: 0},
  {row: 0, col: 0},
  {row: 0, col: 0},
];
let stiffnesses = [0, 0, 0, 0];

// Track movement speed for adaptive stiffness
let current_movement_distance = 0;

function init() {
  console.log('[smear] Creating layer at z-index ' + Z_INDEX);
  createLayer(LAYER_NAME, {
    z_index: Z_INDEX,
    opacity: 1.0, // Fully opaque - no bleed-through!
    cacheable: false,
  });

  // Initialize cursor position
  const pos = getCursorPosition();
  if (pos) {
    target_position = {row: pos.row, col: pos.col};
    setCorners(current_corners, pos.row, pos.col);
    setCorners(target_corners, pos.row, pos.col);
  }

  // Start main loop using native requestAnimationFrame
  // Synchronized with editor render loop for perfect 60fps
  animationLoop();

  console.log('[smear] Plugin initialized with native animation API!');
}

// Main animation loop (native render loop integration)
let frame_count = 0;
let idle_timer = null;
function animationLoop() {
  frame_count++;

  // Poll cursor position
  pollCursorPosition();

  // Run animation step if active
  if (animating) {
    animate();

    // Debug: Log every 60 frames (once per second at 60fps)
    if (frame_count % 60 === 0) {
      console.log('[smear] Frame ' + frame_count + ' - animating, corners[0]:',
        'row=' + current_corners[0].row.toFixed(2),
        'col=' + current_corners[0].col.toFixed(2),
        'target=', target_position.row, ',', target_position.col);
    }

    // Continue at 60fps while animating
    requestAnimationFrame(animationLoop);
  } else {
    // When idle, DON'T use requestAnimationFrame (causes flickering)
    // Instead, poll cursor position slowly with setTimeout
    idle_timer = setTimeout(idleLoop, 50); // Poll at 20fps when idle
  }
}

// Idle loop - slower polling when not animating
function idleLoop() {
  // Poll cursor position
  pollCursorPosition();

  // If animation started, switch to fast loop
  if (animating) {
    requestAnimationFrame(animationLoop);
  } else {
    // Continue slow polling
    idle_timer = setTimeout(idleLoop, 50);
  }
}

function setCorners(corners, row, col) {
  // Block cursor (1x1 cell)
  corners[0] = {row: row, col: col};
  corners[1] = {row: row, col: col + 1};
  corners[2] = {row: row + 1, col: col + 1};
  corners[3] = {row: row + 1, col: col};
}

function resetVelocity() {
  for (let i = 0; i < 4; i++) {
    velocity_corners[i] = {row: 0, col: 0};
  }
}

function setInitialVelocity() {
  // CRITICAL: Initial velocity OPPOSITE to motion (creates bounce!)
  // This is the "anticipation" effect
  for (let i = 0; i < 4; i++) {
    velocity_corners[i].row = (current_corners[i].row - target_corners[i].row) * config.anticipation;
    velocity_corners[i].col = (current_corners[i].col - target_corners[i].col) * config.anticipation;
  }
}

function pollCursorPosition() {
  if (!config.enabled) return;

  const pos = getCursorPosition();
  if (!pos) return;

  // Only trigger animation if cursor actually moved (ignore floating point noise)
  // Use integer comparison to avoid sub-pixel flickering
  const row = Math.floor(pos.row);
  const col = Math.floor(pos.col);
  const target_row = Math.floor(target_position.row);
  const target_col = Math.floor(target_position.col);

  if (row !== target_row || col !== target_col) {
    changeTargetPosition(row, col);
  }
}

function getCenter(corners) {
  return {
    row: (corners[0].row + corners[1].row + corners[2].row + corners[3].row) / 4,
    col: (corners[0].col + corners[1].col + corners[2].col + corners[3].col) / 4,
  };
}

function setStiffnesses() {
  const target_center = getCenter(target_corners);
  const distances = [];
  let min_distance = Infinity;
  let max_distance = 0;

  // Calculate distance from each corner to target center
  for (let i = 0; i < 4; i++) {
    const corner = current_corners[i];
    const dx = corner.col - target_center.col;
    const dy = corner.row - target_center.row;
    const distance = Math.sqrt(dx * dx + dy * dy);

    distances[i] = distance;
    min_distance = Math.min(min_distance, distance);
    max_distance = Math.max(max_distance, distance);
  }

  // ADAPTIVE STIFFNESS: Use fast stiffness for rapid movements
  const is_fast_movement = current_movement_distance > config.fast_movement_threshold;
  const head_stiffness = is_fast_movement ? config.fast_stiffness : config.stiffness;
  const tail_stiffness = is_fast_movement ? config.fast_trailing_stiffness : config.trailing_stiffness;

  // If all corners are same distance, use head stiffness for all
  if (max_distance === min_distance) {
    for (let i = 0; i < 4; i++) {
      stiffnesses[i] = head_stiffness;
    }
    return;
  }

  // Calculate non-linear stiffness distribution
  for (let i = 0; i < 4; i++) {
    const x = (distances[i] - min_distance) / (max_distance - min_distance);
    const stiffness = head_stiffness + (tail_stiffness - head_stiffness) * Math.pow(x, config.trailing_exponent);
    stiffnesses[i] = Math.min(1, stiffness);
  }
}

// Calculate expected animation duration based on distance
function getAnimationTimeout(distance) {
  // Fast movements need MORE time to catch up with boosted stiffness
  if (distance < 3) return 200;
  if (distance < 8) return 500;   // Medium: 500ms
  if (distance < 15) return 800;  // Fast: 800ms
  return 1000;  // Very fast: 1 second max
}

function changeTargetPosition(row, col) {
  // Check if already at target position (prevent flickering when idle)
  const already_at_target = (
    Math.floor(current_corners[0].row) === Math.floor(row) &&
    Math.floor(current_corners[0].col) === Math.floor(col)
  );

  if (already_at_target && !animating) {
    // Already at target and not animating - nothing to do
    return;
  }

  // Check if jump is too small - instant jump instead of animating
  const dx = row - current_corners[0].row;
  const dy = col - current_corners[0].col;
  const distance = Math.sqrt(dx * dx + dy * dy);

  // Store distance for adaptive stiffness
  current_movement_distance = distance;

  console.log('[smear] Cursor moved from', current_corners[0].row, ',', current_corners[0].col,
    'to', row, ',', col, 'distance=', distance.toFixed(2),
    distance > config.fast_movement_threshold ? '(FAST - boosting stiffness)' : '(normal)');

  if (distance < 0.5) {
    // Too small to animate, instant jump
    console.log('[smear] Distance too small, instant jump');
    target_position = {row: row, col: col};
    setCorners(current_corners, row, col);
    setCorners(target_corners, row, col);
    if (animating) {
      stopAnimation();
    }
    clearLayer(LAYER_NAME);
    return;
  }

  console.log('[smear] Starting animation');
  target_position = {row: row, col: col};
  setCorners(target_corners, row, col);
  setStiffnesses();
  if (!animating) {
    setInitialVelocity(); // CRITICAL: Set initial velocity for bounce
  }

  // Store expected timeout based on distance
  config.current_timeout = getAnimationTimeout(distance);
  startAnimation();
}

function startAnimation() {
  if (animating) return;
  animating = true;
  animation_start_time = Date.now();

  // Hide target hack: move cursor render position off-screen during animation
  if (config.hide_target_hack) {
    setCursorRenderPosition(-1, -1);
  }

  // No need to start timer - animationLoop() runs every frame
}

function stopAnimation() {
  if (!animating) return;

  animating = false;
  previous_time = 0;

  // Restore cursor visibility
  if (config.hide_target_hack) {
    clearCursorRenderPosition();
  }

  // Don't clear here - animate() already cleared before stopping
}

// CRITICAL: update() implements sophisticated time-based physics
function update() {
  let distance_head_to_target_squared = Infinity;
  let index_head = 0;
  const max_length = config.max_length;

  // Time-based physics correction
  const current_time = Date.now();
  let time_interval;
  if (previous_time === 0) {
    previous_time = current_time;
    time_interval = BASE_TIME_INTERVAL;
  } else {
    time_interval = current_time - previous_time;
    previous_time = current_time;
  }

  const speed_correction = time_interval / BASE_TIME_INTERVAL;

  // ADAPTIVE DAMPING: Use fast damping for rapid movements
  const is_fast_movement = current_movement_distance > config.fast_movement_threshold;
  const damping = is_fast_movement ? config.fast_damping : config.damping;

  const velocity_conservation_factor = Math.exp(Math.log(1 - damping) * speed_correction);
  // Empirical correction factor to maintain animation duration
  const damping_correction_factor = 1 / (1 + 2.5 * velocity_conservation_factor);

  // Detect movement direction
  const target_center = getCenter(target_corners);
  const current_center = getCenter(current_corners);
  const delta_row = Math.abs(target_center.row - current_center.row);
  const delta_col = Math.abs(target_center.col - current_center.col);
  const is_vertical_movement = delta_row > delta_col * 1.5;
  const is_horizontal_movement = delta_col > delta_row * 1.5;

  // Move toward targets with sophisticated physics
  for (let i = 0; i < 4; i++) {
    const current = current_corners[i];
    const target = target_corners[i];
    const velocity = velocity_corners[i];

    const dx = target.col - current.col;
    const dy = target.row - current.row;
    const distance_squared = dx * dx + dy * dy;

    // Exponential stiffness (handles frame rate variations)
    const stiffness = 1 - Math.exp(Math.log(1 - stiffnesses[i] * damping_correction_factor) * speed_correction);

    if (distance_squared < distance_head_to_target_squared) {
      distance_head_to_target_squared = distance_squared;
      index_head = i;
    }

    // Apply spring physics
    velocity.col = velocity.col + dx * stiffness;
    velocity.row = velocity.row + dy * stiffness;

    current.col = current.col + velocity.col;
    current.row = current.row + velocity.row;

    velocity.col = velocity.col * velocity_conservation_factor;
    velocity.row = velocity.row * velocity_conservation_factor;
  }

  // Constrain corners for straight-line movements (prevent spreading)
  if (is_vertical_movement) {
    // Keep all corners at same column (prevent horizontal spreading)
    const target_col = target_corners[0].col;
    for (let i = 0; i < 4; i++) {
      current_corners[i].col = target_col;
      velocity_corners[i].col = 0;
    }
  } else if (is_horizontal_movement) {
    // Keep all corners at same row (prevent vertical spreading)
    const target_row = target_corners[0].row;
    for (let i = 0; i < 4; i++) {
      current_corners[i].row = target_row;
      velocity_corners[i].row = 0;
    }
  }

  // Limit max trail length
  let smear_length = 0;

  for (let i = 0; i < 4; i++) {
    if (i !== index_head) {
      const dx = current_corners[i].col - current_corners[index_head].col;
      const dy = current_corners[i].row - current_corners[index_head].row;
      const distance = Math.sqrt(dx * dx + dy * dy);
      smear_length = Math.max(smear_length, distance);
    }
  }

  if (smear_length > max_length) {
    const factor = max_length / smear_length;

    for (let i = 0; i < 4; i++) {
      if (i !== index_head) {
        current_corners[i].row = current_corners[index_head].row + (current_corners[i].row - current_corners[index_head].row) * factor;
        current_corners[i].col = current_corners[index_head].col + (current_corners[i].col - current_corners[index_head].col) * factor;
      }
    }
  }
}

function normalize(v) {
  const length = Math.sqrt(v.row * v.row + v.col * v.col);
  if (length === 0) return {row: 0, col: 0};
  return {row: v.row / length, col: v.col / length};
}

function shrinkVolume(corners) {
  // Calculate edges
  const edges = [];
  for (let i = 0; i < 3; i++) {
    edges.push({
      row: corners[i + 1].row - corners[0].row,
      col: corners[i + 1].col - corners[0].col,
    });
  }

  // Calculate volume (area)
  const volume = Math.abs(edges[0].col * edges[1].row - edges[0].row * edges[1].col);
  if (volume <= 0) return corners;

  const center = getCenter(corners);
  let factor = Math.pow(1 / volume, config.volume_reduction_exponent / 2);
  factor = Math.max(config.minimum_volume_factor, factor);

  const shrunk = [];
  for (let i = 0; i < 4; i++) {
    // Motion vector
    const corner_to_target = {
      row: target_corners[i].row - corners[i].row,
      col: target_corners[i].col - corners[i].col,
    };

    const center_to_corner = {
      row: corners[i].row - center.row,
      col: corners[i].col - center.col,
    };

    // Normal perpendicular to motion
    const normal = normalize({
      row: corner_to_target.col,
      col: -corner_to_target.row,
    });

    const projection = center_to_corner.row * normal.row + center_to_corner.col * normal.col;
    const shift = projection * (1 - factor);

    shrunk.push({
      row: corners[i].row - normal.row * shift,
      col: corners[i].col - normal.col * shift,
    });
  }

  return shrunk;
}

// CRITICAL: animate() follows Neovim architecture exactly
function animate() {
  if (!config.enabled || !animating) {
    stopAnimation();
    return;
  }

  // 0. TIMEOUT CHECK - force stop if animation runs too long
  const animation_duration = Date.now() - animation_start_time;
  const timeout = config.current_timeout || 300; // Default 300ms if not set
  if (animation_duration > timeout) {
    console.log('[smear] Animation TIMEOUT after ' + animation_duration + 'ms (limit: ' + timeout + 'ms) - forcing stop');
    setCorners(current_corners, target_position.row, target_position.col);
    resetVelocity();
    clearLayer(LAYER_NAME);
    stopAnimation();
    return;
  }

  // 1. Check stop condition BEFORE doing any work
  const current_center = getCenter(current_corners);
  const target_center = getCenter(target_corners);
  const center_dx = target_center.col - current_center.col;
  const center_dy = target_center.row - current_center.row;
  const center_distance = Math.sqrt(center_dx * center_dx + center_dy * center_dy);

  // FORCE STOP when center reaches target - CHECK FIRST before rendering
  if (center_distance <= 0.05) {
    console.log('[smear] Animation stopped (center reached target: dist=' + center_distance.toFixed(4) + ')');
    setCorners(current_corners, target_position.row, target_position.col);
    resetVelocity();
    clearLayer(LAYER_NAME); // Clear trail
    stopAnimation();
    return; // DONE - stop immediately, no more frames
  }

  // 2. Update physics
  update();

  // 3. Decide whether to shrink volume
  const row_diff = Math.abs(target_center.row - current_center.row);
  const col_diff = Math.abs(target_center.col - current_center.col);
  const straight_line = row_diff < 0.125 || col_diff < 0.125;

  const drawn_corners = straight_line ? current_corners : shrinkVolume(current_corners);

  // 4. Clear and render in one go
  clearLayer(LAYER_NAME);
  render(drawn_corners);
}

function render(drawn_corners) {
  const cells = [];
  const gutterWidth = getGutterWidth();

  const cursor_row = Math.floor(target_position.row);
  const cursor_col = Math.floor(target_position.col);

  // Get bounding box - CRITICAL: Always include cursor position!
  let min_row = Infinity, max_row = -Infinity;
  let min_col = Infinity, max_col = -Infinity;

  // First include all corners
  for (let i = 0; i < 4; i++) {
    min_row = Math.min(min_row, drawn_corners[i].row);
    max_row = Math.max(max_row, drawn_corners[i].row);
    min_col = Math.min(min_col, drawn_corners[i].col);
    max_col = Math.max(max_col, drawn_corners[i].col);
  }

  // CRITICAL: Force include cursor position to fill gap!
  // This ensures trail connects to cursor even when corners lag behind
  min_row = Math.min(min_row, target_position.row);
  max_row = Math.max(max_row, target_position.row + 1);
  min_col = Math.min(min_col, target_position.col);
  max_col = Math.max(max_col, target_position.col + 1);

  // Detect primarily vertical or horizontal movement
  const row_span = max_row - min_row;
  const col_span = max_col - min_col;
  const is_vertical = row_span > col_span * 2; // More vertical than horizontal
  const is_horizontal = col_span > row_span * 2; // More horizontal than vertical

  // SMART CONSTRAINTS: Keep trail tight in perpendicular direction
  // But DON'T override gap-filling in parallel direction!
  if (is_vertical) {
    // Vertical movement - constrain WIDTH to 1 column (perpendicular)
    // But preserve ROW extension (parallel - gap-filling already set this)
    const target_col = Math.floor(target_position.col);
    min_col = target_col;
    max_col = target_col + 1;
  } else if (is_horizontal) {
    // Horizontal movement - constrain HEIGHT to 1 row (perpendicular)
    // But preserve COL extension (parallel - gap-filling already set this)
    const target_row = Math.floor(target_position.row);
    min_row = target_row;
    max_row = target_row + 1;
  } else {
    // DIAGONAL movement - constrain to thin line (1 cell width/height)
    // Limit expansion in both directions to keep trail tight
    const target_row = Math.floor(target_position.row);
    const target_col = Math.floor(target_position.col);

    // Limit to 2 cells wide/tall max for diagonal
    if (col_span > 2) {
      min_col = Math.max(min_col, target_col - 1);
      max_col = Math.min(max_col, target_col + 2);
    }
    if (row_span > 2) {
      min_row = Math.max(min_row, target_row - 1);
      max_row = Math.min(max_row, target_row + 2);
    }
  }

  const start_row = Math.floor(min_row);
  const end_row = Math.ceil(max_row);
  const start_col = Math.floor(min_col);
  const end_col = Math.ceil(max_col);

  // Fill cells
  for (let row = start_row; row < end_row; row++) {
    for (let col = start_col; col < end_col; col++) {
      if (config.never_draw_over_target && row === cursor_row && col === cursor_col) {
        continue;
      }

      // Pure vibrant orange - SPACE with both fg and bg!
      const color = config.cursor_color; // #FF8800 everywhere

      cells.push({
        row: row,
        col: col + gutterWidth,
        char: 0x20, // SPACE character
        fg: color, // Keep foreground - it matters!
        bg: color, // Orange background
      });
    }
  }

  // Debug: Log what we're rendering
  if (cells.length > 0) {
    console.log('[smear] Rendering', cells.length, 'cells from row', start_row, 'to', end_row-1,
                'col', start_col, 'to', end_col-1, '(cursor at', cursor_row, ',', cursor_col, ')');
    renderVirtualText(LAYER_NAME, cells);
  }
}

// Initialize plugin
init();

// Export API
globalThis.SmearCursor = {
  enable: function() {
    config.enabled = true;
    console.log('[smear] Enabled');
  },
  disable: function() {
    config.enabled = false;
    stopAnimation();
    clearLayer(LAYER_NAME);
    console.log('[smear] Disabled');
  },
  config: config,
};

console.log('[smear] Plugin loaded successfully!');
