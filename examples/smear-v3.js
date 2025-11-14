// smear.js - Complete Neovim smear-cursor.nvim port for Vimcraft
// Full implementation with proper draw_quad() rendering

console.log('[smear] Loading smear-cursor plugin...');

// ============================================================================
// CONFIGURATION
// ============================================================================

const config = {
  // Default Neovim smear-cursor values (not Fire Hazard Mode)
  cursor_color: 0xff8800,
  stiffness: 0.6,              // Neovim default (was 0.3)
  trailing_stiffness: 0.45,    // Neovim default (was 0.1)
  damping: 0.85,               // Neovim default (was 0.5)
  trailing_exponent: 3,        // Neovim default (was 5)
  never_draw_over_target: true,
  hide_target_hack: true,
  gamma: 2.2,                  // Neovim default (was 1)

  // Other physics
  anticipation: 0.2,

  // Geometry
  volume_reduction_exponent: 0.3,  // Original Neovim value
  minimum_volume_factor: 0.7,  // Original Neovim value
  max_length: 25,

  // Animation
  distance_stop_animating: 0.1,
  time_interval: 17,

  // Rendering
  max_slope_horizontal: 0.5,
  min_slope_vertical: 2,
  max_shade_no_matrix: 0.75,
  matrix_pixel_threshold: 0.7,
  matrix_pixel_min_factor: 0.5,

  // Color
  color_levels: 16,

  // System
  enabled: true,
};

// ============================================================================
// PART 1: CORE STATE
// ============================================================================

const LAYER_NAME = 'smear_cursor';
const Z_INDEX = 250;

let animating = false;
let previous_time = 0;
let target_position = [0, 0];
let current_corners = [[0,0], [0,0], [0,0], [0,0]];
let target_corners = [[0,0], [0,0], [0,0], [0,0]];
let velocity_corners = [[0,0], [0,0], [0,0], [0,0]];
let stiffnesses = [0, 0, 0, 0];

// ============================================================================
// PART 6A: PARTIAL BLOCK CHARACTERS
// ============================================================================

// Character sets (matching Neovim)
const BOTTOM_BLOCKS = ["█", "▇", "▆", "▅", "▄", "▃", "▂", "▁", " "];
const LEFT_BLOCKS = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"];
const VERTICAL_BARS = ["▏", "🭰", "🭱", "🭲", "🭳", "🭳", "🭵", "▕"];
const MATRIX_CHARACTERS = ["▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█"];

// Edge type enums
const TOP = 1;
const BOTTOM = 2;
const LEFT = 3;
const RIGHT = 4;
const LEFT_DIAGONAL = 5;
const RIGHT_DIAGONAL = 6;
const DIAGONAL = 7;
const NONE = 8;

// Alternating bulge for smoother animation
let bulge_above = false;

// ============================================================================
// PART 1: HELPERS
// ============================================================================

function setCorners(corners, row, col) {
  corners[0] = [row, col];
  corners[1] = [row, col + 1];
  corners[2] = [row + 1, col + 1];
  corners[3] = [row + 1, col];
}

function resetVelocity() {
  for (let i = 0; i < 4; i++) {
    velocity_corners[i] = [0, 0];
  }
}

function setInitialVelocity() {
  for (let i = 0; i < 4; i++) {
    for (let j = 0; j < 2; j++) {
      velocity_corners[i][j] = (current_corners[i][j] - target_corners[i][j]) * config.anticipation;
    }
  }
}

// ============================================================================
// PART 2: PHYSICS
// ============================================================================

