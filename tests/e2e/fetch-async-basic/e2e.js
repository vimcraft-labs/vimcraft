/// Test async fetch basic setup
/// Verifies fetch() returns a Promise and callback registration works
/// NOTE: Tests callback mechanism without actual network requests
vim.e2e.describe("Async Fetch Callbacks", function () {
    vim.e2e.test("fetch returns a Promise object", function () {
        // Use a URL that won't actually connect (fast fail)
        const result = fetch("http://localhost:65535/nonexistent");
        // Check it's a Promise (has then method)
        vim.e2e.assert.true(!!result, "fetch should return something");
        vim.e2e.assert.true(typeof result.then === 'function', "fetch should return a Promise with .then()");
        vim.e2e.assert.true(typeof result.catch === 'function', "fetch should return a Promise with .catch()");
    });
    vim.e2e.test("fetch callback is registered with unique ID", function () {
        const beforeCount = globalThis._nextFetchId;
        // Start two fetches (won't connect, just tests registration)
        fetch("http://localhost:65535/test1");
        fetch("http://localhost:65535/test2");
        const afterCount = globalThis._nextFetchId;
        // Each fetch should increment the ID counter
        vim.e2e.assert.equal(afterCount, beforeCount + 2, "Each fetch should get unique ID");
        // Callbacks should be registered
        const callbackCount = Object.keys(globalThis._fetchCallbacks).length;
        vim.e2e.assert.true(callbackCount >= 2, "Multiple callbacks should be registered");
    });
    vim.e2e.test("__handleFetchCallback processes response correctly", function () {
        // Manually test the callback handler
        let resolved = false;
        let resolvedResponse = null;
        // Create a fake fetch promise by registering callback directly
        const id = globalThis._nextFetchId++;
        globalThis._fetchCallbacks[id] = {
            resolve: (response) => {
                resolved = true;
                resolvedResponse = response;
            },
            reject: () => { }
        };
        // Simulate native code calling the callback with a successful response
        globalThis.__handleFetchCallback(id, {
            success: true,
            status: 200,
            statusText: "OK",
            body: '{"test": "data"}'
        });
        // Verify the callback was processed
        vim.e2e.assert.true(resolved, "Callback should have been called");
        vim.e2e.assert.equal(resolvedResponse.status, 200, "Status should be 200");
        vim.e2e.assert.true(resolvedResponse.ok, "Response.ok should be true");
        vim.e2e.assert.equal(resolvedResponse.statusText, "OK", "Status text should be OK");
        vim.e2e.assert.equal(resolvedResponse.text(), '{"test": "data"}', "Body text should match");
        // Verify JSON parsing works
        const json = resolvedResponse.json();
        vim.e2e.assert.equal(json.test, "data", "JSON parsing should work");
        // Verify callback was cleaned up
        vim.e2e.assert.true(globalThis._fetchCallbacks[id] === undefined, "Callback should be cleaned up");
    });
    vim.e2e.test("__handleFetchCallback handles errors correctly", function () {
        let rejected = false;
        let errorMessage = "";
        const id = globalThis._nextFetchId++;
        globalThis._fetchCallbacks[id] = {
            resolve: () => { },
            reject: (err) => {
                rejected = true;
                errorMessage = err.message;
            }
        };
        // Simulate error response
        globalThis.__handleFetchCallback(id, {
            success: false,
            error: "Network error"
        });
        vim.e2e.assert.true(rejected, "Error callback should have been called");
        vim.e2e.assert.equal(errorMessage, "Network error", "Error message should match");
        vim.e2e.assert.true(globalThis._fetchCallbacks[id] === undefined, "Callback should be cleaned up");
    });
});
vim.e2e.describe("AbortController", function () {
    vim.e2e.test("AbortController is globally available", function () {
        vim.e2e.assert.true(typeof AbortController === 'function', "AbortController should be available");
        vim.e2e.assert.true(typeof AbortSignal === 'function', "AbortSignal should be available");
    });
    vim.e2e.test("AbortController creates signal", function () {
        const controller = new AbortController();
        vim.e2e.assert.true(!!controller.signal, "Controller should have signal");
        vim.e2e.assert.true(controller.signal.aborted === false, "Signal should not be aborted initially");
    });
    vim.e2e.test("AbortController.abort() sets aborted flag", function () {
        const controller = new AbortController();
        controller.abort();
        vim.e2e.assert.true(controller.signal.aborted === true, "Signal should be aborted after abort()");
    });
    vim.e2e.test("AbortSignal fires abort event", function () {
        const controller = new AbortController();
        let eventFired = false;
        controller.signal.addEventListener('abort', function () {
            eventFired = true;
        });
        controller.abort();
        vim.e2e.assert.true(eventFired, "Abort event should fire");
    });
    vim.e2e.test("AbortSignal stores custom reason", function () {
        const controller = new AbortController();
        const customError = new Error("Custom abort reason");
        controller.abort(customError);
        vim.e2e.assert.true(controller.signal.aborted, "Signal should be aborted");
        // The reason is stored correctly
        vim.e2e.assert.true(controller.signal.reason !== undefined, "Reason should be stored");
        vim.e2e.assert.equal(controller.signal.reason.message, "Custom abort reason", "Reason message should match");
    });
    vim.e2e.test("AbortSignal default reason is DOMException", function () {
        const controller = new AbortController();
        controller.abort();
        vim.e2e.assert.true(controller.signal.reason !== undefined, "Reason should be set");
        vim.e2e.assert.equal(controller.signal.reason.name, "AbortError", "Default reason should be AbortError");
    });
});
vim.e2e.describe("Fetch with AbortController", function () {
    vim.e2e.test("fetch registers callback with signal", function () {
        const controller = new AbortController();
        // Start a fetch that won't connect
        fetch("http://localhost:65535/test", { signal: controller.signal });
        // Find the callback (most recent one)
        const callbacks = globalThis._fetchCallbacks;
        const ids = Object.keys(callbacks);
        vim.e2e.assert.true(ids.length > 0, "Callback should be registered");
        // The callback should have the signal attached
        const lastId = ids[ids.length - 1];
        vim.e2e.assert.true(callbacks[lastId].signal === controller.signal, "Signal should be attached to callback");
    });
    vim.e2e.test("abort listener calls native __abortFetch", function () {
        // Test that aborting triggers the native abort function
        const controller = new AbortController();
        let nativeAbortCalled = false;
        const originalAbort = globalThis.__abortFetch;
        // Mock __abortFetch to verify it's called
        if (typeof __abortFetch !== 'undefined') {
            // Store original if exists
            globalThis.__abortFetch_original = __abortFetch;
        }
        globalThis.__abortFetch = function (id) {
            nativeAbortCalled = true;
        };
        // Start a fetch
        fetch("http://localhost:65535/test", { signal: controller.signal });
        // Abort it
        controller.abort();
        // Verify native abort was called
        vim.e2e.assert.true(nativeAbortCalled, "__abortFetch should be called when aborting");
        // Restore original
        if (globalThis.__abortFetch_original) {
            globalThis.__abortFetch = globalThis.__abortFetch_original;
        }
    });
    vim.e2e.test("fetch with already aborted signal does not register callback", function () {
        const controller = new AbortController();
        controller.abort(); // Abort first
        const beforeCount = Object.keys(globalThis._fetchCallbacks).length;
        // Try to fetch with already aborted signal - Promise rejects immediately
        // but callback shouldn't be registered
        fetch("http://localhost:65535/test", { signal: controller.signal });
        const afterCount = Object.keys(globalThis._fetchCallbacks).length;
        // No new callback should be registered (immediate rejection, not async)
        vim.e2e.assert.equal(afterCount, beforeCount, "No callback should be registered for already-aborted signal");
    });
});
vim.e2e.runAll();
