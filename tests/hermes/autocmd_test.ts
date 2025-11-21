// Autocmd API Tests - TypeScript
// These tests run with full Hermes runtime via bytecode compilation
//
// Build: zig build hermes-tests
// This transpiles TS → JS (esbuild) → HBC (hermesc) → execute (Hermes)

declare const vim: {
    api: {
        createAutocmd: (event: string, opts: {
            callback: (ev: { event: string; buf: number; file?: string }) => void;
            pattern?: string;
            group?: string;
            once?: boolean;
            desc?: string;
        }) => number;
        delAutocmd: (id: number) => void;
        createAugroup: (name: string, opts?: { clear?: boolean }) => string;
        clearAutocmds: (opts?: { group?: string }) => void;
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: createAutocmd returns incrementing IDs
function test_createAutocmd_incrementing_ids() {
    let callCount = 0;
    const callback = () => { callCount++; };

    const id1 = vim.api.createAutocmd('BufEnter', { callback });
    const id2 = vim.api.createAutocmd('BufEnter', { callback });
    const id3 = vim.api.createAutocmd('BufEnter', { callback });

    vim.test.assertEqual(id1, 1, 'First autocmd should have ID 1');
    vim.test.assertEqual(id2, 2, 'Second autocmd should have ID 2');
    vim.test.assertEqual(id3, 3, 'Third autocmd should have ID 3');

    // Cleanup
    vim.api.delAutocmd(id1);
    vim.api.delAutocmd(id2);
    vim.api.delAutocmd(id3);

    vim.test.pass('test_createAutocmd_incrementing_ids');
}

// Test 2: createAutocmd with pattern
function test_createAutocmd_with_pattern() {
    let triggeredFile = '';
    const callback = (ev: { file?: string }) => {
        triggeredFile = ev.file || '';
    };

    const id = vim.api.createAutocmd('BufEnter', {
        callback,
        pattern: '*.ts',
        desc: 'Test TypeScript files'
    });

    vim.test.assert(id > 0, 'Should return valid ID');

    // Cleanup
    vim.api.delAutocmd(id);

    vim.test.pass('test_createAutocmd_with_pattern');
}

// Test 3: createAutocmd with group
function test_createAutocmd_with_group() {
    const group = vim.api.createAugroup('test_group', { clear: true });

    const id1 = vim.api.createAutocmd('BufEnter', {
        callback: () => {},
        group: 'test_group'
    });

    const id2 = vim.api.createAutocmd('BufLeave', {
        callback: () => {},
        group: 'test_group'
    });

    vim.test.assert(id1 > 0, 'First autocmd should have valid ID');
    vim.test.assert(id2 > 0, 'Second autocmd should have valid ID');

    // Clear group should remove all autocmds
    vim.api.clearAutocmds({ group: 'test_group' });

    vim.test.pass('test_createAutocmd_with_group');
}

// Test 4: delAutocmd removes autocmd
function test_delAutocmd() {
    let called = false;
    const callback = () => { called = true; };

    const id = vim.api.createAutocmd('BufEnter', { callback });
    vim.test.assert(id > 0, 'Should return valid ID');

    // Delete should not throw
    vim.api.delAutocmd(id);

    // Delete again should be idempotent (no error)
    vim.api.delAutocmd(id);

    vim.test.pass('test_delAutocmd');
}

// Test 5: once flag
function test_createAutocmd_once() {
    let callCount = 0;
    const callback = () => { callCount++; };

    const id = vim.api.createAutocmd('BufEnter', {
        callback,
        once: true
    });

    vim.test.assert(id > 0, 'Should return valid ID');

    // Note: We can't easily trigger the event in unit tests,
    // but we verify the autocmd was created successfully

    vim.test.pass('test_createAutocmd_once');
}

// Run all tests
function runTests() {
    // Note: No console.log - Hermes lean build doesn't have console defined

    test_createAutocmd_incrementing_ids();
    test_createAutocmd_with_pattern();
    test_createAutocmd_with_group();
    test_delAutocmd();
    test_createAutocmd_once();

    // All tests passed (if no exception thrown)
}

runTests();
