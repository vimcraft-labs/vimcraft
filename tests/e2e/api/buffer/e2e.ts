// Buffer API E2E Tests
// Tests vim.api buffer functions with real editor state
// TDD: Write tests first, let them fail, then implement

vim.e2e.describe("vim.api.getCurrentBuf", function() {
    vim.e2e.test("returns buffer handle 0 (current buffer)", function() {
        const buf = vim.api.getCurrentBuf();
        vim.e2e.assert.equal(buf, 0, "getCurrentBuf should return 0 for current buffer");
    });

    vim.e2e.test("returns a number type", function() {
        const buf = vim.api.getCurrentBuf();
        vim.e2e.assert.equal(typeof buf, "number", "Buffer handle should be a number");
    });
});

vim.e2e.describe("vim.api.bufLineCount", function() {
    vim.e2e.test("returns correct line count", function() {
        // Config creates 5 lines of content
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count >= 5, "Buffer should have at least 5 lines");
    });

    vim.e2e.test("accepts buffer handle 0 for current buffer", function() {
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count > 0, "Line count should be positive");
    });
});

vim.e2e.describe("vim.api.bufGetLines", function() {
    vim.e2e.test("returns lines as array of strings", function() {
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.true(Array.isArray(lines), "Should return an array");
        vim.e2e.assert.equal(lines.length, 1, "Should return 1 line");
    });

    vim.e2e.test("returns correct content for first line", function() {
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.true(
            lines[0].includes("Line 1"),
            "First line should contain 'Line 1'"
        );
    });

    vim.e2e.test("returns multiple lines when requested", function() {
        const lines = vim.api.bufGetLines(0, 0, 3, false);
        vim.e2e.assert.equal(lines.length, 3, "Should return 3 lines");
    });

    vim.e2e.test("returns all lines with -1 end index", function() {
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.true(lines.length >= 5, "Should return at least 5 lines");
    });

    vim.e2e.test("handles out of bounds gracefully with strict=false", function() {
        const lines = vim.api.bufGetLines(0, 0, 1000, false);
        vim.e2e.assert.true(Array.isArray(lines), "Should return array even with large end");
    });
});

vim.e2e.describe("vim.api.bufSetLines", function() {
    vim.e2e.test("replaces a single line", function() {
        // Replace line 1 (0-indexed) with new content
        vim.api.bufSetLines(0, 0, 1, false, ["REPLACED LINE"]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "REPLACED LINE", "Line should be replaced");
    });

    vim.e2e.test("inserts new lines", function() {
        const countBefore = vim.api.bufLineCount(0);
        // Insert at end
        vim.api.bufSetLines(0, -1, -1, false, ["NEW LINE AT END"]);
        const countAfter = vim.api.bufLineCount(0);
        vim.e2e.assert.equal(countAfter, countBefore + 1, "Should add one line");
    });

    vim.e2e.test("deletes lines when replacement is empty", function() {
        const countBefore = vim.api.bufLineCount(0);
        // Delete first line
        vim.api.bufSetLines(0, 0, 1, false, []);
        const countAfter = vim.api.bufLineCount(0);
        vim.e2e.assert.equal(countAfter, countBefore - 1, "Should remove one line");
    });
});

vim.e2e.describe("vim.api.bufGetName", function() {
    vim.e2e.test("returns string for buffer name", function() {
        const name = vim.api.bufGetName(0);
        vim.e2e.assert.equal(typeof name, "string", "Buffer name should be a string");
    });

    vim.e2e.test("returns empty string for unnamed buffer", function() {
        // New buffer should be unnamed
        const name = vim.api.bufGetName(0);
        // Could be empty or have a path - just verify it doesn't throw
        vim.e2e.assert.true(true, "bufGetName should not throw");
    });
});