function update() {
  let distance_head_to_target_squared = Infinity;
  let index_head = 0;

  // Time-based physics
  const BASE_TIME_INTERVAL = 17;
  let time_interval;
  if (previous_time === 0) {
    previous_time = Date.now();
    time_interval = BASE_TIME_INTERVAL;
  } else {
    const current_time = Date.now();
    time_interval = current_time - previous_time;
    previous_time = current_time;
  }

  const speed_correction = time_interval / BASE_TIME_INTERVAL;
  const velocity_conservation_factor = Math.exp(Math.log(1 - config.damping) * speed_correction);
  const damping_correction_factor = 1 / (1 + 2.5 * velocity_conservation_factor);

  // Move toward targets with spring physics
  for (let i = 0; i < 4; i++) {
    const distance_squared =
      (current_corners[i][0] - target_corners[i][0]) ** 2 +
      (current_corners[i][1] - target_corners[i][1]) ** 2;

    const stiffness = 1 - Math.exp(
      Math.log(1 - stiffnesses[i] * damping_correction_factor) * speed_correction
    );

    if (distance_squared < distance_head_to_target_squared) {
      distance_head_to_target_squared = distance_squared;
      index_head = i;
    }

    for (let j = 0; j < 2; j++) {
      velocity_corners[i][j] = velocity_corners[i][j] +
        (target_corners[i][j] - current_corners[i][j]) * stiffness;
      current_corners[i][j] = current_corners[i][j] + velocity_corners[i][j];
      velocity_corners[i][j] = velocity_corners[i][j] * velocity_conservation_factor;
    }
  }

  // Max length limiting
  let smear_length = 0;
  for (let i = 0; i < 4; i++) {
    if (i !== index_head) {
      const distance = Math.sqrt(
        (current_corners[i][0] - current_corners[index_head][0]) ** 2 +
        (current_corners[i][1] - current_corners[index_head][1]) ** 2
      );
      smear_length = Math.max(smear_length, distance);
    }
  }

  if (smear_length > config.max_length) {
    const factor = config.max_length / smear_length;
    for (let i = 0; i < 4; i++) {
      if (i !== index_head) {
        for (let j = 0; j < 2; j++) {
          current_corners[i][j] = current_corners[index_head][j] +
            (current_corners[i][j] - current_corners[index_head][j]) * factor;
        }
      }
    }
  }
}

// ============================================================================
// PART 3: GEOMETRY
// ============================================================================

function getCenter(corners) {
  return [
    (corners[0][0] + corners[1][0] + corners[2][0] + corners[3][0]) / 4,
    (corners[0][1] + corners[1][1] + corners[2][1] + corners[3][1]) / 4
  ];
}

function normalize(v) {
  const length = Math.sqrt(v[0] * v[0] + v[1] * v[1]);
  if (length === 0) return [0, 0];
  return [v[0] / length, v[1] / length];
}

function shrinkVolume(corners) {
  const edges = [];
  for (let i = 0; i < 3; i++) {
    edges[i] = [
      corners[i + 1][0] - corners[0][0],
      corners[i + 1][1] - corners[0][1]
    ];
  }

  const double_volumes = [];
  for (let i = 0; i < 2; i++) {
    double_volumes[i] = edges[1][1] * edges[2][0] - edges[1][0] * edges[2][1];
  }
  const volume = (double_volumes[0] + double_volumes[1]) / 2;

  if (volume <= 0) return corners;

  const center = getCenter(corners);
  let factor = Math.pow(1 / volume, config.volume_reduction_exponent / 2);
  factor = Math.max(config.minimum_volume_factor, factor);

  const shrunk_corners = [];
  for (let i = 0; i < 4; i++) {
    const corner_to_target = [
      target_corners[i][0] - corners[i][0],
      target_corners[i][1] - corners[i][1]
    ];
    const center_to_corner = [
      corners[i][0] - center[0],
      corners[i][1] - center[1]
    ];
    const normal = normalize([-corner_to_target[1], corner_to_target[0]]);
    const projection = center_to_corner[0] * normal[0] + center_to_corner[1] * normal[1];
    const shift = projection * (1 - factor);

    shrunk_corners[i] = [
      corners[i][0] - normal[0] * shift,
      corners[i][1] - normal[1] * shift
    ];
  }

  return shrunk_corners;
}

// ============================================================================
// PART 4: STIFFNESS GRADIENT
// ============================================================================

function setStiffnesses() {
  const target_center = getCenter(target_corners);
  const distances = [];
  let min_distance = Infinity;
  let max_distance = 0;

  for (let i = 0; i < 4; i++) {
    const distance = Math.sqrt(
      (current_corners[i][0] - target_center[0]) ** 2 +
      (current_corners[i][1] - target_center[1]) ** 2
    );
    distances[i] = distance;
    min_distance = Math.min(min_distance, distance);
    max_distance = Math.max(max_distance, distance);
  }

  if (max_distance === min_distance) {
    for (let i = 0; i < 4; i++) {
      stiffnesses[i] = config.stiffness;
    }
    return;
  }

  for (let i = 0; i < 4; i++) {
    const x = (distances[i] - min_distance) / (max_distance - min_distance);
    const stiffness = config.stiffness +
      (config.trailing_stiffness - config.stiffness) * Math.pow(x, config.trailing_exponent);
    stiffnesses[i] = Math.min(1, stiffness);
  }
}

// ============================================================================
// PART 6E: COLOR SYSTEM
// ============================================================================

