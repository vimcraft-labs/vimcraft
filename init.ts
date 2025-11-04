/// <reference types="@openvim/types" />

const colors = {
  bg: '#1e1e1e',
  bgAlt: '#252526',
  bgHighlight: '#1E202F',

  fg: '#d4d4d4',
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
  CursorLine: {
    bg: colors.bgHighlight,
  },
  CursorLineNr: {
    fg: colors.activeLineNumber,
  },
  LineNr: {
    fg: colors.lineNumber,
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