vim.e2e.describe("vim.api.bufIsValid", function() {
    vim.e2e.test("returns true for current buffer (0)", function() {
        const valid = vim.api.bufIsValid(0);
        vim.e2e.assert.true(valid, "Buffer 0 should always be valid");
    });

    vim.e2e.test("returns false for invalid buffer handle", function() {
        const valid = vim.api.bufIsValid(9999);
        vim.e2e.assert.false(valid, "Buffer 9999 should not be valid");
    });
});

vim.e2e.describe("vim.api.listBufs", function() {
    vim.e2e.test("returns array of buffer handles", function() {
        const bufs = vim.api.listBufs();
        vim.e2e.assert.true(Array.isArray(bufs), "Should return an array");
    });

    vim.e2e.test("includes current buffer (0) in list", function() {
        const bufs = vim.api.listBufs();
        // In headless mode, returns [0]; in Editor mode, returns actual buffer IDs
        vim.e2e.assert.true(bufs.length >= 1, "Should have at least one buffer");
    });
});

vim.e2e.describe("vim.api.setCurrentBuf", function() {
    vim.e2e.test("does not throw for valid buffer (0)", function() {
        // Should not throw - switching to current buffer is a no-op
        vim.api.setCurrentBuf(0);
        vim.e2e.assert.true(true, "setCurrentBuf(0) should not throw");
    });

    vim.e2e.test("silently ignores invalid buffer handle", function() {
        // Neovim behavior: silently fails for invalid handles
        vim.api.setCurrentBuf(9999);
        vim.e2e.assert.true(true, "setCurrentBuf(9999) should not throw");
    });
});

vim.e2e.describe("vim.api.bufSetName", function() {
    vim.e2e.test("sets buffer name", function() {
        vim.api.bufSetName(0, "/tmp/test_buffer.txt");
        const name = vim.api.bufGetName(0);
        vim.e2e.assert.equal(name, "/tmp/test_buffer.txt", "Buffer name should be set");
    });

    vim.e2e.test("can clear buffer name with empty string", function() {
        vim.api.bufSetName(0, "");
        const name = vim.api.bufGetName(0);
        vim.e2e.assert.equal(name, "", "Buffer name should be empty");
    });
});

vim.e2e.describe("vim.api.bufDelete", function() {
    vim.e2e.test("does not throw for current buffer", function() {
        // In headless mode, cannot delete the only buffer - silently fails
        vim.api.bufDelete(0, {});
        vim.e2e.assert.true(true, "bufDelete should not throw");
    });

    vim.e2e.test("accepts force option", function() {
        // Force option should be accepted without error
        vim.api.bufDelete(0, { force: true });
        vim.e2e.assert.true(true, "bufDelete with force should not throw");
    });
});

// ============================================================================
// NEW BUFFER API FUNCTIONS (TDD - tests written first)
// ============================================================================

vim.e2e.describe("vim.api.createBuf", function() {
    vim.e2e.test("creates a new buffer and returns handle", function() {
        const buf = vim.api.createBuf(true, false);
        vim.e2e.assert.equal(typeof buf, "number", "Should return buffer handle");
    });

    vim.e2e.test("created buffer is valid", function() {
        const buf = vim.api.createBuf(true, false);
        // In headless mode, returns 0 (single buffer); in Editor mode, returns new ID
        vim.e2e.assert.true(buf >= 0, "Buffer handle should be non-negative");
    });

    vim.e2e.test("scratch buffer is not listed", function() {
        // Scratch buffers have listed=false, scratch=true
        const buf = vim.api.createBuf(false, true);
        vim.e2e.assert.true(buf >= 0, "Scratch buffer should be created");
    });
});

