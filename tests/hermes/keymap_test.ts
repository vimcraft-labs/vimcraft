// Keymap API Tests - TypeScript
// Tests vim.keymap.* API with full Hermes runtime
//
// Build: zig build hermes-tests

declare const vim: {
    keymap: {
        set: (mode: string, lhs: string, rhs: string | (() => void), opts?: {
            desc?: string;
            silent?: boolean;
            noremap?: boolean;
            buffer?: boolean;
        }) => void;
        del: (mode: string, lhs: string) => void;
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: keymap.set with string rhs
function test_keymap_set_string() {
    // Set a simple mapping
    vim.keymap.set('n', '<leader>t', ':echo "test"<CR>');

    // Should not throw
    vim.test.pass('test_keymap_set_string');
}

// Test 2: keymap.set with function rhs
function test_keymap_set_function() {
    let called = false;
    vim.keymap.set('n', '<leader>f', () => {
        called = true;
    });

    // Should not throw
    vim.test.pass('test_keymap_set_function');
}

// Test 3: keymap.set with options
function test_keymap_set_with_options() {
    vim.keymap.set('n', '<leader>o', ':echo "options"<CR>', {
        desc: 'Test mapping with options',
        silent: true,
        noremap: true
    });

    // Should not throw
    vim.test.pass('test_keymap_set_with_options');
}

// Test 4: keymap.del removes mapping
function test_keymap_del() {
    // Create mapping
    vim.keymap.set('n', '<leader>d', ':echo "delete"<CR>');

    // Delete mapping (should not throw)
    vim.keymap.del('n', '<leader>d');

    // Deleting again should be idempotent
    vim.keymap.del('n', '<leader>d');

    vim.test.pass('test_keymap_del');
}

// Test 5: keymap.set for different modes
function test_keymap_set_modes() {
    vim.keymap.set('n', '<leader>n', ':echo "normal"<CR>');
    vim.keymap.set('i', '<C-j>', '<Esc>');
    vim.keymap.set('v', '<leader>v', ':echo "visual"<CR>');

    vim.test.pass('test_keymap_set_modes');
}

// Run all tests
function runTests() {
    test_keymap_set_string();
    test_keymap_set_function();
    test_keymap_set_with_options();
    test_keymap_del();
    test_keymap_set_modes();
}

runTests();