function hexToRgb(hex) {
  const r = (hex >> 16) & 0xFF;
  const g = (hex >> 8) & 0xFF;
  const b = hex & 0xFF;
  return [r, g, b];
}

function rgbToHex(r, g, b) {
  return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
}

function interpolateColors(hex1, hex2, t) {
  const [r1, g1, b1] = hexToRgb(hex1);
  const [r2, g2, b2] = hexToRgb(hex2);

  const r = Math.round(r1 + t * (r2 - r1));
  const g = Math.round(g1 + t * (g2 - g1));
  const b = Math.round(b1 + t * (b2 - b1));

  return rgbToHex(r, g, b);
}

const NORMAL_BG = 0x000000;  // Black background
const TRANSPARENT_BG_FALLBACK = 0x303030;  // Dark gray

function getHlGroup(level, inverted) {
  level = level || config.color_levels;
  inverted = inverted || false;

  if (level === 0) {
    return { fg: config.cursor_color, bg: config.cursor_color };
  }

  // Calculate opacity with gamma correction
  const opacity = Math.pow(level / config.color_levels, 1 / config.gamma);

  // Interpolate color from background to cursor color
  const interpolated_color = interpolateColors(TRANSPARENT_BG_FALLBACK, config.cursor_color, opacity);

  if (inverted) {
    // Inverted mode: fg=bg, bg=cursor_color
    return {
      fg: TRANSPARENT_BG_FALLBACK,
      bg: interpolated_color
    };
  } else {
    // Normal mode: fg=cursor_color, bg=transparent
    return {
      fg: interpolated_color,
      bg: null  // Transparent
    };
  }
}

// ============================================================================
// PART 6B: EDGE GEOMETRY
// ============================================================================

function ensureClockwise(corners) {
  const cross = (corners[1][0] - corners[0][0]) * (corners[3][1] - corners[0][1]) -
                (corners[1][1] - corners[0][1]) * (corners[3][0] - corners[0][0]);

  if (cross > 0) {
    return [corners[2], corners[1], corners[0], corners[3]];
  }
  return corners;
}

function precomputeQuadGeometry(corners) {
  const G = {};

  // Bounding box
  G.top = Math.floor(Math.min(corners[0][0], corners[1][0], corners[2][0], corners[3][0]));
  G.bottom = Math.ceil(Math.max(corners[0][0], corners[1][0], corners[2][0], corners[3][0])) - 1;
  G.left = Math.floor(Math.min(corners[0][1], corners[1][1], corners[2][1], corners[3][1]));
  G.right = Math.ceil(Math.max(corners[0][1], corners[1][1], corners[2][1], corners[3][1])) - 1;

  // Edge slopes
  const edges = [];
  G.slopes = [];

  for (let i = 0; i < 4; i++) {
    const next_i = (i + 1) % 4;
    edges[i] = [
      corners[next_i][0] - corners[i][0],
      corners[next_i][1] - corners[i][1]
    ];
    G.slopes[i] = edges[i][0] / edges[i][1];
  }

  // Edge types
  G.edge_types = [];

  for (let i = 0; i < 4; i++) {
    const abs_slope = Math.abs(G.slopes[i]);

    if (abs_slope !== abs_slope) { // NaN check
      G.edge_types[i] = NONE;
    } else if (abs_slope <= config.max_slope_horizontal) {
      G.edge_types[i] = (edges[i][1] > 0) ? TOP : BOTTOM;
    } else if (abs_slope >= config.min_slope_vertical) {
      G.edge_types[i] = (edges[i][0] > 0) ? RIGHT : LEFT;
    } else {
      G.edge_types[i] = (edges[i][0] > 0) ? RIGHT_DIAGONAL : LEFT_DIAGONAL;
    }
  }

  // Precompute intersections
  G.I = {
    centerlines: [],
    edges: [],
    fractions: []
  };

  for (let i = 0; i < 4; i++) {
    const edge_type = G.edge_types[i];

    if (edge_type === TOP || edge_type === BOTTOM) {
      // Horizontal edge
      G.I.centerlines[i] = {};
      G.I.fractions[i] = {};

      for (let col = G.left; col <= G.right; col++) {
        G.I.centerlines[i][col] = corners[i][0] + (col + 0.5 - corners[i][1]) * G.slopes[i];
        G.I.fractions[i][col] = {};

        for (let j = 0; j < 2; j++) {
          const shift = (j === 0) ? -0.25 : 0.25;
          G.I.fractions[i][col][j] = G.I.centerlines[i][col] + shift * G.slopes[i];
        }
      }
    } else if (edge_type === LEFT || edge_type === RIGHT) {
      // Vertical edge
      G.I.centerlines[i] = {};
      G.I.fractions[i] = {};

      for (let row = G.top; row <= G.bottom; row++) {
        G.I.centerlines[i][row] = corners[i][1] + (row + 0.5 - corners[i][0]) / G.slopes[i];
        G.I.fractions[i][row] = {};

        for (let j = 0; j < 2; j++) {
          const shift = (j === 0) ? -0.25 : 0.25;
          G.I.fractions[i][row][j] = G.I.centerlines[i][row] + shift / G.slopes[i];
        }
      }
    } else if (edge_type === LEFT_DIAGONAL || edge_type === RIGHT_DIAGONAL) {
      // Diagonal edge
      G.I.centerlines[i] = {};
      G.I.edges[i] = {};
      G.I.fractions[i] = {};

      for (let row = G.top; row <= G.bottom; row++) {
        G.I.centerlines[i][row] = corners[i][1] + (row + 0.5 - corners[i][0]) / G.slopes[i];
        G.I.edges[i][row] = G.I.centerlines[i][row] +
          ((edge_type === LEFT_DIAGONAL ? 0.5 : -0.5) / Math.abs(G.slopes[i]));
        G.I.fractions[i][row] = {};

        for (let j = 0; j < 2; j++) {
          const shift = (j === 0) ? -0.25 : 0.25;
          G.I.fractions[i][row][j] = G.I.centerlines[i][row] + shift / G.slopes[i];
        }
      }
    }
  }

  return G;
}

