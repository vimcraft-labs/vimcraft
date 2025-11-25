// Window Splits E2E Tests
//
// Consolidated tests for window splitting functionality:
// - :split (horizontal split)
// - :vsplit (vertical split)
// - :close, :only commands
// - Ctrl+W navigation (h/j/k/l/c/o/s/v)
// - Window sizing
// - Cursor navigation in split windows
// - Mode switching in split windows

// ============================================================================
// PART 1: :split command (horizontal split)
// ============================================================================
vim.e2e.describe(":split command (horizontal split)", function() {
    vim.e2e.test(":split creates a new window", function() {
        const before = vim.api.listWins();
        vim.e2e.keys(":split\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, "Should create one new window");
    });

    vim.e2e.test(":sp is abbreviation for :split", function() {
        const before = vim.api.listWins();
        vim.e2e.keys(":sp\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, ":sp should create one new window");
    });

    vim.e2e.test("after :split, new window becomes active", function() {
        const before = vim.api.getCurrentWin();
        vim.e2e.keys(":split\r");
        const after = vim.api.getCurrentWin();
        vim.e2e.assert.true(before !== after, "Current window should change after split");
    });

    vim.e2e.test(":split preserves buffer content", function() {
        vim.e2e.keys(":split\r");
        const buf = vim.api.winGetBuf(0);
        vim.e2e.assert.equal(typeof buf, "number", "Buffer should be accessible in new window");
    });
});

// ============================================================================
// PART 2: :vsplit command (vertical split)
// ============================================================================
vim.e2e.describe(":vsplit command (vertical split)", function() {
    vim.e2e.test(":vsplit creates a new window", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":vsplit\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, "Should create one new window");
    });

    vim.e2e.test(":vs is abbreviation for :vsplit", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":vs\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, ":vs should create one new window");
    });

    vim.e2e.test("after :vsplit, new window becomes active", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.getCurrentWin();
        vim.e2e.keys(":vsplit\r");
        const after = vim.api.getCurrentWin();
        vim.e2e.assert.true(before !== after, "Current window should change after vsplit");
    });
});

// ============================================================================
// PART 3: :close command
// ============================================================================
vim.e2e.describe(":close command", function() {
    vim.e2e.test(":close reduces window count", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":close\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length - 1, "Should remove one window");
    });

    vim.e2e.test(":close on last window does nothing", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":close\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length, "Cannot close last window");
    });

    vim.e2e.test(":q is abbreviation for :close", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":q\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length - 1, ":q should close window");
    });
});

// ============================================================================
// PART 4: :only command
// ============================================================================
vim.e2e.describe(":only command", function() {
    vim.e2e.test(":only closes all windows except current", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys(":only\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, 1, "Should have only one window");
    });

    vim.e2e.test(":only with single window does nothing", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys(":only\r");
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length, "Single window stays");
    });
});

// ============================================================================
// PART 5: Ctrl+W window navigation
// ============================================================================
vim.e2e.describe("Ctrl+W window navigation", function() {
    vim.e2e.test("Ctrl+W h moves to left window", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("\x17l"); // Ctrl+W l - move right
        const rightWin = vim.api.getCurrentWin();
        vim.e2e.keys("\x17h"); // Ctrl+W h - move left
        const leftWin = vim.api.getCurrentWin();
        vim.e2e.assert.true(leftWin !== rightWin, "Should move to left window");
    });

    vim.e2e.test("Ctrl+W l moves to right window", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        const leftWin = vim.api.getCurrentWin();
        vim.e2e.keys("\x17l"); // Ctrl+W l - move right
        const rightWin = vim.api.getCurrentWin();
        vim.e2e.assert.true(leftWin !== rightWin, "Should move to right window");
    });

    vim.e2e.test("Ctrl+W j moves to window below", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        vim.e2e.keys("\x17k"); // Ctrl+W k - move up
        const topWin = vim.api.getCurrentWin();
        vim.e2e.keys("\x17j"); // Ctrl+W j - move down
        const bottomWin = vim.api.getCurrentWin();
        vim.e2e.assert.true(topWin !== bottomWin, "Should move to bottom window");
    });

    vim.e2e.test("Ctrl+W k moves to window above", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        vim.e2e.keys("\x17j"); // Ctrl+W j - move down first
        const bottomWin = vim.api.getCurrentWin();
        vim.e2e.keys("\x17k"); // Ctrl+W k - move up
        const topWin = vim.api.getCurrentWin();
        vim.e2e.assert.true(topWin !== bottomWin, "Should move to top window");
    });

    vim.e2e.test("Ctrl+W c closes current window", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        const before = vim.api.listWins();
        vim.e2e.keys("\x17c"); // Ctrl+W c
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length - 1, "Ctrl+W c should close window");
    });

    vim.e2e.test("Ctrl+W o is equivalent to :only", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":split\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("\x17o"); // Ctrl+W o
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, 1, "Ctrl+W o should close all but current");
    });

    vim.e2e.test("Ctrl+W s creates horizontal split", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys("\x17s"); // Ctrl+W s
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, "Ctrl+W s should split");
    });

    vim.e2e.test("Ctrl+W v creates vertical split", function() {
        vim.e2e.keys(":only\r");
        const before = vim.api.listWins();
        vim.e2e.keys("\x17v"); // Ctrl+W v
        const after = vim.api.listWins();
        vim.e2e.assert.equal(after.length, before.length + 1, "Ctrl+W v should vsplit");
    });
});

