// Motion API Tests - TypeScript
// These tests run with full Hermes runtime via bytecode compilation

declare const vim: {
    motion: {
        left: (count?: number) => void;
        right: (count?: number) => void;
        up: (count?: number) => void;
        down: (count?: number) => void;
        lineStart: () => void;
        lineEnd: () => void;
        wordForward: () => void;
        wordBackward: () => void;
        wordEnd: () => void;
        fileStart: () => void;
        fileEnd: () => void;
        pageUp: () => void;
        pageDown: () => void;
    };
    cursor: {
        getPosition: () => { line: number; col: number };
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: Basic motion commands exist
function test_motion_api_exists() {
    vim.test.assert(typeof vim.motion.left === 'function', 'vim.motion.left should be a function');
    vim.test.assert(typeof vim.motion.right === 'function', 'vim.motion.right should be a function');
    vim.test.assert(typeof vim.motion.up === 'function', 'vim.motion.up should be a function');
    vim.test.assert(typeof vim.motion.down === 'function', 'vim.motion.down should be a function');

    vim.test.pass('test_motion_api_exists');
}

// Test 2: Line motions exist
function test_line_motions_exist() {
    vim.test.assert(typeof vim.motion.lineStart === 'function', 'vim.motion.lineStart should be a function');
    vim.test.assert(typeof vim.motion.lineEnd === 'function', 'vim.motion.lineEnd should be a function');

    vim.test.pass('test_line_motions_exist');
}

// Test 3: Word motions exist
function test_word_motions_exist() {
    vim.test.assert(typeof vim.motion.wordForward === 'function', 'vim.motion.wordForward should be a function');
    vim.test.assert(typeof vim.motion.wordBackward === 'function', 'vim.motion.wordBackward should be a function');
    vim.test.assert(typeof vim.motion.wordEnd === 'function', 'vim.motion.wordEnd should be a function');

    vim.test.pass('test_word_motions_exist');
}

// Test 4: File motions exist
function test_file_motions_exist() {
    vim.test.assert(typeof vim.motion.fileStart === 'function', 'vim.motion.fileStart should be a function');
    vim.test.assert(typeof vim.motion.fileEnd === 'function', 'vim.motion.fileEnd should be a function');
    vim.test.assert(typeof vim.motion.pageUp === 'function', 'vim.motion.pageUp should be a function');
    vim.test.assert(typeof vim.motion.pageDown === 'function', 'vim.motion.pageDown should be a function');

    vim.test.pass('test_file_motions_exist');
}

// Test 5: Cursor position API
function test_cursor_api_exists() {
    vim.test.assert(typeof vim.cursor.getPosition === 'function', 'vim.cursor.getPosition should be a function');

    vim.test.pass('test_cursor_api_exists');
}

// Run all tests
function runTests() {
    // Note: No console.log - Hermes lean build doesn't have console defined

    test_motion_api_exists();
    test_line_motions_exist();
    test_word_motions_exist();
    test_file_motions_exist();
    test_cursor_api_exists();

    // All tests passed (if no exception thrown)
}

runTests();