// ============================================================================
// PART 6C: COVERAGE CALCULATION
// ============================================================================

function getEdgeCellIntersection(edge_index, row, col, G) {
  const edge_type = G.edge_types[edge_index];

  switch (edge_type) {
    case TOP:
      return G.I.centerlines[edge_index][col] - row;
    case BOTTOM:
      return row + 1 - G.I.centerlines[edge_index][col];
    case LEFT:
      return G.I.centerlines[edge_index][row] - col;
    case RIGHT:
      return col + 1 - G.I.centerlines[edge_index][row];
    case LEFT_DIAGONAL:
      return G.I.edges[edge_index][row] - col;
    case RIGHT_DIAGONAL:
      return col + 1 - G.I.edges[edge_index][row];
    case NONE:
    default:
      return 0;
  }
}

function round(x) {
  return Math.floor(x + 0.5);
}

function updateMatrixWithTopEdge(edge_index, fraction_index, row, col, G, matrix) {
  const row_float = 2 * (G.I.fractions[edge_index][col][fraction_index] - row);
  const matrix_index = Math.floor(row_float) + 1;

  for (let index = 0; index < Math.min(2, matrix_index - 1); index++) {
    matrix[index][fraction_index] = 0;
  }

  if (matrix_index === 1 || matrix_index === 2) {
    const shade = 1 - (row_float % 1);
    matrix[matrix_index - 1][fraction_index] = matrix[matrix_index - 1][fraction_index] * shade;
  }
}

function updateMatrixWithBottomEdge(edge_index, fraction_index, row, col, G, matrix) {
  const row_float = 2 * (G.I.fractions[edge_index][col][fraction_index] - row);
  const matrix_index = Math.floor(row_float) + 1;

  for (let index = Math.max(0, matrix_index + 1); index < 2; index++) {
    matrix[index][fraction_index] = 0;
  }

  if (matrix_index === 1 || matrix_index === 2) {
    const shade = row_float % 1;
    matrix[matrix_index - 1][fraction_index] = matrix[matrix_index - 1][fraction_index] * shade;
  }
}

function updateMatrixWithLeftEdge(edge_index, fraction_index, row, col, G, matrix) {
  const col_float = 2 * (G.I.fractions[edge_index][row][fraction_index] - col);
  const matrix_index = Math.floor(col_float) + 1;

  for (let index = 0; index < Math.min(2, matrix_index - 1); index++) {
    matrix[fraction_index][index] = 0;
  }

  if (matrix_index === 1 || matrix_index === 2) {
    const shade = 1 - (col_float % 1);
    matrix[fraction_index][matrix_index - 1] = matrix[fraction_index][matrix_index - 1] * shade;
  }
}

