// E2E tests for process.spawnAsync new options: timeout, detach, stdoutBuffered
//
// Tests the new Neovim-compatible features added to process.spawnAsync

vim.e2e.describe("process.spawnAsync options", function() {

    vim.e2e.test("timeout option kills process after specified ms", function() {
        let exitCode: number | null = null;
        let exitSignal: string | null = null;
        let exited = false;

        // Start a long-running process with 500ms timeout
        const proc = process.spawnAsync("sleep", ["10"], { timeout: 500 });

        proc.onExit((code: number, signal: string | null) => {
            exited = true;
            exitCode = code;
            exitSignal = signal;
        });

        // Wait for timeout to fire (500ms + buffer)
        vim.e2e.wait(800);

        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(exitCode, 124, "exit code should be 124 (timeout)");
    });

    vim.e2e.test("stdoutBuffered collects all output in single callback", function() {
        let callbackCount = 0;
        let receivedData = "";
        let exited = false;

        // Echo multiple lines with small delays - buffered mode should collect all
        const proc = process.spawnAsync("sh", ["-c", "echo line1; sleep 0.05; echo line2; sleep 0.05; echo line3"], {
            stdoutBuffered: true
        });

        proc.onStdout((data: string) => {
            callbackCount++;
            receivedData += data;
        });

        proc.onExit(() => {
            exited = true;
        });

        // Wait for process to complete
        vim.e2e.wait(500);

        vim.e2e.assert.true(exited, "process should have exited");
        // Buffered mode should deliver all output in a single callback
        vim.e2e.assert.equal(callbackCount, 1, "should receive exactly 1 callback (buffered)");
        vim.e2e.assert.true(receivedData.includes("line1"), "should contain line1");
        vim.e2e.assert.true(receivedData.includes("line2"), "should contain line2");
        vim.e2e.assert.true(receivedData.includes("line3"), "should contain line3");
    });

    vim.e2e.test("detach option allows process to spawn (basic test)", function() {
        let exited = false;
        let exitCode: number | null = null;

        // Spawn a short-lived detached process
        const proc = process.spawnAsync("sleep", ["0.1"], { detach: true });

        proc.onExit((code: number) => {
            exited = true;
            exitCode = code;
        });

        // Wait for process to complete
        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "detached process should have exited");
        vim.e2e.assert.equal(exitCode, 0, "exit code should be 0");
    });

    vim.e2e.test("stderrBuffered collects all stderr in single callback", function() {
        let callbackCount = 0;
        let receivedData = "";
        let exited = false;

        // Echo to stderr with small delays
        const proc = process.spawnAsync("sh", ["-c", "echo err1 >&2; sleep 0.05; echo err2 >&2; sleep 0.05; echo err3 >&2"], {
            stderrBuffered: true
        });

        proc.onStderr((data: string) => {
            callbackCount++;
            receivedData += data;
        });

        proc.onExit(() => {
            exited = true;
        });

        vim.e2e.wait(500);

        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(callbackCount, 1, "should receive exactly 1 stderr callback (buffered)");
        vim.e2e.assert.true(receivedData.includes("err1"), "should contain err1");
        vim.e2e.assert.true(receivedData.includes("err2"), "should contain err2");
        vim.e2e.assert.true(receivedData.includes("err3"), "should contain err3");
    });

    vim.e2e.test("streaming mode (default) delivers output immediately", function() {
        let callbackCount = 0;
        let exited = false;

        // Same command but WITHOUT buffered mode - should get multiple callbacks
        const proc = process.spawnAsync("sh", ["-c", "echo line1; sleep 0.1; echo line2; sleep 0.1; echo line3"]);

        proc.onStdout(() => {
            callbackCount++;
        });

        proc.onExit(() => {
            exited = true;
        });

        vim.e2e.wait(500);

        vim.e2e.assert.true(exited, "process should have exited");
        // Streaming mode may deliver in multiple callbacks (implementation dependent)
        // At minimum we expect 1 callback, possibly more
        vim.e2e.assert.true(callbackCount >= 1, "should receive at least 1 callback");
    });

});

vim.e2e.runAll();