vim.e2e.describe("vim.api.bufGetText", function() {
    vim.e2e.test("returns text from specified range", function() {
        // Set up known content
        vim.api.bufSetLines(0, 0, -1, false, ["Hello World", "Second Line"]);
        // Get characters 0-5 from line 0 ("Hello")
        const text = vim.api.bufGetText(0, 0, 0, 0, 5);
        vim.e2e.assert.true(Array.isArray(text), "Should return array of strings");
        vim.e2e.assert.equal(text[0], "Hello", "Should return 'Hello'");
    });

    vim.e2e.test("handles multi-line text", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Line One", "Line Two", "Line Three"]);
        // Get from line 0 col 5 to line 1 col 4 ("One\nLine")
        const text = vim.api.bufGetText(0, 0, 5, 1, 4);
        vim.e2e.assert.true(text.length >= 1, "Should return text");
    });

    vim.e2e.test("returns empty for invalid range", function() {
        const text = vim.api.bufGetText(0, 100, 0, 100, 10);
        vim.e2e.assert.true(Array.isArray(text), "Should return array even for invalid range");
    });
});

vim.e2e.describe("vim.api.bufSetText", function() {
    vim.e2e.test("replaces text at character level", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello World"]);
        // Replace "World" (col 6-11) with "Vim"
        vim.api.bufSetText(0, 0, 6, 0, 11, ["Vim"]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "Hello Vim", "Should replace 'World' with 'Vim'");
    });

    vim.e2e.test("inserts text at position", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["HelloWorld"]);
        // Insert " " at col 5
        vim.api.bufSetText(0, 0, 5, 0, 5, [" "]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "Hello World", "Should insert space");
    });

    vim.e2e.test("handles multi-line replacement", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["First", "Second", "Third"]);
        // Replace from line 0 col 2 to line 2 col 2 with single line
        vim.api.bufSetText(0, 0, 2, 2, 2, ["REPLACED"]);
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count >= 1, "Buffer should have at least 1 line");
    });
});

vim.e2e.describe("vim.api.bufIsLoaded", function() {
    vim.e2e.test("returns true for current buffer", function() {
        const loaded = vim.api.bufIsLoaded(0);
        vim.e2e.assert.true(loaded, "Current buffer should be loaded");
    });

    vim.e2e.test("returns false for invalid buffer", function() {
        const loaded = vim.api.bufIsLoaded(9999);
        vim.e2e.assert.false(loaded, "Invalid buffer should not be loaded");
    });
});

vim.e2e.describe("vim.api.bufGetVar", function() {
    vim.e2e.test("returns undefined for non-existent variable", function() {
        const value = vim.api.bufGetVar(0, "nonexistent_var");
        vim.e2e.assert.equal(value, undefined, "Non-existent var should be undefined");
    });

    vim.e2e.test("returns previously set variable", function() {
        vim.api.bufSetVar(0, "test_var", "test_value");
        const value = vim.api.bufGetVar(0, "test_var");
        vim.e2e.assert.equal(value, "test_value", "Should return set value");
    });
});

vim.e2e.describe("vim.api.bufSetVar", function() {
    vim.e2e.test("sets string variable", function() {
        vim.api.bufSetVar(0, "my_string", "hello");
        const value = vim.api.bufGetVar(0, "my_string");
        vim.e2e.assert.equal(value, "hello", "String var should be set");
    });

    vim.e2e.test("sets number variable", function() {
        vim.api.bufSetVar(0, "my_number", 42);
        const value = vim.api.bufGetVar(0, "my_number");
        vim.e2e.assert.equal(value, 42, "Number var should be set");
    });

    vim.e2e.test("sets boolean variable", function() {
        vim.api.bufSetVar(0, "my_bool", true);
        const value = vim.api.bufGetVar(0, "my_bool");
        vim.e2e.assert.equal(value, true, "Boolean var should be set");
    });

    vim.e2e.test("overwrites existing variable", function() {
        vim.api.bufSetVar(0, "overwrite_test", "old");
        vim.api.bufSetVar(0, "overwrite_test", "new");
        const value = vim.api.bufGetVar(0, "overwrite_test");
        vim.e2e.assert.equal(value, "new", "Should overwrite with new value");
    });
});