function updateMatrixWithRightEdge(edge_index, fraction_index, row, col, G, matrix) {
  const col_float = 2 * (G.I.fractions[edge_index][row][fraction_index] - col);
  const matrix_index = Math.floor(col_float) + 1;

  for (let index = Math.max(0, matrix_index + 1); index < 2; index++) {
    matrix[fraction_index][index] = 0;
  }

  if (matrix_index === 1 || matrix_index === 2) {
    const shade = col_float % 1;
    matrix[fraction_index][matrix_index - 1] = matrix[fraction_index][matrix_index - 1] * shade;
  }
}

function updateMatrixWithEdge(edge_index, fraction_index, row, col, G, matrix) {
  const edge_type = G.edge_types[edge_index];

  switch (edge_type) {
    case TOP:
      updateMatrixWithTopEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case BOTTOM:
      updateMatrixWithBottomEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case LEFT:
      updateMatrixWithLeftEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case RIGHT:
      updateMatrixWithRightEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case LEFT_DIAGONAL:
      updateMatrixWithLeftEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case RIGHT_DIAGONAL:
      updateMatrixWithRightEdge(edge_index, fraction_index, row, col, G, matrix);
      break;
    case NONE:
    default:
      // Do nothing
      break;
  }
}

// ============================================================================
// PART 6D: DRAWING FUNCTIONS
// ============================================================================

// Batch cells for rendering
let render_cells = [];

function drawCharacter(row, col, character, hl_group) {
  const gutterWidth = getGutterWidth();

  render_cells.push({
    row: row,
    col: col + gutterWidth,
    char: character.codePointAt(0),
    fg: hl_group.fg || config.cursor_color,
    bg: hl_group.bg || config.cursor_color,
  });
}

function getBottomBlockProperties(micro_shift, thickness, shade) {
  const character_index = Math.min(8, Math.max(0, Math.floor(micro_shift)));
  if (character_index === 8) return null;

  const character_thickness = 1 - character_index / 8;
  shade = shade * thickness / character_thickness;
  const hl_group_index = round(shade * config.color_levels);
  if (hl_group_index === 0) return null;

  return {
    character_index: character_index,
    character_list: BOTTOM_BLOCKS,
    hl_group: getHlGroup(hl_group_index)
  };
}

function getTopBlockProperties(micro_shift, thickness, shade) {
  const character_index = Math.min(8, Math.max(0, Math.ceil(micro_shift)));
  if (character_index === 0) return null;

  const character_thickness = character_index / 8;
  shade = shade * thickness / character_thickness;
  const hl_group_index = round(shade * config.color_levels);
  if (hl_group_index === 0) return null;

  // Modern approach: use BOTTOM_BLOCKS with inverted colors
  return {
    character_index: character_index,
    character_list: BOTTOM_BLOCKS,
    hl_group: getHlGroup(hl_group_index, true)  // inverted
  };
}

function drawVerticallyShiftedSubBlock(row_top, row_bottom, col, shade) {
  if (row_top >= row_bottom) return;

  const row = Math.floor(row_top);
  const center = ((row_top + row_bottom) / 2) % 1;
  const thickness = row_bottom - row_top;
  const gap_top = row_top % 1;
  const gap_bottom = (1 - row_bottom) % 1;

  let props;

  // Alternating bulge logic (matches Neovim exactly)
  if (Math.max(gap_top, gap_bottom) / 2 < Math.min(gap_top, gap_bottom)) {
    if (bulge_above) {
      const micro_shift = (row_bottom % 1) * 8;
      props = getTopBlockProperties(micro_shift, thickness, shade);
    } else {
      const micro_shift = (row_top % 1) * 8;
      props = getBottomBlockProperties(micro_shift, thickness, shade);
    }
  } else if (center < 0.5) {
    // Draw top block
    const micro_shift = center * 16;
    props = getTopBlockProperties(micro_shift, thickness, shade);
  } else {
    // Draw bottom block
    const micro_shift = center * 16 - 8;
    props = getBottomBlockProperties(micro_shift, thickness, shade);
  }

  if (props) {
    const character = props.character_list[props.character_index];
    drawCharacter(row, col, character, props.hl_group);
  }
}

function getLeftBlockProperties(micro_shift, thickness, shade) {
  const character_index = Math.min(8, Math.max(0, Math.ceil(micro_shift)));
  if (character_index === 0) return null;

  const character_thickness = character_index / 8;
  shade = shade * thickness / character_thickness;
  const hl_group_index = round(shade * config.color_levels);
  if (hl_group_index === 0) return null;

  return {
    character_index: character_index,
    character_list: LEFT_BLOCKS,
    hl_group: getHlGroup(hl_group_index)
  };
}