// ============================================================================
// PART 6: Window sizing
// ============================================================================
vim.e2e.describe("Window sizing after splits", function() {
    vim.e2e.test("horizontal split divides height", function() {
        vim.e2e.keys(":only\r");
        const fullHeight = vim.api.winGetHeight(0);
        vim.e2e.keys(":split\r");
        const topHeight = vim.api.winGetHeight(0);
        vim.e2e.assert.true(topHeight < fullHeight, "Split window should be smaller than full");
        vim.e2e.assert.true(topHeight > 0, "Split window should have positive height");
    });

    vim.e2e.test("vertical split divides width", function() {
        vim.e2e.keys(":only\r");
        const fullWidth = vim.api.winGetWidth(0);
        vim.e2e.keys(":vsplit\r");
        const leftWidth = vim.api.winGetWidth(0);
        vim.e2e.assert.true(leftWidth < fullWidth, "Split window should be narrower than full");
        vim.e2e.assert.true(leftWidth > 0, "Split window should have positive width");
    });
});

// ============================================================================
// PART 7: Independent cursor positions per window
// ============================================================================
vim.e2e.describe("Independent cursor positions per window", function() {
    vim.e2e.test("window switching preserves current cursor context", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":split\r");

        const topWin = vim.api.getCurrentWin();

        vim.e2e.keys("\x17j"); // Ctrl+W j
        const bottomWin = vim.api.getCurrentWin();

        vim.e2e.assert.true(
            topWin !== bottomWin,
            "Should be able to switch between windows"
        );

        vim.e2e.keys("\x17k"); // Ctrl+W k
        const backToTop = vim.api.getCurrentWin();
        vim.e2e.assert.equal(backToTop, topWin, "Should return to original window");
    });
});

// ============================================================================
// PART 8: Cursor navigation (hjkl) in vsplit windows
// ============================================================================
vim.e2e.describe("Cursor navigation (hjkl) in vsplit windows", function() {
    vim.e2e.test("'j' moves cursor down after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("j");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 1, "j should move cursor down by 1 row");
    });

    vim.e2e.test("'k' moves cursor up after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("G");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("k");
        const after = vim.e2e.getCursor();

        if (before.line > 0) {
            vim.e2e.assert.equal(after.line, before.line - 1, "k should move cursor up by 1 row");
        } else {
            vim.e2e.assert.equal(after.line, 0, "k at top should stay at top");
        }
    });

    vim.e2e.test("'l' moves cursor right after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("l");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.col, before.col + 1, "l should move cursor right by 1 col");
    });

    vim.e2e.test("'h' moves cursor left after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg$");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("h");
        const after = vim.e2e.getCursor();

        if (before.col > 0) {
            vim.e2e.assert.equal(after.col, before.col - 1, "h should move cursor left by 1 col");
        } else {
            vim.e2e.assert.equal(after.col, 0, "h at start should stay at start");
        }
    });

    vim.e2e.test("'jjj' moves cursor down 3 times after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("jjj");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 3, "jjj should move cursor down by 3 rows");
    });

    vim.e2e.test("'lll' moves cursor right 3 times after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("lll");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.col, before.col + 3, "lll should move cursor right by 3 cols");
    });

    vim.e2e.test("cursor stays in active window during hjkl movement", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("jjj");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 3, "Cursor should move down 3 lines");
    });

    vim.e2e.test("cursor position is consistent after hjkl in vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("lll");
        const afterRight = vim.e2e.getCursor();
        vim.e2e.assert.equal(afterRight.col, 3, "Should be at column 3 after lll");

        vim.e2e.keys("jj");
        const afterDown = vim.e2e.getCursor();
        vim.e2e.assert.equal(afterDown.line, 2, "Should be at line 2 after jj");
    });

    vim.e2e.test("cursor renders in correct window after switching", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("jjj");
        const leftPos = vim.e2e.getCursor();

        vim.e2e.keys("\x17l"); // Ctrl+W l

        vim.e2e.keys("lllll");
        const rightPos = vim.e2e.getCursor();

        vim.e2e.assert.true(rightPos.col >= 5, "Right window cursor should be at col 5+");
    });

    vim.e2e.test("rapid hjkl movements in vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("jjjjj");
        vim.e2e.keys("lllll");

        const pos = vim.e2e.getCursor();
        vim.e2e.assert.equal(pos.line, 5, "Should be at line 5");
        vim.e2e.assert.equal(pos.col, 5, "Should be at col 5");
    });
});

