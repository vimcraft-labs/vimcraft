// E2E tests for process.spawn() - async subprocess with stdio
//
// Tests the libuv-based async subprocess API for persistent processes
// with bidirectional stdio communication (e.g., for LSP servers).
vim.e2e.describe("process.spawn", function () {
    vim.e2e.test("spawns process and receives stdout", function () {
        let output = "";
        let exitCode = null;
        const proc = process.spawn("echo", ["hello async"]);
        proc.onStdout((data) => {
            output += data;
        });
        proc.onExit((code) => {
            exitCode = code;
        });
        // Wait for process to complete
        vim.e2e.wait(100);
        vim.e2e.assert.true(output.includes("hello async"), "stdout should contain 'hello async'");
        vim.e2e.assert.equal(exitCode, 0);
    });
    vim.e2e.test("spawns process and receives stderr", function () {
        let stderr = "";
        let exitCode = null;
        // Use sh -c to write to stderr
        const proc = process.spawn("sh", ["-c", "echo error >&2"]);
        proc.onStderr((data) => {
            stderr += data;
        });
        proc.onExit((code) => {
            exitCode = code;
        });
        vim.e2e.wait(100);
        vim.e2e.assert.true(stderr.includes("error"), "stderr should contain 'error'");
        vim.e2e.assert.equal(exitCode, 0);
    });
    vim.e2e.test("stdin.write sends data to process", function () {
        let output = "";
        let exitCode = null;
        // Use cat to echo stdin back to stdout
        const proc = process.spawn("cat");
        proc.onStdout((data) => {
            output += data;
        });
        proc.onExit((code) => {
            exitCode = code;
        });
        // Write to stdin
        proc.stdin.write("test input\n");
        // Give it time to process
        vim.e2e.wait(50);
        // Close stdin to let cat exit
        proc.kill("SIGTERM");
        vim.e2e.wait(100);
        vim.e2e.assert.true(output.includes("test input"), "stdout should contain stdin data");
    });
    vim.e2e.test("kill terminates process with signal", function () {
        let exitSignal = null;
        let exited = false;
        // Start a long-running process
        const proc = process.spawn("sleep", ["10"]);
        proc.onExit((code, signal) => {
            exited = true;
            exitSignal = signal;
        });
        // Wait for process to start
        vim.e2e.wait(50);
        // Kill it
        const killed = proc.kill("SIGKILL");
        vim.e2e.assert.true(killed, "kill() should return true");
        vim.e2e.wait(100);
        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(exitSignal, "SIGKILL");
    });
    vim.e2e.test("kill with default signal (SIGTERM)", function () {
        let exited = false;
        const proc = process.spawn("sleep", ["10"]);
        proc.onExit(() => {
            exited = true;
        });
        vim.e2e.wait(50);
        // Kill with default signal
        proc.kill();
        vim.e2e.wait(100);
        vim.e2e.assert.true(exited, "process should have exited");
    });
    vim.e2e.test("process.pid is set", function () {
        const proc = process.spawn("sleep", ["1"]);
        // pid should be set immediately after spawn
        vim.e2e.assert.true(proc.pid > 0, "pid should be positive");
        proc.kill();
        vim.e2e.wait(100);
    });
    vim.e2e.test("handles non-existent command gracefully", function () {
        let threw = false;
        let errorMessage = "";
        try {
            process.spawn("/nonexistent/command/12345");
        }
        catch (e) {
            threw = true;
            errorMessage = (e === null || e === void 0 ? void 0 : e.message) || String(e);
        }
        // Should throw when command doesn't exist
        vim.e2e.assert.true(threw, "should throw for non-existent command");
        vim.e2e.assert.true(errorMessage.includes("spawn") || errorMessage.includes("process"), "error message should mention spawn or process");
    });
    vim.e2e.test("multiple processes can run concurrently", function () {
        let output1 = "";
        let output2 = "";
        let exits = 0;
        const proc1 = process.spawn("echo", ["proc1"]);
        const proc2 = process.spawn("echo", ["proc2"]);
        proc1.onStdout((data) => { output1 += data; });
        proc2.onStdout((data) => { output2 += data; });
        proc1.onExit(() => { exits++; });
        proc2.onExit(() => { exits++; });
        vim.e2e.wait(200);
        vim.e2e.assert.true(output1.includes("proc1"), "proc1 output");
        vim.e2e.assert.true(output2.includes("proc2"), "proc2 output");
        vim.e2e.assert.equal(exits, 2);
    });
    vim.e2e.test("cwd option changes working directory", function () {
        let output = "";
        const proc = process.spawn("pwd", [], { cwd: "/tmp" });
        proc.onStdout((data) => {
            output += data;
        });
        vim.e2e.wait(100);
        // On macOS, /tmp may resolve to /private/tmp
        vim.e2e.assert.true(output.includes("/tmp") || output.includes("/private/tmp"), "cwd should be /tmp");
    });
    vim.e2e.test("bidirectional communication works", function () {
        let responses = [];
        let exitCode = null;
        // Use a simple shell script that echoes with prefix
        const proc = process.spawn("sh", ["-c", "while read line; do echo \"got: $line\"; done"]);
        proc.onStdout((data) => {
            responses.push(data.trim());
        });
        proc.onExit((code) => {
            exitCode = code;
        });
        // Send multiple lines
        proc.stdin.write("hello\n");
        vim.e2e.wait(50);
        proc.stdin.write("world\n");
        vim.e2e.wait(50);
        // Terminate
        proc.kill();
        vim.e2e.wait(100);
        // Check we got responses
        vim.e2e.assert.true(responses.length >= 2, "should receive at least 2 responses");
        vim.e2e.assert.true(responses.some(r => r.includes("got: hello")), "should get hello response");
        vim.e2e.assert.true(responses.some(r => r.includes("got: world")), "should get world response");
    });
});
vim.e2e.runAll();