function getRightBlockProperties(micro_shift, thickness, shade) {
  const character_index = Math.min(8, Math.max(0, Math.floor(micro_shift)));
  if (character_index === 8) return null;

  const character_thickness = 1 - character_index / 8;
  shade = shade * thickness / character_thickness;
  const hl_group_index = round(shade * config.color_levels);
  if (hl_group_index === 0) return null;

  // Modern approach: use LEFT_BLOCKS with inverted colors
  return {
    character_index: character_index,
    character_list: LEFT_BLOCKS,
    hl_group: getHlGroup(hl_group_index, true)  // inverted
  };
}

function getVerticalBarProperties(micro_shift, thickness, shade) {
  const character_index = Math.min(7, Math.max(0, Math.floor(micro_shift)));
  if (character_index < 0 || character_index >= 8) return null;

  const character_thickness = 1 / 8;
  shade = Math.min(1, shade * thickness / character_thickness);
  const hl_group_index = round(shade * config.color_levels);
  if (hl_group_index === 0) return null;

  return {
    character_index: character_index,
    character_list: VERTICAL_BARS,
    hl_group: getHlGroup(hl_group_index)
  };
}

function drawHorizontallyShiftedSubBlock(row, col_left, col_right, shade) {
  if (col_left >= col_right) return;

  const col = Math.floor(col_left);
  const center = ((col_left + col_right) / 2) % 1;
  const thickness = col_right - col_left;
  const gap_left = col_left % 1;
  const gap_right = (1 - col_right) % 1;

  let props;

  // Use vertical bars for very thin horizontal smears (matching Neovim)
  if (thickness <= 1.5 / 8) {
    const micro_shift = center * 8;
    props = getVerticalBarProperties(micro_shift, thickness, shade);
  } else if (Math.max(gap_left, gap_right) / 2 < Math.min(gap_left, gap_right)) {
    // Alternating bulge
    if (bulge_above) {
      const micro_shift = (col_right % 1) * 8;
      props = getLeftBlockProperties(micro_shift, thickness, shade);
    } else {
      const micro_shift = (col_left % 1) * 8;
      props = getRightBlockProperties(micro_shift, thickness, shade);
    }
  } else if (center < 0.5) {
    // Draw left block
    const micro_shift = center * 16;
    props = getLeftBlockProperties(micro_shift, thickness, shade);
  } else {
    // Draw right block
    const micro_shift = center * 16 - 8;
    props = getRightBlockProperties(micro_shift, thickness, shade);
  }

  if (props) {
    const character = props.character_list[props.character_index];
    drawCharacter(row, col, character, props.hl_group);
  }
}

function drawMatrixCharacter(row, col, matrix) {
  const max = Math.max(matrix[0][0], matrix[0][1], matrix[1][0], matrix[1][1]);
  if (max < config.matrix_pixel_threshold) return;

  const threshold = max * config.matrix_pixel_min_factor;
  const bit_1 = (matrix[0][0] > threshold) ? 1 : 0;
  const bit_2 = (matrix[0][1] > threshold) ? 1 : 0;
  const bit_3 = (matrix[1][0] > threshold) ? 1 : 0;
  const bit_4 = (matrix[1][1] > threshold) ? 1 : 0;
  const index = bit_1 * 1 + bit_2 * 2 + bit_3 * 4 + bit_4 * 8;
  if (index === 0) return;

  const character = MATRIX_CHARACTERS[index - 1];
  const shade = matrix[0][0] + matrix[0][1] + matrix[1][0] + matrix[1][1];
  const max_shade = bit_1 + bit_2 + bit_3 + bit_4;
  let hl_group_index = round(shade / max_shade * config.color_levels);
  hl_group_index = Math.min(hl_group_index, config.color_levels);  // Clamp to max
  if (hl_group_index === 0) return;

  drawCharacter(row, col, character, getHlGroup(hl_group_index));
}

// ============================================================================
// PART 6D: MAIN DRAW_QUAD FUNCTION
// ============================================================================

