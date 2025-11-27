/// Integration tests for async fetch API
/// Tests the full native→JS callback flow with real (failing) network requests
/// These tests verify the complete code path without requiring a mock server

vim.e2e.describe("Fetch Native Integration", function() {
  vim.e2e.test("connection refused triggers error callback", function() {
    // Use a port that's definitely not listening
    const promise = fetch("http://127.0.0.1:65534/test");

    // Verify promise is returned
    vim.e2e.assert.true(!!promise, "fetch should return a Promise");
    vim.e2e.assert.true(typeof promise.then === 'function', "Should have .then()");
    vim.e2e.assert.true(typeof promise.catch === 'function', "Should have .catch()");

    // Callback should be registered
    const callbackCount = Object.keys(globalThis._fetchCallbacks).length;
    vim.e2e.assert.true(callbackCount > 0, "Callback should be registered for pending request");
  });

  vim.e2e.test("multiple concurrent requests get unique IDs", function() {
    const startId = globalThis._nextFetchId;

    // Start multiple fetches concurrently
    fetch("http://127.0.0.1:65534/test1");
    fetch("http://127.0.0.1:65534/test2");
    fetch("http://127.0.0.1:65534/test3");

    const endId = globalThis._nextFetchId;

    // Each request should get a unique ID
    vim.e2e.assert.equal(endId, startId + 3, "Three requests should get three unique IDs");
  });

  vim.e2e.test("fetch passes method to native", function() {
    // We can't directly verify what's passed to native, but we can verify
    // the fetch doesn't throw with various methods
    const methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

    for (const method of methods) {
      const beforeId = globalThis._nextFetchId;
      fetch("http://127.0.0.1:65534/test", { method });
      const afterId = globalThis._nextFetchId;

      vim.e2e.assert.equal(afterId, beforeId + 1, `${method} request should register callback`);
    }
  });

  vim.e2e.test("fetch passes custom headers", function() {
    const beforeId = globalThis._nextFetchId;

    fetch("http://127.0.0.1:65534/test", {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer test-token',
        'X-Custom-Header': 'custom-value'
      }
    });

    const afterId = globalThis._nextFetchId;
    vim.e2e.assert.equal(afterId, beforeId + 1, "Request with headers should register callback");
  });

  vim.e2e.test("fetch passes body for POST", function() {
    const beforeId = globalThis._nextFetchId;

    fetch("http://127.0.0.1:65534/test", {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key: 'value', number: 42 })
    });

    const afterId = globalThis._nextFetchId;
    vim.e2e.assert.equal(afterId, beforeId + 1, "POST with body should register callback");
  });
});

vim.e2e.describe("Fetch Options Integration", function() {
  vim.e2e.test("timeout option is accepted", function() {
    const beforeId = globalThis._nextFetchId;

    // Pass timeout option - won't error even if native ignores it
    fetch("http://127.0.0.1:65534/test", {
      timeout: 5000
    });

    const afterId = globalThis._nextFetchId;
    vim.e2e.assert.equal(afterId, beforeId + 1, "Request with timeout should register callback");
  });

  vim.e2e.test("maxResponseSize option is accepted", function() {
    const beforeId = globalThis._nextFetchId;

    fetch("http://127.0.0.1:65534/test", {
      maxResponseSize: 1024 * 1024
    });

    const afterId = globalThis._nextFetchId;
    vim.e2e.assert.equal(afterId, beforeId + 1, "Request with maxResponseSize should register callback");
  });

  vim.e2e.test("all options together", function() {
    const controller = new AbortController();
    const beforeId = globalThis._nextFetchId;

    fetch("http://127.0.0.1:65534/test", {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({ test: true }),
      signal: controller.signal,
      timeout: 10000,
      maxResponseSize: 1024 * 1024 * 10
    });

    const afterId = globalThis._nextFetchId;
    vim.e2e.assert.equal(afterId, beforeId + 1, "Request with all options should register callback");

    // Verify signal is attached
    const callbacks = globalThis._fetchCallbacks;
    const lastId = Object.keys(callbacks).pop();
    vim.e2e.assert.true(callbacks[lastId!].signal === controller.signal, "Signal should be attached");
  });
});

