// Options API E2E Tests
// Tests vim.opt.* API with real editor state

vim.e2e.describe("Options Read - Boolean", function() {
    vim.e2e.test("vim.opt.number is boolean", function() {
        const number = vim.opt.number;
        vim.e2e.assert.true(typeof number === 'boolean', 'vim.opt.number should be boolean');
    });

    vim.e2e.test("vim.opt.cursorline is boolean", function() {
        const cursorline = vim.opt.cursorline;
        vim.e2e.assert.true(typeof cursorline === 'boolean', 'vim.opt.cursorline should be boolean');
    });

    vim.e2e.test("vim.opt.wrap is boolean", function() {
        const wrap = vim.opt.wrap;
        vim.e2e.assert.true(typeof wrap === 'boolean', 'vim.opt.wrap should be boolean');
    });
});

vim.e2e.describe("Options Read - Number", function() {
    vim.e2e.test("vim.opt.tabstop is positive number", function() {
        const tabstop = vim.opt.tabstop;
        vim.e2e.assert.true(typeof tabstop === 'number', 'vim.opt.tabstop should be number');
        vim.e2e.assert.true(tabstop > 0, 'tabstop should be positive');
    });

    vim.e2e.test("vim.opt.shiftwidth is number", function() {
        const shiftwidth = vim.opt.shiftwidth;
        vim.e2e.assert.true(typeof shiftwidth === 'number', 'vim.opt.shiftwidth should be number');
    });

    vim.e2e.test("vim.opt.scrolloff is number", function() {
        const scrolloff = vim.opt.scrolloff;
        vim.e2e.assert.true(typeof scrolloff === 'number', 'vim.opt.scrolloff should be number');
    });
});

vim.e2e.describe("Options Write - Boolean", function() {
    vim.e2e.test("setting vim.opt.number works", function() {
        const original = vim.opt.number;

        vim.opt.number = true;
        vim.e2e.assert.equal(vim.opt.number, true, 'Setting number=true should work');

        vim.opt.number = false;
        vim.e2e.assert.equal(vim.opt.number, false, 'Setting number=false should work');

        // Restore
        vim.opt.number = original;
    });
});

vim.e2e.describe("Options Write - Number", function() {
    vim.e2e.test("setting vim.opt.tabstop works", function() {
        const original = vim.opt.tabstop;

        vim.opt.tabstop = 2;
        vim.e2e.assert.equal(vim.opt.tabstop, 2, 'Setting tabstop=2 should work');

        vim.opt.tabstop = 4;
        vim.e2e.assert.equal(vim.opt.tabstop, 4, 'Setting tabstop=4 should work');

        vim.opt.tabstop = 8;
        vim.e2e.assert.equal(vim.opt.tabstop, 8, 'Setting tabstop=8 should work');

        // Restore
        vim.opt.tabstop = original;
    });
});

vim.e2e.describe("Options Scopes", function() {
    vim.e2e.test("vim.optLocal.tabstop is number", function() {
        const localTabstop = vim.optLocal.tabstop;
        vim.e2e.assert.true(typeof localTabstop === 'number', 'vim.optLocal.tabstop should be number');
    });

    vim.e2e.test("vim.optGlobal.tabstop is number", function() {
        const globalTabstop = vim.optGlobal.tabstop;
        vim.e2e.assert.true(typeof globalTabstop === 'number', 'vim.optGlobal.tabstop should be number');
    });
});

vim.e2e.runAll();
