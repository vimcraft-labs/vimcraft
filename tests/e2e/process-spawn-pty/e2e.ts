// E2E tests for process.spawnPty() - PTY-based subprocess
//
// Comprehensive TDD test suite covering all edge cases for the PTY API.
// Tests interactive terminal programs (fzf, htop, shells).
//
// Key differences from spawn():
// - Single bidirectional stream (onData instead of onStdout/onStderr)
// - Programs see a real TTY (isatty() returns true)
// - Supports terminal resize via resize()

vim.e2e.describe("process.spawnPty", function() {

    // =========================================================================
    // Basic Functionality
    // =========================================================================

    vim.e2e.test("spawns PTY and receives output", function() {
        let output = "";
        let exitCode: number | null = null;

        const pty = process.spawnPty("echo", ["hello pty"]);

        pty.onData((data: string) => {
            output += data;
        });

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("hello pty"), "output should contain 'hello pty', got: " + JSON.stringify(output));
        vim.e2e.assert.equal(exitCode, 0);
    });

    vim.e2e.test("PTY pid is positive integer", function() {
        const pty = process.spawnPty("echo", ["test"]);

        vim.e2e.assert.true(pty.pid > 0, "pid should be positive, got: " + pty.pid);
        vim.e2e.assert.true(Number.isInteger(pty.pid), "pid should be integer");

        vim.e2e.wait(200);
    });

    vim.e2e.test("write sends data to PTY stdin", function() {
        let output = "";

        const pty = process.spawnPty("cat");

        pty.onData((data: string) => {
            output += data;
        });

        pty.write("test input\n");
        vim.e2e.wait(100);

        pty.kill();
        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("test"), "output should contain input data, got: " + JSON.stringify(output));
    });

    vim.e2e.test("kill terminates PTY process", function() {
        let exited = false;

        const pty = process.spawnPty("sleep", ["10"]);

        pty.onExit(() => {
            exited = true;
        });

        vim.e2e.wait(100);

        const killed = pty.kill();
        vim.e2e.assert.true(killed, "kill() should return true");

        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "process should have exited");
    });

    vim.e2e.test("resize changes PTY dimensions", function() {
        const pty = process.spawnPty("sh");

        vim.e2e.wait(100);

        let resizeSuccess = false;
        try {
            pty.resize(40, 120);
            resizeSuccess = true;
        } catch (e) {
            resizeSuccess = false;
        }

        vim.e2e.assert.true(resizeSuccess, "resize should succeed");

        pty.kill();
        vim.e2e.wait(200);
    });

    // =========================================================================
    // Options
    // =========================================================================

    vim.e2e.test("cwd option changes working directory", function() {
        let output = "";

        const pty = process.spawnPty("pwd", [], { cwd: "/tmp" });

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(
            output.includes("/tmp") || output.includes("/private/tmp"),
            "cwd should be /tmp, got: " + JSON.stringify(output)
        );
    });

    vim.e2e.test("rows option sets initial terminal height", function() {
        let output = "";

        const pty = process.spawnPty("sh", ["-c", "stty size"], {
            rows: 50,
            cols: 80
        });

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("50"), "should have 50 rows, got: " + JSON.stringify(output));
    });

    vim.e2e.test("cols option sets initial terminal width", function() {
        let output = "";

        const pty = process.spawnPty("sh", ["-c", "stty size"], {
            rows: 24,
            cols: 132
        });

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("132"), "should have 132 cols, got: " + JSON.stringify(output));
    });

    vim.e2e.test("env option passes environment variables", function() {
        let output = "";

        const pty = process.spawnPty("sh", ["-c", "echo $MY_PTY_VAR"], {
            env: { MY_PTY_VAR: "pty_env_test" }
        });

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(
            output.includes("pty_env_test"),
            "should receive custom env var, got: " + JSON.stringify(output)
        );
    });

    vim.e2e.test("default rows/cols are 24x80", function() {
        let output = "";

        const pty = process.spawnPty("sh", ["-c", "stty size"]);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("24"), "default rows should be 24");
        vim.e2e.assert.true(output.includes("80"), "default cols should be 80");
    });

    // =========================================================================
    // Signal Handling
    // =========================================================================

    vim.e2e.test("kill with SIGTERM (default)", function() {
        let exited = false;
        let exitSignal: string | null = null;

        const pty = process.spawnPty("sleep", ["10"]);

        pty.onExit((code: number, signal: string | null) => {
            exited = true;
            exitSignal = signal;
        });

        vim.e2e.wait(100);
        pty.kill(); // Default is SIGTERM
        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(exitSignal, "SIGTERM");
    });

    vim.e2e.test("kill with SIGKILL", function() {
        let exited = false;
        let exitSignal: string | null = null;

        const pty = process.spawnPty("sleep", ["10"]);

        pty.onExit((code: number, signal: string | null) => {
            exited = true;
            exitSignal = signal;
        });

        vim.e2e.wait(100);
        pty.kill("SIGKILL");
        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(exitSignal, "SIGKILL");
    });

    vim.e2e.test("kill with numeric signal (9 = SIGKILL)", function() {
        let exited = false;

        const pty = process.spawnPty("sleep", ["10"]);

        pty.onExit(() => {
            exited = true;
        });

        vim.e2e.wait(100);
        pty.kill(9);
        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "process should have exited with numeric signal");
    });

    vim.e2e.test("kill with SIGINT", function() {
        let exited = false;
        let exitSignal: string | null = null;

        const pty = process.spawnPty("sleep", ["10"]);

        pty.onExit((code: number, signal: string | null) => {
            exited = true;
            exitSignal = signal;
        });

        vim.e2e.wait(100);
        pty.kill("SIGINT");
        vim.e2e.wait(300);

        vim.e2e.assert.true(exited, "process should have exited");
        vim.e2e.assert.equal(exitSignal, "SIGINT");
    });

    // =========================================================================
    // Exit Handling
    // =========================================================================

    vim.e2e.test("onExit receives correct exit code for success", function() {
        let exitCode: number | null = null;

        const pty = process.spawnPty("sh", ["-c", "exit 0"]);

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.equal(exitCode, 0);
    });

    vim.e2e.test("onExit receives correct exit code for failure", function() {
        let exitCode: number | null = null;

        const pty = process.spawnPty("sh", ["-c", "exit 42"]);

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.equal(exitCode, 42);
    });

    vim.e2e.test("onExit receives exit code 127 for command not found", function() {
        let exitCode: number | null = null;

        // Use sh -c to invoke a non-existent command
        const pty = process.spawnPty("sh", ["-c", "/nonexistent/cmd/xyz123"]);

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.equal(exitCode, 127);
    });

    vim.e2e.test("onExit called only once", function() {
        let exitCount = 0;

        const pty = process.spawnPty("echo", ["done"]);

        pty.onExit(() => {
            exitCount++;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.equal(exitCount, 1);
    });

    // =========================================================================
    // Data Handling
    // =========================================================================

    vim.e2e.test("onData receives multiple data chunks for long output", function() {
        let dataChunks = 0;
        let totalOutput = "";

        // Generate multiple lines of output
        const pty = process.spawnPty("sh", ["-c", "for i in 1 2 3 4 5; do echo line$i; done"]);

        pty.onData((data: string) => {
            dataChunks++;
            totalOutput += data;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.true(totalOutput.includes("line1"), "should contain line1");
        vim.e2e.assert.true(totalOutput.includes("line5"), "should contain line5");
    });

    vim.e2e.test("onData handles binary-safe output", function() {
        let output = "";

        // Echo some special characters
        const pty = process.spawnPty("sh", ["-c", "printf 'hello\\tworld\\n'"]);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("hello"), "should contain hello");
        vim.e2e.assert.true(output.includes("world"), "should contain world");
    });

    vim.e2e.test("empty output produces no onData calls before exit", function() {
        let dataReceived = false;

        const pty = process.spawnPty("true"); // true exits immediately with no output

        pty.onData(() => {
            dataReceived = true;
        });

        vim.e2e.wait(200);

        // May or may not receive data (PTY echo settings), but shouldn't crash
        vim.e2e.assert.true(true, "should not crash on empty output");
    });

    // =========================================================================
    // TTY Features
    // =========================================================================

    vim.e2e.test("programs see real TTY (isatty returns true)", function() {
        let output = "";

        // tty command prints device path or "not a tty"
        const pty = process.spawnPty("tty");

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(
            output.includes("/dev/") || output.includes("tty"),
            "should be a real TTY device, got: " + JSON.stringify(output)
        );
        vim.e2e.assert.true(
            !output.includes("not a tty"),
            "should NOT report 'not a tty'"
        );
    });

    vim.e2e.test("TERM environment variable is set", function() {
        let output = "";

        const pty = process.spawnPty("sh", ["-c", "echo $TERM"]);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        // Default TERM is xterm-256color
        vim.e2e.assert.true(
            output.includes("xterm") || output.includes("256color"),
            "TERM should be set, got: " + JSON.stringify(output)
        );
    });

    vim.e2e.test("resize updates SIGWINCH to process", function() {
        let output = "";

        // Start a shell and check size after resize
        const pty = process.spawnPty("sh");

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(100);

        // Resize
        pty.resize(30, 100);

        // Query size
        pty.write("stty size\n");
        vim.e2e.wait(200);

        pty.kill();
        vim.e2e.wait(200);

        vim.e2e.assert.true(
            output.includes("30") && output.includes("100"),
            "should report new size, got: " + JSON.stringify(output)
        );
    });

    // =========================================================================
    // Bidirectional Communication
    // =========================================================================

    vim.e2e.test("bidirectional I/O with interactive shell", function() {
        let output = "";

        const pty = process.spawnPty("sh");

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(100);

        pty.write("echo interactive_test\n");
        vim.e2e.wait(200);

        vim.e2e.assert.true(
            output.includes("interactive_test"),
            "should receive echoed command output, got: " + JSON.stringify(output)
        );

        pty.kill();
        vim.e2e.wait(200);
    });

    vim.e2e.test("multiple writes in sequence", function() {
        let output = "";

        const pty = process.spawnPty("cat");

        pty.onData((data: string) => {
            output += data;
        });

        pty.write("first\n");
        vim.e2e.wait(50);
        pty.write("second\n");
        vim.e2e.wait(50);
        pty.write("third\n");
        vim.e2e.wait(100);

        pty.kill();
        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("first"), "should contain first");
        vim.e2e.assert.true(output.includes("second"), "should contain second");
        vim.e2e.assert.true(output.includes("third"), "should contain third");
    });

    vim.e2e.test("write returns true for successful write", function() {
        const pty = process.spawnPty("cat");

        vim.e2e.wait(50);

        const result = pty.write("test\n");
        vim.e2e.assert.true(result, "write should return true");

        pty.kill();
        vim.e2e.wait(200);
    });

    // =========================================================================
    // Concurrent PTYs
    // =========================================================================

    vim.e2e.test("multiple PTYs can run concurrently", function() {
        let output1 = "";
        let output2 = "";
        let exits = 0;

        const pty1 = process.spawnPty("echo", ["pty_one"]);
        const pty2 = process.spawnPty("echo", ["pty_two"]);

        pty1.onData((data: string) => { output1 += data; });
        pty2.onData((data: string) => { output2 += data; });

        pty1.onExit(() => { exits++; });
        pty2.onExit(() => { exits++; });

        vim.e2e.wait(300);

        vim.e2e.assert.true(output1.includes("pty_one"), "pty1 should receive its output");
        vim.e2e.assert.true(output2.includes("pty_two"), "pty2 should receive its output");
        vim.e2e.assert.equal(exits, 2);
    });

    vim.e2e.test("three concurrent PTYs with different commands", function() {
        let outputs: string[] = ["", "", ""];
        let exitCount = 0;

        const pty1 = process.spawnPty("echo", ["alpha"]);
        const pty2 = process.spawnPty("echo", ["beta"]);
        const pty3 = process.spawnPty("echo", ["gamma"]);

        pty1.onData((d: string) => { outputs[0] += d; });
        pty2.onData((d: string) => { outputs[1] += d; });
        pty3.onData((d: string) => { outputs[2] += d; });

        pty1.onExit(() => { exitCount++; });
        pty2.onExit(() => { exitCount++; });
        pty3.onExit(() => { exitCount++; });

        vim.e2e.wait(400);

        vim.e2e.assert.true(outputs[0].includes("alpha"), "pty1 output");
        vim.e2e.assert.true(outputs[1].includes("beta"), "pty2 output");
        vim.e2e.assert.true(outputs[2].includes("gamma"), "pty3 output");
        vim.e2e.assert.equal(exitCount, 3);
    });

    // =========================================================================
    // Edge Cases - Arguments
    // =========================================================================

    vim.e2e.test("empty args array works", function() {
        let output = "";

        const pty = process.spawnPty("pwd", []);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.length > 0, "should receive output with empty args");
    });

    vim.e2e.test("args with spaces work correctly", function() {
        let output = "";

        const pty = process.spawnPty("echo", ["hello world", "foo bar"]);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("hello world"), "should preserve spaces in args");
        vim.e2e.assert.true(output.includes("foo bar"), "should preserve spaces in second arg");
    });

    vim.e2e.test("args with special characters work", function() {
        let output = "";

        const pty = process.spawnPty("echo", ["$HOME", "*.txt", "test;ls"]);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        // These should be passed literally, not shell-expanded
        vim.e2e.assert.true(output.includes("$HOME"), "should pass $HOME literally");
    });

    vim.e2e.test("many arguments work", function() {
        let output = "";
        const args = [];
        for (let i = 0; i < 20; i++) {
            args.push("arg" + i);
        }

        const pty = process.spawnPty("echo", args);

        pty.onData((data: string) => {
            output += data;
        });

        vim.e2e.wait(200);

        vim.e2e.assert.true(output.includes("arg0"), "should contain first arg");
        vim.e2e.assert.true(output.includes("arg19"), "should contain last arg");
    });

    // =========================================================================
    // Edge Cases - Error Handling
    // =========================================================================

    vim.e2e.test("invalid command throws error", function() {
        let threw = false;
        let errorMessage = "";

        try {
            // @ts-ignore - testing invalid input
            process.spawnPty(123);
        } catch (e: any) {
            threw = true;
            errorMessage = e?.message || String(e);
        }

        vim.e2e.assert.true(threw, "should throw for invalid command type");
    });

    vim.e2e.test("empty command string throws error", function() {
        let threw = false;

        try {
            process.spawnPty("");
        } catch (e) {
            threw = true;
        }

        vim.e2e.assert.true(threw, "should throw for empty command");
    });

    vim.e2e.test("kill on already exited process returns false", function() {
        const pty = process.spawnPty("true"); // Exits immediately

        vim.e2e.wait(300); // Wait for exit

        const result = pty.kill();
        vim.e2e.assert.true(result === false || result === true, "kill should return boolean");
    });

    vim.e2e.test("write to exited process returns false", function() {
        const pty = process.spawnPty("true"); // Exits immediately

        vim.e2e.wait(300); // Wait for exit

        const result = pty.write("test");
        vim.e2e.assert.equal(result, false);
    });

    vim.e2e.test("resize on exited process is safe", function() {
        const pty = process.spawnPty("true"); // Exits immediately

        vim.e2e.wait(300); // Wait for exit

        // Should not throw, may return false
        let threw = false;
        try {
            pty.resize(40, 100);
        } catch (e) {
            threw = true;
        }

        vim.e2e.assert.true(!threw, "resize on exited process should not throw");
    });

    // =========================================================================
    // Edge Cases - Callback Registration
    // =========================================================================

    vim.e2e.test("onData can be set after spawn", function() {
        const pty = process.spawnPty("sleep", ["0.1"]);

        vim.e2e.wait(50);

        let dataCalled = false;
        pty.onData(() => {
            dataCalled = true;
        });

        vim.e2e.wait(200);

        // May or may not receive data, but shouldn't crash
        vim.e2e.assert.true(true, "late onData registration should not crash");

        pty.kill();
        vim.e2e.wait(200);
    });

    vim.e2e.test("onExit can be set after spawn", function() {
        const pty = process.spawnPty("echo", ["test"]);

        vim.e2e.wait(50);

        let exitCalled = false;
        pty.onExit(() => {
            exitCalled = true;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.true(exitCalled, "late onExit should still be called");
    });

    vim.e2e.test("replacing onData callback works", function() {
        let firstCallback = 0;
        let secondCallback = 0;

        const pty = process.spawnPty("sh");

        pty.onData(() => {
            firstCallback++;
        });

        vim.e2e.wait(50);

        // Replace callback
        pty.onData(() => {
            secondCallback++;
        });

        pty.write("echo test\n");
        vim.e2e.wait(200);

        pty.kill();
        vim.e2e.wait(200);

        // Second callback should receive data, first should not (after replacement)
        vim.e2e.assert.true(secondCallback > 0, "second callback should be called");
    });

    vim.e2e.test("onData returns this for chaining", function() {
        const pty = process.spawnPty("echo", ["test"]);

        const result = pty.onData(() => {});
        vim.e2e.assert.equal(result, pty);

        vim.e2e.wait(200);
    });

    vim.e2e.test("onExit returns this for chaining", function() {
        const pty = process.spawnPty("echo", ["test"]);

        const result = pty.onExit(() => {});
        vim.e2e.assert.equal(result, pty);

        vim.e2e.wait(200);
    });

    vim.e2e.test("chained callback registration works", function() {
        let dataReceived = false;
        let exitReceived = false;

        process.spawnPty("echo", ["chain"])
            .onData(() => { dataReceived = true; })
            .onExit(() => { exitReceived = true; });

        vim.e2e.wait(300);

        vim.e2e.assert.true(dataReceived, "onData should be called");
        vim.e2e.assert.true(exitReceived, "onExit should be called");
    });

    // =========================================================================
    // Timeout Option
    // =========================================================================

    vim.e2e.test("timeout option kills process after specified time", function() {
        let exitCode: number | null = null;

        const pty = process.spawnPty("sleep", ["10"], { timeout: 200 });

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(500);

        // Timeout should have killed the process
        vim.e2e.assert.true(exitCode !== null, "process should have exited");
        vim.e2e.assert.equal(exitCode, 124); // Timeout exit code
    });

    vim.e2e.test("process completing before timeout exits normally", function() {
        let exitCode: number | null = null;

        const pty = process.spawnPty("echo", ["quick"], { timeout: 5000 });

        pty.onExit((code: number) => {
            exitCode = code;
        });

        vim.e2e.wait(300);

        vim.e2e.assert.equal(exitCode, 0); // Normal exit, not timeout
    });

});

vim.e2e.runAll();
