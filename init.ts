/// <reference types="@vimcraft/types" />

const colors = {
  bg: '#1A1B26',
  fg: '#ABB2BF',
  bgAlt: '#252526',
  cursorLine: '#1E202F',
  visual: '#283457',

  // fg: '#d4d4d4',
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
};

const highlights = {
  Normal: {
    bg: colors.bg,
    fg: colors.fg,
  },
  Visual: {
    bg: colors.visual,
  },
  CursorLine: {
    bg: colors.cursorLine,
  },
  LineNr: {
    fg: colors.lineNumber,
  },
  CursorLineNr: {
    fg: colors.activeLineNumber,
  },
  Comment: {
    fg: colors.gray,
    italic: true,
  },
  String: {
    fg: colors.green,
  },
  Keyword: {
    fg: colors.purple,
    bold: true,
  },
  Function: {
    fg: colors.blue,
  },
  Type: {
    fg: colors.yellow,
  },
  Constant: {
    fg: colors.cyan,
  },
};

for (const [name, opts] of Object.entries(highlights)) {
  vim.highlight(name, opts);
}

vim.opt.number = true;
vim.opt.signColumn = "yes";
vim.opt.cursorLine = true;

setTimeout(() => {
  console.log('✅ OpenVim ready!');
}, 100);

console.log('📝 Config loaded successfully!');
