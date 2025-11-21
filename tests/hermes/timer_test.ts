// Timer API Tests - TypeScript
// Tests setTimeout/setInterval with full Hermes runtime
//
// Build: zig build hermes-tests

declare function setTimeout(callback: () => void, delay: number): number;
declare function clearTimeout(id: number): void;
declare function setInterval(callback: () => void, delay: number): number;
declare function clearInterval(id: number): void;

declare const vim: {
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Test 1: setTimeout returns timer ID
function test_setTimeout_returns_id() {
    const id = setTimeout(() => {}, 1000);
    vim.test.assert(typeof id === 'number', 'setTimeout should return a number ID');
    vim.test.assert(id > 0, 'Timer ID should be positive');

    // Clear to prevent execution
    clearTimeout(id);

    vim.test.pass('test_setTimeout_returns_id');
}

// Test 2: clearTimeout accepts timer ID
function test_clearTimeout() {
    const id = setTimeout(() => {}, 1000);

    // Should not throw
    clearTimeout(id);

    // Clearing again should be idempotent
    clearTimeout(id);

    vim.test.pass('test_clearTimeout');
}

// Test 3: setInterval returns timer ID
function test_setInterval_returns_id() {
    const id = setInterval(() => {}, 1000);
    vim.test.assert(typeof id === 'number', 'setInterval should return a number ID');
    vim.test.assert(id > 0, 'Timer ID should be positive');

    // Clear to prevent repeated execution
    clearInterval(id);

    vim.test.pass('test_setInterval_returns_id');
}

// Test 4: clearInterval accepts timer ID
function test_clearInterval() {
    const id = setInterval(() => {}, 1000);

    // Should not throw
    clearInterval(id);

    // Clearing again should be idempotent
    clearInterval(id);

    vim.test.pass('test_clearInterval');
}

// Test 5: Multiple timers have unique IDs
function test_timer_unique_ids() {
    const id1 = setTimeout(() => {}, 1000);
    const id2 = setTimeout(() => {}, 1000);
    const id3 = setInterval(() => {}, 1000);

    vim.test.assert(id1 !== id2, 'Timer IDs should be unique');
    vim.test.assert(id2 !== id3, 'Timer IDs should be unique across setTimeout/setInterval');

    clearTimeout(id1);
    clearTimeout(id2);
    clearInterval(id3);

    vim.test.pass('test_timer_unique_ids');
}

// Run all tests
function runTests() {
    test_setTimeout_returns_id();
    test_clearTimeout();
    test_setInterval_returns_id();
    test_clearInterval();
    test_timer_unique_ids();
}

runTests();
