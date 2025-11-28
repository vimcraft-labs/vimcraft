/// Test real HTTP fetch with actual network request
/// This tests the complete async fetch flow in the E2E runner
vim.e2e.describe("Real HTTP Fetch", function () {
    vim.e2e.test("fetch returns response from real server", function () {
        let result = null;
        let error = null;
        console.log("Starting fetch...");
        console.log("Callbacks before:", Object.keys(globalThis._fetchCallbacks).length);
        // Make a real HTTP request to a reliable test endpoint
        fetch("https://api.github.com/zen")
            .then((response) => {
            result = response;
            console.log("Fetch succeeded:", response.status);
        })
            .catch((err) => {
            error = err;
            console.log("Fetch failed:", err.message || err);
        });
        console.log("Callbacks after fetch():", Object.keys(globalThis._fetchCallbacks).length);
        // Wait for the async result (E2E runner processes queue)
        // Use longer timeout for network reliability
        vim.e2e.wait(5000);
        console.log("After wait - result:", result !== null);
        console.log("After wait - error:", error !== null);
        console.log("Callbacks remaining:", Object.keys(globalThis._fetchCallbacks).length);
        // Check result - we test that Promise resolution works
        console.log("result object:", JSON.stringify(result));
        console.log("result !== null:", result !== null);
        // Use assert.equal for clearer failure message
        vim.e2e.assert.equal(result !== null, true, "Response should be received");
    });
});
vim.e2e.runAll();
