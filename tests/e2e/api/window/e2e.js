// Window API E2E Tests
// Tests vim.api window functions with real editor state
// TDD: Write tests first, let them fail, then implement
vim.e2e.describe("vim.api.getCurrentWin", function () {
    vim.e2e.test("returns window handle 0 (current window)", function () {
        const win = vim.api.getCurrentWin();
        vim.e2e.assert.equal(win, 0, "getCurrentWin should return 0 for current window");
    });
    vim.e2e.test("returns a number type", function () {
        const win = vim.api.getCurrentWin();
        vim.e2e.assert.equal(typeof win, "number", "Window handle should be a number");
    });
});
vim.e2e.describe("vim.api.winGetCursor", function () {
    vim.e2e.test("returns cursor position as [row, col]", function () {
        // Cursor should be at start after config.ts runs gg0
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(Array.isArray(pos), "Should return an array");
        vim.e2e.assert.equal(pos.length, 2, "Should return [row, col]");
    });
    vim.e2e.test("row is 1-indexed (Neovim convention)", function () {
        // After gg0, cursor at first line
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 1, "First line should be row 1 (1-indexed)");
    });
    vim.e2e.test("col is 0-indexed (Neovim convention)", function () {
        // After gg0, cursor at first column
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[1], 0, "First column should be col 0 (0-indexed)");
    });
    vim.e2e.test("reflects cursor movement", function () {
        // First go to known position, then move
        vim.e2e.keys("gg0"); // Go to start
        vim.e2e.keys("jj"); // Move down 2 lines (to line 3, 1-indexed)
        vim.e2e.keys("lllll"); // Move right 5 cols
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 3, "Should be on line 3");
        vim.e2e.assert.equal(pos[1], 5, "Should be at column 5");
    });
});
vim.e2e.describe("vim.api.winSetCursor", function () {
    vim.e2e.test("sets cursor to specified position", function () {
        // Set cursor to line 2, col 3
        vim.api.winSetCursor(0, [2, 3]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 2, "Row should be 2");
        vim.e2e.assert.equal(pos[1], 3, "Col should be 3");
    });
    vim.e2e.test("clamps to valid line range", function () {
        // Try to set cursor beyond buffer
        vim.api.winSetCursor(0, [100, 0]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[0] <= 5, "Row should be clamped to buffer size");
    });
    vim.e2e.test("clamps to valid column range", function () {
        // Set to line 1, then try invalid column
        vim.api.winSetCursor(0, [1, 1000]);
        const pos = vim.api.winGetCursor(0);
        // Column should be clamped to line length
        vim.e2e.assert.true(pos[1] < 1000, "Col should be clamped to line length");
    });
});
vim.e2e.describe("vim.api.winIsValid", function () {
    vim.e2e.test("returns true for current window (0)", function () {
        const valid = vim.api.winIsValid(0);
        vim.e2e.assert.true(valid, "Window 0 should always be valid");
    });
    vim.e2e.test("returns false for invalid window handle", function () {
        const valid = vim.api.winIsValid(9999);
        vim.e2e.assert.false(valid, "Window 9999 should not be valid");
    });
});
vim.e2e.describe("vim.api.winGetBuf", function () {
    vim.e2e.test("returns buffer handle for window", function () {
        const buf = vim.api.winGetBuf(0);
        vim.e2e.assert.equal(buf, 0, "Window 0 should contain buffer 0");
    });
});
vim.e2e.describe("vim.api.winGetHeight", function () {
    vim.e2e.test("returns window height as number", function () {
        const height = vim.api.winGetHeight(0);
        vim.e2e.assert.equal(typeof height, "number", "Height should be a number");
        vim.e2e.assert.true(height > 0, "Height should be positive");
    });
});
vim.e2e.describe("vim.api.winGetWidth", function () {
    vim.e2e.test("returns window width as number", function () {
        const width = vim.api.winGetWidth(0);
        vim.e2e.assert.equal(typeof width, "number", "Width should be a number");
        vim.e2e.assert.true(width > 0, "Width should be positive");
    });
});
// ============================================================================
// NEW WINDOW API FUNCTIONS (TDD - tests written first)
// ============================================================================
vim.e2e.describe("vim.api.setCurrentWin", function () {
    vim.e2e.test("does not throw for current window (0)", function () {
        vim.api.setCurrentWin(0);
        vim.e2e.assert.true(true, "setCurrentWin(0) should not throw");
    });
    vim.e2e.test("silently ignores invalid window handle", function () {
        // Neovim behavior: silently fails for invalid handles
        vim.api.setCurrentWin(9999);
        vim.e2e.assert.true(true, "setCurrentWin(9999) should not throw");
    });
    vim.e2e.test("current window remains 0 after call", function () {
        vim.api.setCurrentWin(0);
        const win = vim.api.getCurrentWin();
        vim.e2e.assert.equal(win, 0, "Current window should still be 0");
    });
});
vim.e2e.describe("vim.api.listWins", function () {
    vim.e2e.test("returns array of window handles", function () {
        const wins = vim.api.listWins();
        vim.e2e.assert.true(Array.isArray(wins), "Should return an array");
    });
    vim.e2e.test("includes current window (0) in list", function () {
        const wins = vim.api.listWins();
        vim.e2e.assert.true(wins.includes(0), "Should include window 0");
    });
    vim.e2e.test("returns at least one window", function () {
        const wins = vim.api.listWins();
        vim.e2e.assert.true(wins.length >= 1, "Should have at least one window");
    });
});
vim.e2e.describe("vim.api.winSetBuf", function () {
    vim.e2e.test("does not throw for valid window and buffer", function () {
        vim.api.winSetBuf(0, 0);
        vim.e2e.assert.true(true, "winSetBuf should not throw");
    });
    vim.e2e.test("current buffer remains accessible", function () {
        vim.api.winSetBuf(0, 0);
        const buf = vim.api.winGetBuf(0);
        vim.e2e.assert.equal(buf, 0, "Buffer should still be accessible");
    });
    vim.e2e.test("silently ignores invalid window", function () {
        vim.api.winSetBuf(9999, 0);
        vim.e2e.assert.true(true, "Should not throw for invalid window");
    });
});
vim.e2e.describe("vim.api.winSetHeight", function () {
    vim.e2e.test("does not throw for valid window", function () {
        vim.api.winSetHeight(0, 20);
        vim.e2e.assert.true(true, "winSetHeight should not throw");
    });
    vim.e2e.test("silently ignores in single-window mode", function () {
        // Single window cannot change height
        const before = vim.api.winGetHeight(0);
        vim.api.winSetHeight(0, 10);
        const after = vim.api.winGetHeight(0);
        // Height should remain unchanged in single-window mode
        vim.e2e.assert.equal(before, after, "Height unchanged in single-window mode");
    });
});
vim.e2e.describe("vim.api.winSetWidth", function () {
    vim.e2e.test("does not throw for valid window", function () {
        vim.api.winSetWidth(0, 80);
        vim.e2e.assert.true(true, "winSetWidth should not throw");
    });
    vim.e2e.test("silently ignores in single-window mode", function () {
        // Single window cannot change width
        const before = vim.api.winGetWidth(0);
        vim.api.winSetWidth(0, 40);
        const after = vim.api.winGetWidth(0);
        // Width should remain unchanged in single-window mode
        vim.e2e.assert.equal(before, after, "Width unchanged in single-window mode");
    });
});
vim.e2e.describe("vim.api.winClose", function () {
    vim.e2e.test("does not throw for current window", function () {
        // In single-window mode, cannot close the only window
        vim.api.winClose(0, false);
        vim.e2e.assert.true(true, "winClose should not throw");
    });
    vim.e2e.test("accepts force option", function () {
        vim.api.winClose(0, true);
        vim.e2e.assert.true(true, "winClose with force should not throw");
    });
    vim.e2e.test("window 0 still valid after close attempt", function () {
        vim.api.winClose(0, false);
        const valid = vim.api.winIsValid(0);
        vim.e2e.assert.true(valid, "Window 0 should still be valid (single-window)");
    });
});
vim.e2e.describe("vim.api.winGetVar", function () {
    vim.e2e.test("returns undefined for non-existent variable", function () {
        const value = vim.api.winGetVar(0, "nonexistent_win_var");
        vim.e2e.assert.equal(value, undefined, "Non-existent var should be undefined");
    });
    vim.e2e.test("returns previously set variable", function () {
        vim.api.winSetVar(0, "test_win_var", "win_value");
        const value = vim.api.winGetVar(0, "test_win_var");
        vim.e2e.assert.equal(value, "win_value", "Should return set value");
    });
});
vim.e2e.describe("vim.api.winSetVar", function () {
    vim.e2e.test("sets string variable", function () {
        vim.api.winSetVar(0, "win_string", "hello");
        const value = vim.api.winGetVar(0, "win_string");
        vim.e2e.assert.equal(value, "hello", "String var should be set");
    });
    vim.e2e.test("sets number variable", function () {
        vim.api.winSetVar(0, "win_number", 123);
        const value = vim.api.winGetVar(0, "win_number");
        vim.e2e.assert.equal(value, 123, "Number var should be set");
    });
    vim.e2e.test("sets object variable", function () {
        vim.api.winSetVar(0, "win_obj", { foo: "bar" });
        const value = vim.api.winGetVar(0, "win_obj");
        vim.e2e.assert.equal(value.foo, "bar", "Object var should be set");
    });
    vim.e2e.test("overwrites existing variable", function () {
        vim.api.winSetVar(0, "win_overwrite", "old");
        vim.api.winSetVar(0, "win_overwrite", "new");
        const value = vim.api.winGetVar(0, "win_overwrite");
        vim.e2e.assert.equal(value, "new", "Should overwrite with new value");
    });
});
vim.e2e.describe("vim.api.winDelVar", function () {
    vim.e2e.test("deletes existing variable", function () {
        vim.api.winSetVar(0, "win_to_delete", "value");
        vim.api.winDelVar(0, "win_to_delete");
        const value = vim.api.winGetVar(0, "win_to_delete");
        vim.e2e.assert.equal(value, undefined, "Deleted var should be undefined");
    });
    vim.e2e.test("does not throw for non-existent variable", function () {
        vim.api.winDelVar(0, "win_never_existed");
        vim.e2e.assert.true(true, "Should not throw");
    });
});
vim.e2e.describe("vim.api.winCall", function () {
    vim.e2e.test("executes function with window as context", function () {
        let called = false;
        vim.api.winCall(0, function () {
            called = true;
        });
        vim.e2e.assert.true(called, "Function should be called");
    });
    vim.e2e.test("returns function result", function () {
        const result = vim.api.winCall(0, function () {
            return 99;
        });
        vim.e2e.assert.equal(result, 99, "Should return function result");
    });
    vim.e2e.test("has access to window state", function () {
        const result = vim.api.winCall(0, function () {
            return vim.api.winGetCursor(0);
        });
        vim.e2e.assert.true(Array.isArray(result), "Should access cursor in context");
    });
    vim.e2e.test("returns undefined for invalid window", function () {
        const result = vim.api.winCall(9999, function () { return 42; });
        vim.e2e.assert.equal(result, undefined, "Invalid window should return undefined");
    });
});
vim.e2e.describe("vim.api.winGetNumber", function () {
    vim.e2e.test("returns window number as number", function () {
        const num = vim.api.winGetNumber(0);
        vim.e2e.assert.equal(typeof num, "number", "Should return number");
    });
    vim.e2e.test("returns 1 for only window (1-indexed)", function () {
        const num = vim.api.winGetNumber(0);
        vim.e2e.assert.equal(num, 1, "Single window should be number 1");
    });
    vim.e2e.test("returns -1 for invalid window", function () {
        const num = vim.api.winGetNumber(9999);
        vim.e2e.assert.equal(num, -1, "Invalid window should return -1");
    });
});
vim.e2e.describe("vim.api.winGetPosition", function () {
    vim.e2e.test("returns position as [row, col]", function () {
        const pos = vim.api.winGetPosition(0);
        vim.e2e.assert.true(Array.isArray(pos), "Should return array");
        vim.e2e.assert.equal(pos.length, 2, "Should have 2 elements");
    });
    vim.e2e.test("returns [0, 0] for full-screen window", function () {
        const pos = vim.api.winGetPosition(0);
        vim.e2e.assert.equal(pos[0], 0, "Row should be 0 for full-screen");
        vim.e2e.assert.equal(pos[1], 0, "Col should be 0 for full-screen");
    });
    vim.e2e.test("returns null for invalid window", function () {
        const pos = vim.api.winGetPosition(9999);
        vim.e2e.assert.equal(pos, null, "Invalid window should return null");
    });
});
// ============================================================================
// EDGE CASES
// ============================================================================
vim.e2e.describe("Edge Cases: Window API", function () {
    vim.e2e.test("winGetCursor returns null for invalid window", function () {
        const pos = vim.api.winGetCursor(9999);
        vim.e2e.assert.equal(pos, null, "Invalid window should return null");
    });
    vim.e2e.test("winSetCursor ignores invalid window", function () {
        vim.api.winSetCursor(9999, [1, 0]);
        vim.e2e.assert.true(true, "Should not throw");
    });
    vim.e2e.test("winGetBuf returns null for invalid window", function () {
        const buf = vim.api.winGetBuf(9999);
        vim.e2e.assert.equal(buf, null, "Invalid window should return null");
    });
    vim.e2e.test("winGetHeight returns null for invalid window", function () {
        const height = vim.api.winGetHeight(9999);
        vim.e2e.assert.equal(height, null, "Invalid window should return null");
    });
    vim.e2e.test("winGetWidth returns null for invalid window", function () {
        const width = vim.api.winGetWidth(9999);
        vim.e2e.assert.equal(width, null, "Invalid window should return null");
    });
    vim.e2e.test("negative window handle treated as invalid", function () {
        const valid = vim.api.winIsValid(-1);
        vim.e2e.assert.false(valid, "Negative window handle should be invalid");
    });
    vim.e2e.test("window variables isolated per window", function () {
        vim.api.winSetVar(0, "isolated_win_var", "win0");
        const value = vim.api.winGetVar(9999, "isolated_win_var");
        vim.e2e.assert.equal(value, undefined, "Invalid window should not have var");
    });
});
// ============================================================================
// ADDITIONAL EDGE CASES (Comprehensive Coverage)
// ============================================================================
vim.e2e.describe("Edge Cases: Boundary Values", function () {
    vim.e2e.test("winSetCursor with row 0 (invalid in Neovim)", function () {
        // Neovim uses 1-indexed rows, row 0 should be treated as row 1
        vim.api.winSetCursor(0, [0, 0]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.equal(pos[0], 1, "Row 0 should be treated as row 1");
    });
    vim.e2e.test("winSetCursor with negative row", function () {
        vim.api.winSetCursor(0, [-5, 0]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[0] >= 1, "Negative row should be clamped to valid range");
    });
    vim.e2e.test("winSetCursor with negative column", function () {
        vim.api.winSetCursor(0, [1, -5]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[1] >= 0, "Negative column should be clamped to 0");
    });
    vim.e2e.test("winSetCursor with very large row", function () {
        vim.api.winSetCursor(0, [999999, 0]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[0] <= 100, "Very large row should be clamped");
    });
    vim.e2e.test("winSetCursor with very large column", function () {
        vim.api.winSetCursor(0, [1, 999999]);
        const pos = vim.api.winGetCursor(0);
        vim.e2e.assert.true(pos[1] < 999999, "Very large column should be clamped");
    });
});
vim.e2e.describe("Edge Cases: Empty and Null Arguments", function () {
    vim.e2e.test("winGetVar with empty string name", function () {
        const value = vim.api.winGetVar(0, "");
        vim.e2e.assert.equal(value, undefined, "Empty name should return undefined");
    });
    vim.e2e.test("winSetVar with empty string name", function () {
        vim.api.winSetVar(0, "", "value");
        const value = vim.api.winGetVar(0, "");
        // Empty name should either be ignored or stored
        vim.e2e.assert.true(true, "Should not throw for empty name");
    });
    vim.e2e.test("winDelVar with empty string name", function () {
        vim.api.winDelVar(0, "");
        vim.e2e.assert.true(true, "Should not throw for empty name");
    });
    vim.e2e.test("winSetVar with null value", function () {
        vim.api.winSetVar(0, "null_val", null);
        const value = vim.api.winGetVar(0, "null_val");
        vim.e2e.assert.equal(value, null, "Should store null value");
    });
    vim.e2e.test("winSetVar with undefined value", function () {
        vim.api.winSetVar(0, "undef_val", undefined);
        const value = vim.api.winGetVar(0, "undef_val");
        // undefined may be stored as undefined or ignored
        vim.e2e.assert.true(true, "Should not throw for undefined value");
    });
    vim.e2e.test("winSetVar with array value", function () {
        vim.api.winSetVar(0, "arr_val", [1, 2, 3]);
        const value = vim.api.winGetVar(0, "arr_val");
        vim.e2e.assert.true(Array.isArray(value), "Should store array value");
        vim.e2e.assert.equal(value.length, 3, "Array should have correct length");
    });
    vim.e2e.test("winSetVar with boolean value", function () {
        vim.api.winSetVar(0, "bool_true", true);
        vim.api.winSetVar(0, "bool_false", false);
        vim.e2e.assert.equal(vim.api.winGetVar(0, "bool_true"), true, "Should store true");
        vim.e2e.assert.equal(vim.api.winGetVar(0, "bool_false"), false, "Should store false");
    });
});
vim.e2e.describe("Edge Cases: Special Window Handles", function () {
    vim.e2e.test("window handle 0 is always current window", function () {
        const cursor0 = vim.api.winGetCursor(0);
        const cursorCurrent = vim.api.winGetCursor(vim.api.getCurrentWin());
        vim.e2e.assert.equal(cursor0[0], cursorCurrent[0], "Handle 0 should match current window");
        vim.e2e.assert.equal(cursor0[1], cursorCurrent[1], "Handle 0 should match current window");
    });
    vim.e2e.test("float window handle (0.5) treated as integer", function () {
        // JavaScript may pass float, should be converted to int
        const valid = vim.api.winIsValid(0.5);
        // 0.5 truncates to 0, which is valid
        vim.e2e.assert.true(valid, "Float 0.5 should truncate to 0 (valid)");
    });
    vim.e2e.test("NaN window handle treated as invalid", function () {
        const valid = vim.api.winIsValid(NaN);
        vim.e2e.assert.false(valid, "NaN should be invalid");
    });
    vim.e2e.test("Infinity window handle treated as invalid", function () {
        const valid = vim.api.winIsValid(Infinity);
        vim.e2e.assert.false(valid, "Infinity should be invalid");
    });
});
vim.e2e.describe("Edge Cases: winCall Context Isolation", function () {
    vim.e2e.test("winCall preserves current window after execution", function () {
        const before = vim.api.getCurrentWin();
        vim.api.winCall(0, function () {
            // Do something in window context
            vim.api.winGetCursor(0);
        });
        const after = vim.api.getCurrentWin();
        vim.e2e.assert.equal(before, after, "Current window should be preserved");
    });
    vim.e2e.test("winCall handles exception in callback", function () {
        // This tests that exceptions don't break window state
        try {
            vim.api.winCall(0, function () {
                throw new Error("Test error");
            });
        }
        catch (e) {
            // Expected to throw
        }
        // Window should still be accessible
        const valid = vim.api.winIsValid(0);
        vim.e2e.assert.true(valid, "Window should still be valid after exception");
    });
    vim.e2e.test("winCall with function returning undefined", function () {
        const result = vim.api.winCall(0, function () {
            // No return statement
        });
        vim.e2e.assert.equal(result, undefined, "Should return undefined");
    });
});
vim.e2e.describe("Edge Cases: winClose Behavior", function () {
    vim.e2e.test("winClose on invalid window does not throw", function () {
        vim.api.winClose(9999, false);
        vim.e2e.assert.true(true, "Should not throw for invalid window");
    });
    vim.e2e.test("winClose with force on invalid window does not throw", function () {
        vim.api.winClose(9999, true);
        vim.e2e.assert.true(true, "Should not throw for invalid window with force");
    });
});
vim.e2e.describe("Edge Cases: Concurrent Variable Operations", function () {
    vim.e2e.test("rapid set/get operations work correctly", function () {
        for (let i = 0; i < 100; i++) {
            vim.api.winSetVar(0, "rapid_" + i, i);
        }
        // Verify a few values
        vim.e2e.assert.equal(vim.api.winGetVar(0, "rapid_0"), 0, "First value correct");
        vim.e2e.assert.equal(vim.api.winGetVar(0, "rapid_50"), 50, "Middle value correct");
        vim.e2e.assert.equal(vim.api.winGetVar(0, "rapid_99"), 99, "Last value correct");
    });
    vim.e2e.test("set then delete then get returns undefined", function () {
        vim.api.winSetVar(0, "temp_var", "exists");
        vim.api.winDelVar(0, "temp_var");
        const value = vim.api.winGetVar(0, "temp_var");
        vim.e2e.assert.equal(value, undefined, "Deleted var should be undefined");
    });
    vim.e2e.test("delete then set creates new variable", function () {
        vim.api.winDelVar(0, "recreate_var");
        vim.api.winSetVar(0, "recreate_var", "new_value");
        const value = vim.api.winGetVar(0, "recreate_var");
        vim.e2e.assert.equal(value, "new_value", "Recreated var should have new value");
    });
});
vim.e2e.runAll();