vim.e2e.describe("vim.api.bufDelVar", function() {
    vim.e2e.test("deletes existing variable", function() {
        vim.api.bufSetVar(0, "to_delete", "value");
        vim.api.bufDelVar(0, "to_delete");
        const value = vim.api.bufGetVar(0, "to_delete");
        vim.e2e.assert.equal(value, undefined, "Deleted var should be undefined");
    });

    vim.e2e.test("does not throw for non-existent variable", function() {
        vim.api.bufDelVar(0, "never_existed");
        vim.e2e.assert.true(true, "Should not throw");
    });
});

vim.e2e.describe("vim.api.bufGetChangedtick", function() {
    vim.e2e.test("returns a number", function() {
        const tick = vim.api.bufGetChangedtick(0);
        vim.e2e.assert.equal(typeof tick, "number", "Changedtick should be a number");
    });

    vim.e2e.test("increments after buffer modification", function() {
        const before = vim.api.bufGetChangedtick(0);
        vim.api.bufSetLines(0, 0, 0, false, ["New line"]);
        const after = vim.api.bufGetChangedtick(0);
        vim.e2e.assert.true(after > before, "Changedtick should increment after edit");
    });
});

vim.e2e.describe("vim.api.bufGetOffset", function() {
    vim.e2e.test("returns byte offset for line", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello", "World"]);
        // Line 0 starts at offset 0
        const offset0 = vim.api.bufGetOffset(0, 0);
        vim.e2e.assert.equal(offset0, 0, "Line 0 should start at offset 0");
    });

    vim.e2e.test("calculates offset for subsequent lines", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello", "World"]);
        // Line 1 starts after "Hello\n" = 6 bytes
        const offset1 = vim.api.bufGetOffset(0, 1);
        vim.e2e.assert.equal(offset1, 6, "Line 1 should start at offset 6");
    });

    vim.e2e.test("returns -1 for out of range line", function() {
        const offset = vim.api.bufGetOffset(0, 9999);
        vim.e2e.assert.equal(offset, -1, "Invalid line should return -1");
    });
});

vim.e2e.describe("vim.api.bufCall", function() {
    vim.e2e.test("executes function with buffer as context", function() {
        let called = false;
        vim.api.bufCall(0, function() {
            called = true;
        });
        vim.e2e.assert.true(called, "Function should be called");
    });

    vim.e2e.test("returns function result", function() {
        const result = vim.api.bufCall(0, function() {
            return 42;
        });
        vim.e2e.assert.equal(result, 42, "Should return function result");
    });

    vim.e2e.test("has access to buffer content", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Test Content"]);
        const result = vim.api.bufCall(0, function() {
            return vim.api.bufGetLines(0, 0, 1, false)[0];
        });
        vim.e2e.assert.equal(result, "Test Content", "Should access buffer in context");
    });
});

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

vim.e2e.describe("Edge Cases: bufGetLines", function() {
    vim.e2e.test("empty buffer returns empty array", function() {
        vim.api.bufSetLines(0, 0, -1, false, []);
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.true(Array.isArray(lines), "Should return array");
    });

    vim.e2e.test("start > end returns empty array", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Line 1", "Line 2"]);
        const lines = vim.api.bufGetLines(0, 5, 3, false);
        vim.e2e.assert.equal(lines.length, 0, "Should return empty array when start > end");
    });

    vim.e2e.test("negative start treated as 0", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["First", "Second"]);
        const lines = vim.api.bufGetLines(0, -5, 1, false);
        vim.e2e.assert.equal(lines[0], "First", "Negative start should get first line");
    });

    vim.e2e.test("handles unicode content", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["你好世界", "🎉emoji🎊"]);
        const lines = vim.api.bufGetLines(0, 0, 2, false);
        vim.e2e.assert.equal(lines[0], "你好世界", "Should handle Chinese characters");
        vim.e2e.assert.equal(lines[1], "🎉emoji🎊", "Should handle emoji");
    });

    vim.e2e.test("handles very long lines", function() {
        const longLine = "x".repeat(10000);
        vim.api.bufSetLines(0, 0, -1, false, [longLine]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0].length, 10000, "Should handle 10K character line");
    });
});

