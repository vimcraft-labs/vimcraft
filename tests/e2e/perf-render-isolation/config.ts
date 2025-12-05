// Minimal config - just highlights like user's config

const colors = {
  bg: "#1A1B26",
  fg: '#ABB2BF',
  cursorLine: '#1E202F',
  lineNumber: '#343543',
  activeLineNumber: '#51afef',
  green: '#98c379',
  yellow: '#e5c07b',
  purple: '#c678dd',
  blue: '#61afef',
  cyan: '#56b6c2',
  gray: '#5c6370',
};

const highlights = {
  Normal: { bg: colors.bg, fg: colors.fg },
  CursorLine: { bg: colors.cursorLine },
  LineNr: { fg: colors.lineNumber },
  CursorLineNr: { fg: colors.activeLineNumber, bg: colors.cursorLine },
  Comment: { fg: colors.gray, italic: true },
  String: { fg: colors.green },
  Keyword: { fg: colors.purple, bold: true },
  Function: { fg: colors.blue },
  Type: { fg: colors.yellow },
  Constant: { fg: colors.cyan },
  GitSignsAdd: { fg: colors.green, bold: true },
  GitSignsChange: { fg: colors.yellow, bold: true },
};

for (const [name, opts] of Object.entries(highlights)) {
  vim.highlight(name, opts);
}

console.log("[config] Highlights set");
