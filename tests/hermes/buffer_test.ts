// Buffer API Tests - TypeScript
// Tests vim.buffer.* API with full Hermes runtime
//
// Build: zig build hermes-tests

declare const vim: {
    buffer: {
        getContent: () => ArrayBuffer;
        getLineContent: (line: number) => ArrayBuffer;
        getLength: () => number;
        getLineCount: () => number;
        getChangedTick: () => number;
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: getLength returns number
function test_buffer_get_length() {
    const len = vim.buffer.getLength();
    vim.test.assert(typeof len === 'number', 'getLength should return a number');
    vim.test.assert(len >= 0, 'getLength should return non-negative');
    vim.test.pass('test_buffer_get_length');
}

// Test 2: getLineCount returns number
function test_buffer_get_line_count() {
    const count = vim.buffer.getLineCount();
    vim.test.assert(typeof count === 'number', 'getLineCount should return a number');
    vim.test.assert(count >= 0, 'getLineCount should return non-negative');
    vim.test.pass('test_buffer_get_line_count');
}

// Test 3: getChangedTick returns number (version tracking)
function test_buffer_get_changed_tick() {
    const tick = vim.buffer.getChangedTick();
    vim.test.assert(typeof tick === 'number', 'getChangedTick should return a number');
    vim.test.assert(tick >= 0, 'getChangedTick should return non-negative');
    vim.test.pass('test_buffer_get_changed_tick');
}

// Test 4: getContent returns ArrayBuffer
function test_buffer_get_content() {
    const content = vim.buffer.getContent();
    vim.test.assert(content instanceof ArrayBuffer, 'getContent should return ArrayBuffer');
    vim.test.pass('test_buffer_get_content');
}

// Test 5: getLineContent returns ArrayBuffer for valid line
function test_buffer_get_line_content() {
    const lineCount = vim.buffer.getLineCount();
    if (lineCount > 0) {
        const line = vim.buffer.getLineContent(0);
        vim.test.assert(line instanceof ArrayBuffer, 'getLineContent should return ArrayBuffer');
    }
    vim.test.pass('test_buffer_get_line_content');
}

// Run all tests
function runTests() {
    test_buffer_get_length();
    test_buffer_get_line_count();
    test_buffer_get_changed_tick();
    test_buffer_get_content();
    test_buffer_get_line_content();
}

runTests();