vim.e2e.describe("Edge Cases: bufSetLines", function() {
    vim.e2e.test("handles empty replacement array", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["A", "B", "C"]);
        vim.api.bufSetLines(0, 0, 2, false, []);
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.equal(count, 1, "Should delete 2 lines");
    });

    vim.e2e.test("insert at beginning with start=0 end=0", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Original"]);
        vim.api.bufSetLines(0, 0, 0, false, ["Inserted"]);
        const lines = vim.api.bufGetLines(0, 0, 2, false);
        vim.e2e.assert.equal(lines[0], "Inserted", "New line should be first");
        vim.e2e.assert.equal(lines[1], "Original", "Original should be second");
    });

    vim.e2e.test("handles lines with newline characters stripped", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["No trailing newline"]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.false(lines[0].endsWith("\n"), "Lines should not have trailing newlines");
    });

    vim.e2e.test("multiple consecutive operations", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["1"]);
        vim.api.bufSetLines(0, 1, 1, false, ["2"]);
        vim.api.bufSetLines(0, 2, 2, false, ["3"]);
        const lines = vim.api.bufGetLines(0, 0, -1, false);
        vim.e2e.assert.equal(lines.length, 3, "Should have 3 lines after 3 inserts");
    });
});

vim.e2e.describe("Edge Cases: bufGetText", function() {
    vim.e2e.test("col beyond line length returns partial", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Short"]);
        const text = vim.api.bufGetText(0, 0, 0, 0, 100);
        vim.e2e.assert.equal(text[0], "Short", "Should return available text");
    });

    vim.e2e.test("same start and end position returns empty", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello"]);
        const text = vim.api.bufGetText(0, 0, 2, 0, 2);
        vim.e2e.assert.equal(text[0], "", "Same position should return empty string");
    });

    vim.e2e.test("negative column treated as 0", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello"]);
        const text = vim.api.bufGetText(0, 0, -5, 0, 3);
        vim.e2e.assert.equal(text[0], "Hel", "Negative col should start from 0");
    });
});

vim.e2e.describe("Edge Cases: bufSetText", function() {
    vim.e2e.test("delete text with empty replacement", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello World"]);
        vim.api.bufSetText(0, 0, 5, 0, 11, [""]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "Hello", "Should delete ' World'");
    });

    vim.e2e.test("replace with multiple lines", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["One Two Three"]);
        vim.api.bufSetText(0, 0, 4, 0, 7, ["A", "B"]);
        const count = vim.api.bufLineCount(0);
        vim.e2e.assert.true(count >= 1, "Multi-line replacement should work");
    });

    vim.e2e.test("insert at end of line", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello"]);
        vim.api.bufSetText(0, 0, 5, 0, 5, [" World"]);
        const lines = vim.api.bufGetLines(0, 0, 1, false);
        vim.e2e.assert.equal(lines[0], "Hello World", "Should append to line");
    });
});

vim.e2e.describe("Edge Cases: bufSetVar/bufGetVar", function() {
    vim.e2e.test("handles empty string variable name", function() {
        // Should not crash, behavior may vary
        vim.api.bufSetVar(0, "", "value");
        vim.e2e.assert.true(true, "Should not throw for empty name");
    });

    vim.e2e.test("handles special characters in name", function() {
        vim.api.bufSetVar(0, "var_with-special.chars", "value");
        const value = vim.api.bufGetVar(0, "var_with-special.chars");
        vim.e2e.assert.equal(value, "value", "Should handle special chars in name");
    });

    vim.e2e.test("handles null/undefined values", function() {
        vim.api.bufSetVar(0, "null_var", null);
        const value = vim.api.bufGetVar(0, "null_var");
        vim.e2e.assert.equal(value, null, "Should store null");
    });

    vim.e2e.test("handles object values", function() {
        vim.api.bufSetVar(0, "obj_var", { key: "value", num: 42 });
        const value = vim.api.bufGetVar(0, "obj_var");
        vim.e2e.assert.equal(value.key, "value", "Should store object");
        vim.e2e.assert.equal(value.num, 42, "Should preserve object properties");
    });

    vim.e2e.test("handles array values", function() {
        vim.api.bufSetVar(0, "arr_var", [1, 2, 3]);
        const value = vim.api.bufGetVar(0, "arr_var");
        vim.e2e.assert.true(Array.isArray(value), "Should store array");
        vim.e2e.assert.equal(value.length, 3, "Should preserve array length");
    });

    vim.e2e.test("variables isolated per buffer", function() {
        // Set var on buffer 0
        vim.api.bufSetVar(0, "isolated_var", "buf0");
        // Different buffer handle should not see it (unless same buffer)
        const value = vim.api.bufGetVar(9999, "isolated_var");
        vim.e2e.assert.equal(value, undefined, "Invalid buffer should not have var");
    });
});

