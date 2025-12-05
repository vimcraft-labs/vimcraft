// ============================================================================
// SIMULATES FULL USER CONFIG
// ============================================================================

// Colors (from user's index.ts)
const colors = {
  bg: "#1A1B26",
  fg: '#ABB2BF',
  bgAlt: '#252526',
  cursorLine: '#1E202F',
  statusLine: '#51afef',
  visual: '#283457',
  dim: "#343543",
  fgAlt: '#808080',
  lineNumber: '#343543',
  activeLineNumber: '#51afef',
  red: '#e06c75',
  green: '#98c379',
  yellow: '#e5c07b',
  blue: '#61afef',
  purple: '#c678dd',
  cyan: '#56b6c2',
  gray: '#5c6370',
  orange: "#FF8800",
};

// Highlights (from user's index.ts)
const highlights = {
  Normal: { bg: colors.bg, fg: colors.fg },
  Visual: { bg: colors.visual },
  CursorLine: { bg: colors.cursorLine },
  LineNr: { fg: colors.lineNumber },
  CursorLineNr: { fg: colors.activeLineNumber, bg: colors.cursorLine },
  StatusLine: { fg: colors.blue, bg: colors.bg },
  Search: { fg: colors.bg, bg: colors.orange },
  Comment: { fg: colors.gray, italic: true },
  String: { fg: colors.green },
  Keyword: { fg: colors.purple, bold: true },
  Function: { fg: colors.blue },
  Type: { fg: colors.yellow },
  Constant: { fg: colors.cyan },
  EndOfBuffer: { fg: colors.bg },
  // GitSigns highlights
  GitSignsAdd: { fg: colors.green, bold: true },
  GitSignsChange: { fg: colors.yellow, bold: true },
  GitSignsDelete: { fg: colors.red, bold: true },
};

for (const [name, opts] of Object.entries(highlights)) {
  vim.highlight(name, opts);
}

// Options (from user's index.ts)
vim.opt.number = true;
vim.opt.signColumn = "yes";
vim.opt.cursorLine = true;
vim.opt.relativeNumber = true;
vim.opt.lastStatus = LastStatus.Always;
vim.opt.list = true;
vim.opt.listChars = { tab: '', eol: '¬', space: '·' };

// Simulate git-bundle: add signs to buffer
const ns = vim.api.createNamespace("gitsigns");

// Add 50 git signs scattered throughout buffer
for (let i = 0; i < 50; i++) {
  const line = i * 2;
  const signType = i % 3 === 0 ? '+' : (i % 3 === 1 ? '~' : '-');
  const hlGroup = i % 3 === 0 ? 'GitSignsAdd' : (i % 3 === 1 ? 'GitSignsChange' : 'GitSignsDelete');
  vim.api.bufSetExtmark(0, ns, line, 0, { signText: signType, signHlGroup: hlGroup });
}

console.log("[config] Full user config loaded with 50 git signs");
