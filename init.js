vim.opt.cursorline = true;

const highlights = {
	Normal: { bg: '#1A1B26', fg: '#d4d4d4' },
	CursorLine: { bg: '#1E202F' },
};

for (const key of Object.keys(highlights)) {
	vim.highlight(key, highlights[key]);
}