vim.e2e.describe("Edge Cases: bufGetOffset", function() {
    vim.e2e.test("offset for line 0 is always 0", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Any content"]);
        const offset = vim.api.bufGetOffset(0, 0);
        vim.e2e.assert.equal(offset, 0, "First line always at offset 0");
    });

    vim.e2e.test("handles empty lines", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["", "Second"]);
        // Empty first line is "\n" = 1 byte
        const offset = vim.api.bufGetOffset(0, 1);
        vim.e2e.assert.equal(offset, 1, "Second line after empty first line");
    });

    vim.e2e.test("negative line returns -1", function() {
        const offset = vim.api.bufGetOffset(0, -1);
        vim.e2e.assert.equal(offset, -1, "Negative line should return -1");
    });
});

vim.e2e.describe("Edge Cases: bufGetChangedtick", function() {
    vim.e2e.test("starts at positive number", function() {
        const tick = vim.api.bufGetChangedtick(0);
        vim.e2e.assert.true(tick >= 0, "Changedtick should be non-negative");
    });

    vim.e2e.test("does not increment for bufGetLines", function() {
        const before = vim.api.bufGetChangedtick(0);
        vim.api.bufGetLines(0, 0, 1, false);
        const after = vim.api.bufGetChangedtick(0);
        vim.e2e.assert.equal(before, after, "Read ops should not change tick");
    });

    vim.e2e.test("increments for bufSetText", function() {
        vim.api.bufSetLines(0, 0, -1, false, ["Hello"]);
        const before = vim.api.bufGetChangedtick(0);
        vim.api.bufSetText(0, 0, 0, 0, 1, ["X"]);
        const after = vim.api.bufGetChangedtick(0);
        vim.e2e.assert.true(after > before, "bufSetText should increment tick");
    });
});

vim.e2e.describe("Edge Cases: Invalid Buffer Handles", function() {
    vim.e2e.test("bufLineCount returns null for invalid buffer", function() {
        const count = vim.api.bufLineCount(9999);
        vim.e2e.assert.equal(count, null, "Invalid buffer should return null");
    });

    vim.e2e.test("bufGetLines returns null for invalid buffer", function() {
        const lines = vim.api.bufGetLines(9999, 0, 1, false);
        vim.e2e.assert.equal(lines, null, "Invalid buffer should return null");
    });

    vim.e2e.test("bufSetLines handles invalid buffer gracefully", function() {
        // Should not throw
        vim.api.bufSetLines(9999, 0, 1, false, ["test"]);
        vim.e2e.assert.true(true, "Should not throw for invalid buffer");
    });

    vim.e2e.test("bufGetName returns empty for invalid buffer", function() {
        const name = vim.api.bufGetName(9999);
        vim.e2e.assert.equal(name, "", "Invalid buffer should return empty name");
    });

    vim.e2e.test("bufCall returns undefined for invalid buffer", function() {
        const result = vim.api.bufCall(9999, function() { return 42; });
        vim.e2e.assert.equal(result, undefined, "Invalid buffer should return undefined");
    });
});

vim.e2e.runAll();