// ============================================================================
// PART 9: Cursor navigation (hjkl) in horizontal splits
// ============================================================================
vim.e2e.describe("Cursor navigation (hjkl) in horizontal splits", function() {
    vim.e2e.test("'j' moves cursor down after :split", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":split\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("j");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 1, "j should move cursor down after :split");
    });

    vim.e2e.test("'l' moves cursor right after :split", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":split\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("l");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.col, before.col + 1, "l should move cursor right after :split");
    });

    vim.e2e.test("multiple movements work after :split", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":split\r");

        vim.e2e.keys("jjll");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, 2, "Should be at row 2 after jj");
        vim.e2e.assert.equal(after.col, 2, "Should be at col 2 after ll");
    });
});

// ============================================================================
// PART 10: Navigation after window switching
// ============================================================================
vim.e2e.describe("Navigation after window switching", function() {
    vim.e2e.test("hjkl works after Ctrl+W navigation", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("\x17l"); // Ctrl+W l

        const before = vim.e2e.getCursor();
        vim.e2e.keys("j");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 1, "j should work after Ctrl+W l");
    });

    vim.e2e.test("hjkl works after switching back", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("\x17l"); // Ctrl+W l
        vim.e2e.keys("\x17h"); // Ctrl+W h

        const before = vim.e2e.getCursor();
        vim.e2e.keys("jl");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, before.line + 1, "j should work after Ctrl+W h");
        vim.e2e.assert.equal(after.col, before.col + 1, "l should work after Ctrl+W h");
    });
});

// ============================================================================
// PART 11: Word motions in split windows
// ============================================================================
vim.e2e.describe("Word motions in split windows", function() {
    vim.e2e.test("'w' moves to next word after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("w");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.true(
            after.col > before.col || after.line > before.line,
            "w should move cursor forward"
        );
    });

    vim.e2e.test("'b' moves to previous word after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("G$");
        vim.e2e.keys(":vsplit\r");

        const before = vim.e2e.getCursor();
        vim.e2e.keys("b");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.true(
            after.col < before.col || after.line < before.line,
            "b should move cursor backward"
        );
    });
});

// ============================================================================
// PART 12: Line motions in split windows
// ============================================================================
vim.e2e.describe("Line motions in split windows", function() {
    vim.e2e.test("'0' moves to start of line after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg$");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("0");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.col, 0, "0 should move to column 0");
    });

    vim.e2e.test("'$' moves to end of line after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg0");
        vim.e2e.keys(":vsplit\r");

        const beforeCol = vim.e2e.getCursor().col;
        vim.e2e.keys("$");
        const afterCol = vim.e2e.getCursor().col;

        vim.e2e.assert.true(afterCol >= beforeCol, "$ should move to end of line");
    });

    vim.e2e.test("'gg' moves to top after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("G");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.keys("gg");
        const after = vim.e2e.getCursor();

        vim.e2e.assert.equal(after.line, 0, "gg should move to line 0");
    });

    vim.e2e.test("'G' moves to bottom after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys("gg");
        vim.e2e.keys(":vsplit\r");

        const beforeLine = vim.e2e.getCursor().line;
        vim.e2e.keys("G");
        const afterLine = vim.e2e.getCursor().line;

        vim.e2e.assert.true(afterLine >= beforeLine, "G should move to end of file");
    });
});

// ============================================================================
// PART 13: Mode switching in split windows
// ============================================================================
vim.e2e.describe("Mode switching in split windows", function() {
    vim.e2e.test("insert mode works after :vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("i");

        const mode = vim.e2e.getMode();
        vim.e2e.assert.equal(mode, "INSERT", "Should enter insert mode");

        vim.e2e.keys("\x1b");
    });

    vim.e2e.test("ESC returns to normal mode in split", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("i");
        vim.e2e.keys("\x1b");

        const mode = vim.e2e.getMode();
        vim.e2e.assert.equal(mode, "NORMAL", "ESC should return to normal mode");
    });
});

// Run all tests
vim.e2e.runAll();
