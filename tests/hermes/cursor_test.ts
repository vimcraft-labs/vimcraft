// Cursor API Tests - TypeScript
// Tests vim.cursor.* API with full Hermes runtime
//
// Build: zig build hermes-tests

declare const vim: {
    cursor: {
        getPosition: () => { row: number; col: number };
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: getPosition returns object with row and col
function test_cursor_get_position() {
    const pos = vim.cursor.getPosition();
    vim.test.assert(typeof pos === 'object', 'getPosition should return an object');
    vim.test.assert(typeof pos.row === 'number', 'position.row should be a number');
    vim.test.assert(typeof pos.col === 'number', 'position.col should be a number');
    vim.test.pass('test_cursor_get_position');
}

// Test 2: Position values are non-negative
function test_cursor_position_non_negative() {
    const pos = vim.cursor.getPosition();
    vim.test.assert(pos.row >= 0, 'position.row should be non-negative');
    vim.test.assert(pos.col >= 0, 'position.col should be non-negative');
    vim.test.pass('test_cursor_position_non_negative');
}

// Test 3: getPosition is consistent (idempotent)
function test_cursor_position_consistent() {
    const pos1 = vim.cursor.getPosition();
    const pos2 = vim.cursor.getPosition();
    vim.test.assertEqual(pos1.row, pos2.row, 'Consecutive getPosition calls should return same row');
    vim.test.assertEqual(pos1.col, pos2.col, 'Consecutive getPosition calls should return same col');
    vim.test.pass('test_cursor_position_consistent');
}

// Run all tests
function runTests() {
    test_cursor_get_position();
    test_cursor_position_non_negative();
    test_cursor_position_consistent();
}

runTests();