function drawQuad(corners, target_pos) {
  // Toggle bulge direction for smoother animation
  bulge_above = !bulge_above;

  // Clear cells for this frame
  render_cells = [];

  corners = ensureClockwise(corners);
  const G = precomputeQuadGeometry(corners);

  for (let row = G.top; row <= G.bottom; row++) {
    for (let col = G.left; col <= G.right; col++) {
      // Skip target cell
      if (config.never_draw_over_target &&
          row === Math.floor(target_pos[0]) &&
          col === Math.floor(target_pos[1])) {
        continue;
      }

      // Calculate intersections for all 4 edges
      const intersections = {};
      let should_skip = false;

      for (let i = 0; i < 4; i++) {
        const intersection = getEdgeCellIntersection(i, row, col, G);
        let edge_type = G.edge_types[i];

        if (edge_type === LEFT_DIAGONAL || edge_type === RIGHT_DIAGONAL) {
          edge_type = DIAGONAL;
        }

        if (edge_type !== DIAGONAL && intersection >= 1) {
          should_skip = true;
          break;
        }

        if (intersections[edge_type] === undefined || intersections[edge_type] < intersection) {
          intersections[edge_type] = intersection;
        }
      }

      if (should_skip) continue;

      // Try to render as shifted block
      if (intersections[DIAGONAL] === undefined || intersections[DIAGONAL] < 1 - config.max_shade_no_matrix) {
        let is_vertically_shifted = false;
        let vertical_shade = 1;
        let is_horizontally_shifted = false;
        let horizontal_shade = 1;

        if (intersections[TOP] !== undefined || intersections[BOTTOM] !== undefined) {
          is_vertically_shifted = true;
          intersections[TOP] = Math.max(0, intersections[TOP] || 0);
          intersections[BOTTOM] = Math.max(0, intersections[BOTTOM] || 0);
          vertical_shade = 1 - intersections[TOP] - intersections[BOTTOM];
        }

        if (intersections[LEFT] !== undefined || intersections[RIGHT] !== undefined) {
          is_horizontally_shifted = true;
          intersections[LEFT] = Math.max(0, intersections[LEFT] || 0);
          intersections[RIGHT] = Math.max(0, intersections[RIGHT] || 0);
          horizontal_shade = 1 - intersections[LEFT] - intersections[RIGHT];
        }

        if (is_vertically_shifted && is_horizontally_shifted) {
          if (vertical_shade < config.max_shade_no_matrix &&
              horizontal_shade < config.max_shade_no_matrix) {
            is_horizontally_shifted = false;
            is_vertically_shifted = false;
          } else if (2 * (1 - vertical_shade) > (1 - horizontal_shade)) {
            is_horizontally_shifted = false;
          } else {
            is_vertically_shifted = false;
          }
        }

        // Draw shifted block
        if (is_vertically_shifted) {
          drawVerticallyShiftedSubBlock(
            row + intersections[TOP],
            row + 1 - intersections[BOTTOM],
            col,
            horizontal_shade
          );
          continue;
        }

        if (is_horizontally_shifted) {
          // Filter very thin right blocks near target (reduces blocky appearance)
          if (1 - intersections[RIGHT] <= 1 / 8 &&
              row === Math.floor(target_pos[0]) &&
              (col === Math.floor(target_pos[1]) || col === Math.floor(target_pos[1]) + 1)) {
            continue;
          }

          drawHorizontallyShiftedSubBlock(
            row,
            col + intersections[LEFT],
            col + 1 - intersections[RIGHT],
            vertical_shade
          );
          continue;
        }
      }

      // Draw matrix character (fallback)
      const matrix = [[1, 1], [1, 1]];

      // Update matrix with edge intersections
      for (let edge_index = 0; edge_index < 4; edge_index++) {
        for (let fraction_index = 0; fraction_index < 2; fraction_index++) {
          updateMatrixWithEdge(edge_index, fraction_index, row, col, G, matrix);
        }
      }

      drawMatrixCharacter(row, col, matrix);
    }
  }

  // Render all cells at once
  if (render_cells.length > 0) {
    renderVirtualText(LAYER_NAME, render_cells);
  }
}

// ============================================================================
// PART 5: ANIMATION
// ============================================================================

