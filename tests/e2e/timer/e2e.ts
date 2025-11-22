// Timer API E2E Tests
// Tests setTimeout/setInterval with real Hermes runtime

vim.e2e.describe("setTimeout API", function() {
    vim.e2e.test("setTimeout returns timer ID", function() {
        const id = setTimeout(function() {}, 1000);
        vim.e2e.assert.true(typeof id === 'number', 'setTimeout should return a number ID');
        vim.e2e.assert.true(id > 0, 'Timer ID should be positive');

        // Clear to prevent execution
        clearTimeout(id);
    });

    vim.e2e.test("clearTimeout accepts timer ID", function() {
        const id = setTimeout(function() {}, 1000);

        // Should not throw
        clearTimeout(id);

        // Clearing again should be idempotent
        clearTimeout(id);

        vim.e2e.assert.true(true, "clearTimeout completed without error");
    });
});

vim.e2e.describe("setInterval API", function() {
    vim.e2e.test("setInterval returns timer ID", function() {
        const id = setInterval(function() {}, 1000);
        vim.e2e.assert.true(typeof id === 'number', 'setInterval should return a number ID');
        vim.e2e.assert.true(id > 0, 'Timer ID should be positive');

        // Clear to prevent repeated execution
        clearInterval(id);
    });

    vim.e2e.test("clearInterval accepts timer ID", function() {
        const id = setInterval(function() {}, 1000);

        // Should not throw
        clearInterval(id);

        // Clearing again should be idempotent
        clearInterval(id);

        vim.e2e.assert.true(true, "clearInterval completed without error");
    });
});

vim.e2e.describe("Timer Unique IDs", function() {
    vim.e2e.test("multiple timers have unique IDs", function() {
        const id1 = setTimeout(function() {}, 1000);
        const id2 = setTimeout(function() {}, 1000);
        const id3 = setInterval(function() {}, 1000);

        vim.e2e.assert.true(id1 !== id2, 'Timer IDs should be unique');
        vim.e2e.assert.true(id2 !== id3, 'Timer IDs should be unique across setTimeout/setInterval');

        clearTimeout(id1);
        clearTimeout(id2);
        clearInterval(id3);
    });
});

vim.e2e.runAll();
