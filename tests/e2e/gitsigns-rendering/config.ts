// Gitsigns rendering test config
// Tests that sign column is properly rendered with extmarks

// CRITICAL: Enable sign column BEFORE setting any signs
vim.opt.signColumn = "yes";

// Set up highlight groups
vim.api.setHighlight(0, 'GitSignsAdd', { fg: '#98c379', bold: true });
vim.api.setHighlight(0, 'GitSignsChange', { fg: '#e5c07b', bold: true });
vim.api.setHighlight(0, 'GitSignsDelete', { fg: '#e06c75', bold: true });

console.log("[config] signColumn set to yes");