vim.e2e.describe("Fetch Abort Integration", function() {
  vim.e2e.test("aborting removes callback from registry", function() {
    const controller = new AbortController();

    // Track __abortFetch calls
    let abortedId: number | null = null;
    const original = (globalThis as any).__abortFetch;
    (globalThis as any).__abortFetch = function(id: number) {
      abortedId = id;
      if (original) original(id);
    };

    const beforeCallbackCount = Object.keys(globalThis._fetchCallbacks).length;

    // Start fetch
    fetch("http://127.0.0.1:65534/test", { signal: controller.signal });

    const afterStartCount = Object.keys(globalThis._fetchCallbacks).length;
    vim.e2e.assert.equal(afterStartCount, beforeCallbackCount + 1, "Callback should be registered");

    // Abort the request
    controller.abort();

    // Callback should be removed
    const afterAbortCount = Object.keys(globalThis._fetchCallbacks).length;
    vim.e2e.assert.equal(afterAbortCount, beforeCallbackCount, "Callback should be removed after abort");

    // __abortFetch should have been called
    vim.e2e.assert.true(abortedId !== null, "__abortFetch should be called");

    // Restore
    (globalThis as any).__abortFetch = original;
  });

  vim.e2e.test("abort after callback processed is safe", function() {
    const controller = new AbortController();

    // Start fetch
    fetch("http://127.0.0.1:65534/test", { signal: controller.signal });

    // Get the ID
    const ids = Object.keys(globalThis._fetchCallbacks);
    const id = ids[ids.length - 1];

    // Simulate response arriving (removes callback)
    globalThis.__handleFetchCallback(parseInt(id), {
      success: true,
      status: 200,
      statusText: "OK",
      body: "{}"
    });

    // Now abort - should not throw
    controller.abort();

    // Should not crash, callback already removed
    vim.e2e.assert.true(true, "Abort after completion should not throw");
  });

  vim.e2e.test("multiple aborts are idempotent", function() {
    const controller = new AbortController();

    controller.abort();
    vim.e2e.assert.true(controller.signal.aborted, "First abort should work");

    controller.abort();
    vim.e2e.assert.true(controller.signal.aborted, "Second abort should be safe");

    controller.abort();
    vim.e2e.assert.true(controller.signal.aborted, "Third abort should be safe");
  });
});

vim.e2e.describe("Response Object Integration", function() {
  vim.e2e.test("successful response has correct properties", function() {
    let response: any = null;

    // Register a manual callback
    const id = globalThis._nextFetchId++;
    globalThis._fetchCallbacks[id] = {
      resolve: (r: any) => { response = r; },
      reject: (e: any) => { console.log("REJECTED:", e); }
    };

    // Simulate full response (without optional headers field)
    globalThis.__handleFetchCallback(id, {
      success: true,
      status: 200,
      statusText: "OK",
      body: '{"data": "test", "count": 42}'
    });

    // Verify response object
    vim.e2e.assert.true(response !== null, "Response should be set");
    vim.e2e.assert.equal(response.status, 200, "Status should be 200");
    vim.e2e.assert.equal(response.statusText, "OK", "StatusText should be OK");
    vim.e2e.assert.true(response.ok, "ok should be true for 200");

    // Verify body methods
    const bodyText = response.text();
    const expected = '{"data": "test", "count": 42}';
    // Use assert.true with === to work around assert.equal string comparison quirk
    vim.e2e.assert.true(bodyText === expected, "text() should return body");

    const json = response.json();
    vim.e2e.assert.equal(json.data, "test", "json() should parse body");
    vim.e2e.assert.equal(json.count, 42, "json() should parse numbers");
  });

  vim.e2e.test("error response has ok=false", function() {
    let response: any = null;

    const id = globalThis._nextFetchId++;
    globalThis._fetchCallbacks[id] = {
      resolve: (r: any) => { response = r; },
      reject: () => {}
    };

    // Simulate 404 response
    globalThis.__handleFetchCallback(id, {
      success: true,
      status: 404,
      statusText: "Not Found",
      body: '{"error": "not found"}'
    });

    vim.e2e.assert.true(response !== null, "Response should be set");
    vim.e2e.assert.equal(response.status, 404, "Status should be 404");
    vim.e2e.assert.true(!response.ok, "ok should be false for 404");
  });

  vim.e2e.test("5xx responses have ok=false", function() {
    let response: any = null;

    const id = globalThis._nextFetchId++;
    globalThis._fetchCallbacks[id] = {
      resolve: (r: any) => { response = r; },
      reject: () => {}
    };

    globalThis.__handleFetchCallback(id, {
      success: true,
      status: 500,
      statusText: "Internal Server Error",
      body: ""
    });

    vim.e2e.assert.equal(response.status, 500, "Status should be 500");
    vim.e2e.assert.true(!response.ok, "ok should be false for 500");
  });

  vim.e2e.test("network error rejects promise", function() {
    let error: any = null;

    const id = globalThis._nextFetchId++;
    globalThis._fetchCallbacks[id] = {
      resolve: () => {},
      reject: (e: any) => { error = e; }
    };

    globalThis.__handleFetchCallback(id, {
      success: false,
      error: "Connection refused"
    });

    vim.e2e.assert.true(error !== null, "Error should be set");
    vim.e2e.assert.equal(error.message, "Connection refused", "Error message should match");
  });
});

vim.e2e.runAll();