function animate() {
  try {
    if (!config.enabled || !animating) {
      // Make sure layer is cleared when stopping
      renderVirtualText(LAYER_NAME, []);
      clearLayer(LAYER_NAME);
      stopAnimation();
      return;
    }

    update();

    // Check stop condition
    let max_distance = 0;
    let max_velocity = 0;

    for (let i = 0; i < 4; i++) {
      const distance = Math.sqrt(
        (current_corners[i][0] - target_corners[i][0]) ** 2 +
        (current_corners[i][1] - target_corners[i][1]) ** 2
      );
      const velocity = Math.sqrt(
        velocity_corners[i][0] ** 2 + velocity_corners[i][1] ** 2
      );
      max_distance = Math.max(max_distance, distance);
      max_velocity = Math.max(max_velocity, velocity);
    }

    // Check stop condition
    const should_stop = max_distance <= config.distance_stop_animating &&
                        max_velocity <= config.distance_stop_animating;

    if (!should_stop) {
      // Continue animating - render the trail
      const current_center = getCenter(current_corners);
      const target_center = getCenter(target_corners);

      // Check if moving in a straight line (horizontal or vertical)
      const straight_line = Math.abs(target_center[0] - current_center[0]) < 1/8 ||
                           Math.abs(target_center[1] - current_center[1]) < 1/8;

      // Only shrink volume for diagonal movements to reduce blocky appearance
      // Straight-line movements skip shrinking (but have tighter thickness already)
      const drawn_corners = straight_line ? current_corners : shrinkVolume(current_corners);

      clearLayer(LAYER_NAME);
      drawQuad(drawn_corners, target_position);
    } else {
      // Animation complete - clear trail
      setCorners(current_corners, target_position[0], target_position[1]);
      resetVelocity();

      clearLayer(LAYER_NAME);
      renderVirtualText(LAYER_NAME, []);

      stopAnimation();
      return;
    }
  } catch (error) {
    console.log('[smear] ERROR in animate():', error.toString());
    renderVirtualText(LAYER_NAME, []);
    clearLayer(LAYER_NAME);
    stopAnimation();
  }
}

// ============================================================================
// ANIMATION CONTROL
// ============================================================================

function startAnimation() {
  if (animating) return;
  animating = true;

  if (config.hide_target_hack) {
    setCursorRenderPosition(-1, -1);
  }
}

function stopAnimation() {
  if (!animating) return;
  animating = false;
  previous_time = 0;

  if (config.hide_target_hack) {
    clearCursorRenderPosition();
  }

  // Don't clear the main animation timer here - it should keep running for idle detection
}

// ============================================================================
// PART 7: MAIN LOOP
// ============================================================================

function changeTargetPosition(row, col) {
  const dx = row - current_corners[0][0];
  const dy = col - current_corners[0][1];
  const distance = Math.sqrt(dx * dx + dy * dy);

  if (distance < 0.5) {
    target_position = [row, col];
    setCorners(current_corners, row, col);
    setCorners(target_corners, row, col);
    renderVirtualText(LAYER_NAME, []);
    clearLayer(LAYER_NAME);
    return;
  }

  target_position = [row, col];
  setCorners(target_corners, row, col);
  setStiffnesses();

  if (!animating) {
    setInitialVelocity();
  }

  startAnimation();
}

let frame_count = 0;

function animationLoop() {
  if (!config.enabled) {
    // Ensure layer is clear when disabled
    renderVirtualText(LAYER_NAME, []);
    clearLayer(LAYER_NAME);
    requestAnimationFrame(animationLoop);
    return;
  }

  frame_count++;

  // Check for cursor movement (runs even when not animating)
  try {
    const pos = getCursorPosition();
    if (pos) {
      const row = Math.floor(pos.row);
      const col = Math.floor(pos.col);
      const target_row = Math.floor(target_position[0]);
      const target_col = Math.floor(target_position[1]);

      if (row !== target_row || col !== target_col) {
        changeTargetPosition(row, col);
      }
    }
  } catch (error) {
    console.log('[smear] Error in cursor polling:', error.toString());
  }

  // Run animation frame if active
  if (animating) {
    try {
      animate();
    } catch (error) {
      console.log('[smear] Error in animate:', error.toString());
      renderVirtualText(LAYER_NAME, []);
      clearLayer(LAYER_NAME);
      stopAnimation();
    }
  }

  // Always use requestAnimationFrame for smooth rendering
  requestAnimationFrame(animationLoop);
}

// ============================================================================
// PART 8: INITIALIZATION
// ============================================================================

function init() {
  createLayer(LAYER_NAME, {
    z_index: Z_INDEX,
    opacity: 1.0,
    cacheable: false,
  });

  const pos = getCursorPosition();

  if (pos) {
    target_position = [pos.row, pos.col];
    setCorners(current_corners, pos.row, pos.col);
    setCorners(target_corners, pos.row, pos.col);
  }

  animationLoop();
}

init();

// Export API
globalThis.SmearCursor = {
  enable: function() {
    config.enabled = true;
  },
  disable: function() {
    config.enabled = false;
    stopAnimation();
    renderVirtualText(LAYER_NAME, []);
    clearLayer(LAYER_NAME);
  },
  config: config,
};

console.log('[smear] Plugin loaded!');

