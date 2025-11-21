// Options API Tests - TypeScript
// Tests vim.opt.* API with full Hermes runtime
//
// Build: zig build hermes-tests

declare const vim: {
    opt: {
        number: boolean;
        relativenumber: boolean;
        cursorline: boolean;
        tabstop: number;
        shiftwidth: number;
        expandtab: boolean;
        wrap: boolean;
        scrolloff: number;
        signcolumn: string;
    };
    optLocal: {
        number: boolean;
        cursorline: boolean;
        tabstop: number;
    };
    optGlobal: {
        number: boolean;
        cursorline: boolean;
        tabstop: number;
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: Boolean options can be read
function test_opt_read_boolean() {
    const number = vim.opt.number;
    vim.test.assert(typeof number === 'boolean', 'vim.opt.number should be boolean');

    const cursorline = vim.opt.cursorline;
    vim.test.assert(typeof cursorline === 'boolean', 'vim.opt.cursorline should be boolean');

    const wrap = vim.opt.wrap;
    vim.test.assert(typeof wrap === 'boolean', 'vim.opt.wrap should be boolean');

    vim.test.pass('test_opt_read_boolean');
}

// Test 2: Number options can be read
function test_opt_read_number() {
    const tabstop = vim.opt.tabstop;
    vim.test.assert(typeof tabstop === 'number', 'vim.opt.tabstop should be number');
    vim.test.assert(tabstop > 0, 'tabstop should be positive');

    const shiftwidth = vim.opt.shiftwidth;
    vim.test.assert(typeof shiftwidth === 'number', 'vim.opt.shiftwidth should be number');

    const scrolloff = vim.opt.scrolloff;
    vim.test.assert(typeof scrolloff === 'number', 'vim.opt.scrolloff should be number');

    vim.test.pass('test_opt_read_number');
}

// Test 3: Boolean options can be set
function test_opt_set_boolean() {
    const original = vim.opt.number;

    vim.opt.number = true;
    vim.test.assertEqual(vim.opt.number, true, 'Setting number=true should work');

    vim.opt.number = false;
    vim.test.assertEqual(vim.opt.number, false, 'Setting number=false should work');

    // Restore
    vim.opt.number = original;

    vim.test.pass('test_opt_set_boolean');
}

// Test 4: Number options can be set
function test_opt_set_number() {
    const original = vim.opt.tabstop;

    vim.opt.tabstop = 2;
    vim.test.assertEqual(vim.opt.tabstop, 2, 'Setting tabstop=2 should work');

    vim.opt.tabstop = 4;
    vim.test.assertEqual(vim.opt.tabstop, 4, 'Setting tabstop=4 should work');

    vim.opt.tabstop = 8;
    vim.test.assertEqual(vim.opt.tabstop, 8, 'Setting tabstop=8 should work');

    // Restore
    vim.opt.tabstop = original;

    vim.test.pass('test_opt_set_number');
}

// Test 5: optLocal scope works
function test_opt_local_scope() {
    const localTabstop = vim.optLocal.tabstop;
    vim.test.assert(typeof localTabstop === 'number', 'vim.optLocal.tabstop should be number');

    vim.test.pass('test_opt_local_scope');
}

// Test 6: optGlobal scope works
function test_opt_global_scope() {
    const globalTabstop = vim.optGlobal.tabstop;
    vim.test.assert(typeof globalTabstop === 'number', 'vim.optGlobal.tabstop should be number');

    vim.test.pass('test_opt_global_scope');
}

// Run all tests
function runTests() {
    test_opt_read_boolean();
    test_opt_read_number();
    test_opt_set_boolean();
    test_opt_set_number();
    test_opt_local_scope();
    test_opt_global_scope();
}

runTests();
