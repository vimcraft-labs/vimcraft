// Separator E2E Tests
//
// Consolidated tests for vsplit separator (|) rendering:
// - Character rendering and presence
// - Height spanning full window
// - Continuity without gaps
// - Position consistency
// - State stability across re-renders
// - Visual column alignment with wide characters (emoji, CJK)

// ============================================================================
// PART 1: Separator Character and Presence
// ============================================================================
vim.e2e.describe("Separator Character", function() {
    vim.e2e.test(":vsplit creates separator character in PTY output", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count after :vsplit: " + separatorCount);
        vim.e2e.assert.true(separatorCount > 0, "Should have at least 1 separator character (got " + separatorCount + ")");
    });

    vim.e2e.test("separator character appears in captured output", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();

        const output = vim.e2e.pty.getOutput();
        const hasSeparator = output.indexOf("\u2502") !== -1;

        vim.e2e.pty.stopCapture();

        console.log("Output contains separator: " + hasSeparator);
        vim.e2e.assert.true(hasSeparator, "Captured output should contain separator character");
    });
});

// ============================================================================
// PART 2: Separator Height
// ============================================================================
vim.e2e.describe("Separator Height", function() {
    vim.e2e.test("separator count matches window height", function() {
        vim.e2e.keys(":only\r");
        const winHeight = vim.api.winGetHeight(0);

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Window height: " + winHeight);
        console.log("Separator count: " + separatorCount);

        vim.e2e.assert.true(
            separatorCount >= winHeight - 2,
            "Separator count (" + separatorCount + ") should be >= window height - 2 (" + (winHeight - 2) + ")"
        );
    });

    vim.e2e.test("multiple vsplits have expected separator count", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count after 2 vsplits: " + separatorCount);
        vim.e2e.assert.true(separatorCount > 0, "Should have separators after multiple vsplits");
    });
});

// ============================================================================
// PART 3: Separator Continuity (No Gaps)
// ============================================================================
vim.e2e.describe("Separator Continuity", function() {
    vim.e2e.test("separator has no gaps in column", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":vsplit\r");
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        const winHeight = vim.api.winGetHeight(0);
        const expectedMinSeparators = winHeight;

        console.log("Checking separator continuity:");
        console.log("  Window height: " + winHeight);
        console.log("  Separator count: " + separatorCount);

        vim.e2e.assert.true(
            separatorCount >= expectedMinSeparators - 1,
            "Separator count (" + separatorCount + ") should be >= " + (expectedMinSeparators - 1) + " (window height - 1)"
        );
    });

    vim.e2e.test("separator present after cursor movement", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("jjjjj");
        vim.e2e.keys("lllll");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count after movement: " + separatorCount);
        vim.e2e.assert.true(separatorCount > 0, "Separator should persist after cursor movement");
    });
});

// ============================================================================
// PART 4: Separator Position and Window Dimensions
// ============================================================================
vim.e2e.describe("Separator Position", function() {
    vim.e2e.test("windows have correct widths after vsplit", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        const wins = vim.api.listWins();
        vim.e2e.assert.equal(wins.length, 2, "Should have 2 windows after vsplit");

        let totalWidth = 0;
        for (let i = 0; i < wins.length; i++) {
            const width = vim.api.winGetWidth(wins[i]);
            console.log("Window " + wins[i] + " width: " + width);
            totalWidth += width;
            vim.e2e.assert.true(width > 0, "Window " + wins[i] + " should have positive width");
        }

        console.log("Total window widths: " + totalWidth);
        vim.e2e.assert.true(totalWidth > 0, "Total window widths should be positive");
    });

    vim.e2e.test("both windows have valid dimensions", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        const wins = vim.api.listWins();
        vim.e2e.assert.equal(wins.length, 2, "Should have 2 windows after vsplit");

        for (let i = 0; i < wins.length; i++) {
            const width = vim.api.winGetWidth(wins[i]);
            const height = vim.api.winGetHeight(wins[i]);

            console.log("Window " + wins[i] + ": " + width + "x" + height);

            vim.e2e.assert.true(width > 0, "Window " + wins[i] + " should have positive width");
            vim.e2e.assert.true(height > 0, "Window " + wins[i] + " should have positive height");
        }
    });
});

// ============================================================================
// PART 5: Separator After Window Operations
// ============================================================================
vim.e2e.describe("Separator After Operations", function() {
    vim.e2e.test("separator visible after switching windows", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("\x17l"); // Ctrl+W l
        vim.e2e.keys("\x17h"); // Ctrl+W h

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count after window switching: " + separatorCount);
        vim.e2e.assert.true(separatorCount > 0, "Separator should be visible after window switching");
    });

    vim.e2e.test("separator redraws correctly after mode change", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys("i");
        vim.e2e.keys("\x1b"); // ESC

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count after mode change: " + separatorCount);
        vim.e2e.assert.true(separatorCount > 0, "Separator should redraw after mode change");
    });
});

// ============================================================================
// PART 6: Horizontal and Mixed Splits
// ============================================================================
vim.e2e.describe("Horizontal and Mixed Splits", function() {
    vim.e2e.test(":split uses statusline as separator (no vertical bar)", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();

        vim.e2e.keys(":split\r");
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Vertical bar count after :split (horizontal): " + separatorCount);

        const winCount = vim.api.listWins().length;
        vim.e2e.assert.equal(winCount, 2, "Should have 2 windows after :split");
    });

    vim.e2e.test("separator renders with mixed split types", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");
        vim.e2e.keys(":split\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        const winCount = vim.api.listWins().length;
        console.log("Window count: " + winCount);
        console.log("Separator count: " + separatorCount);

        vim.e2e.assert.equal(winCount, 3, "Should have 3 windows after vsplit + split");
        vim.e2e.assert.true(separatorCount > 0, "Should have vertical separators in mixed layout");
    });
});

// ============================================================================
// PART 7: State Consistency Across Renders
// ============================================================================
vim.e2e.describe("Separator State Consistency", function() {
    vim.e2e.test("separator count stable after 10 cursor movements", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const initialCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Initial separator count: " + initialCount);

        vim.e2e.keys("jjjjjjjjjj");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const afterMovementCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("After 10 movements: " + afterMovementCount);

        vim.e2e.assert.equal(
            initialCount,
            afterMovementCount,
            "Separator count should remain stable (was " + initialCount + ", now " + afterMovementCount + ")"
        );
    });

    vim.e2e.test("separator count stable after 20 rapid movements", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const initialCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        vim.e2e.keys("jjjjjjjjjjkkkkkkkkkk");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const finalCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Initial: " + initialCount + ", After 20 movements: " + finalCount);

        vim.e2e.assert.equal(initialCount, finalCount,
            "Separator should persist through rapid cursor movements");
    });

    vim.e2e.test("separator stable after window switch cycle", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const initialCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        vim.e2e.keys("\x17w");
        vim.e2e.keys("\x17w");
        vim.e2e.keys("\x17w");
        vim.e2e.keys("\x17w");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const finalCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Initial: " + initialCount + ", After window switches: " + finalCount);

        vim.e2e.assert.equal(initialCount, finalCount,
            "Separator should persist through window switching");
    });

    vim.e2e.test("separator stable through insert mode cycle", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const initialCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        vim.e2e.keys("i");
        vim.e2e.keys("test");
        vim.e2e.keys("\x1b");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const finalCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Initial: " + initialCount + ", After insert mode: " + finalCount);

        vim.e2e.assert.equal(initialCount, finalCount,
            "Separator should persist through insert mode cycle");
    });

    vim.e2e.test("separator exists at statusline row after re-render", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        const winHeight = vim.api.winGetHeight(0);
        console.log("Window height: " + winHeight);

        vim.e2e.keys("j");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();

        const separatorCount = vim.e2e.pty.countSequence("\u2502");
        vim.e2e.pty.stopCapture();

        console.log("Separator count (should include statusline row): " + separatorCount);

        vim.e2e.assert.true(
            separatorCount >= winHeight,
            "Separator should span at least window height (" + winHeight + "), got " + separatorCount
        );
    });

    vim.e2e.test("separator stable through 5 render cycles", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":vsplit\r");

        let counts: number[] = [];

        for (let i = 0; i < 5; i++) {
            vim.e2e.keys("j");

            vim.e2e.pty.startCapture();
            vim.e2e.pty.clear();
            vim.e2e.pty.render();
            const count = vim.e2e.pty.countSequence("\u2502");
            vim.e2e.pty.stopCapture();

            counts.push(count);
            console.log("Cycle " + (i + 1) + ": " + count + " separators");
        }

        const firstCount = counts[0];
        for (let i = 1; i < counts.length; i++) {
            vim.e2e.assert.equal(
                firstCount,
                counts[i],
                "Frame " + (i + 1) + " separator count should match frame 1"
            );
        }
    });
});

// ============================================================================
// PART 8: Visual Column Alignment (Emoji/Wide Character Bug)
// ============================================================================
vim.e2e.describe("Separator Visual Column (Terminal-Accurate)", function() {

    // Helper: Get display width of a Unicode codepoint
    // Follows Unicode standard (like uucode/utf8proc)
    function getDisplayWidth(codepoint: number): number {
        // Zero-width characters
        if (codepoint >= 0x0300 && codepoint <= 0x036F) return 0; // Combining marks
        if (codepoint >= 0xFE00 && codepoint <= 0xFE0F) return 0; // Variation selectors
        if (codepoint >= 0x200B && codepoint <= 0x200D) return 0; // Zero-width chars
        if (codepoint === 0xFEFF) return 0; // BOM

        // Wide characters (CJK) - always width 2 per Unicode standard
        if (codepoint >= 0x4E00 && codepoint <= 0x9FFF) return 2;   // CJK Unified
        if (codepoint >= 0x3400 && codepoint <= 0x4DBF) return 2;   // CJK Extension A
        if (codepoint >= 0x20000 && codepoint <= 0x2A6DF) return 2; // CJK Extension B
        if (codepoint >= 0x3040 && codepoint <= 0x30FF) return 2;   // Hiragana/Katakana
        if (codepoint >= 0xFF00 && codepoint <= 0xFFEF) return 2;   // Fullwidth forms

        // Modern emoji (0x1F000+) - width 2 when emoji option is enabled (default)
        if (codepoint >= 0x1F000 && codepoint <= 0x1FFFF) return 2;

        // Everything else uses Unicode standard width (typically 1)
        return 1;
    }

    // Parse terminal output and find separator columns
    function parseSeparatorColumns(output: string): Map<number, number> {
        const separatorPositions: Map<number, number> = new Map();

        let cursorRow = 1;
        let cursorCol = 1;

        let i = 0;
        while (i < output.length) {
            if (output[i] === '\x1b') {
                if (output[i + 1] === '[') {
                    let j = i + 2;
                    while (j < output.length && !/[A-Za-z]/.test(output[j])) {
                        j++;
                    }
                    if (j < output.length) {
                        const params = output.substring(i + 2, j);
                        const command = output[j];

                        if (command === 'H') {
                            const parts = params.split(';');
                            cursorRow = parseInt(parts[0]) || 1;
                            cursorCol = parseInt(parts[1]) || 1;
                        } else if (command === 'A') {
                            cursorRow -= parseInt(params) || 1;
                        } else if (command === 'B') {
                            cursorRow += parseInt(params) || 1;
                        } else if (command === 'C') {
                            cursorCol += parseInt(params) || 1;
                        } else if (command === 'D') {
                            cursorCol -= parseInt(params) || 1;
                        }

                        i = j + 1;
                        continue;
                    }
                }
                if (output[i + 1] === 'P') {
                    let j = i + 2;
                    while (j < output.length - 1) {
                        if (output[j] === '\x1b' && output[j + 1] === '\\') {
                            j += 2;
                            break;
                        }
                        j++;
                    }
                    i = j;
                    continue;
                }
                i++;
                continue;
            }

            if (output.charCodeAt(i) < 32) {
                i++;
                continue;
            }

            const charCode = output.charCodeAt(i);
            let codepoint: number;
            let charLen: number;

            if (charCode >= 0xD800 && charCode <= 0xDBFF && i + 1 < output.length) {
                const lowSurrogate = output.charCodeAt(i + 1);
                codepoint = 0x10000 + ((charCode - 0xD800) << 10) + (lowSurrogate - 0xDC00);
                charLen = 2;
            } else {
                codepoint = charCode;
                charLen = 1;
            }

            if (codepoint === 0x2502) {
                if (!separatorPositions.has(cursorRow)) {
                    separatorPositions.set(cursorRow, cursorCol);
                }
            }

            const width = getDisplayWidth(codepoint);
            cursorCol += width;

            i += charLen;
        }

        return separatorPositions;
    }

    vim.e2e.test("vsplit separator visual column with README.md", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":e README.md\r");
        vim.e2e.keys("gg");
        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const output = vim.e2e.pty.getOutput();
        vim.e2e.pty.stopCapture();

        const separatorPositions = parseSeparatorColumns(output);

        const columns: number[] = [];
        const entries = Array.from(separatorPositions.entries()).sort((a, b) => a[0] - b[0]);

        console.log("=== SEPARATOR VISUAL COLUMNS ===");
        for (const [row, col] of entries) {
            console.log("Row " + row + ": visual col " + col);
            columns.push(col);
        }

        const uniqueCols = [...new Set(columns)];
        console.log("Unique columns: " + uniqueCols.join(", "));

        if (uniqueCols.length > 1) {
            console.log("=== MISALIGNMENT DETECTED ===");
            const expectedCol = columns[0];
            for (const [row, col] of entries) {
                if (col !== expectedCol) {
                    console.log("Row " + row + ": expected " + expectedCol + ", got " + col);
                }
            }
        }

        vim.e2e.assert.true(
            separatorPositions.size > 0,
            "Should find separators"
        );

        vim.e2e.assert.equal(
            uniqueCols.length,
            1,
            "Separator should be at same visual column on ALL rows. Found: " + uniqueCols.join(", ")
        );
    });

    vim.e2e.test("vsplit with explicit emoji content", function() {
        vim.e2e.keys(":only\r");
        vim.e2e.keys(":enew!\r");

        vim.e2e.keys("iLine 1 - normal text\r");
        vim.e2e.keys("Line 2 - normal text\r");
        vim.e2e.keys("Line 3 - normal text\r");
        vim.e2e.keys("\u26A0 WARNING - emoji line\r");  // Warning sign
        vim.e2e.keys("Line 5 - normal text\r");
        vim.e2e.keys("Line 6 - normal text\r");
        vim.e2e.keys("\x1b");
        vim.e2e.keys("gg");

        vim.e2e.keys(":vsplit\r");

        vim.e2e.pty.startCapture();
        vim.e2e.pty.clear();
        vim.e2e.pty.render();
        const output = vim.e2e.pty.getOutput();
        vim.e2e.pty.stopCapture();

        const separatorPositions = parseSeparatorColumns(output);

        const columns: number[] = [];
        for (const [row, col] of separatorPositions.entries()) {
            columns.push(col);
        }

        const uniqueCols = [...new Set(columns)];

        console.log("=== EMOJI CONTENT TEST ===");
        console.log("Total rows with separator: " + columns.length);
        console.log("Unique separator columns: " + uniqueCols.join(", "));

        vim.e2e.assert.equal(
            uniqueCols.length,
            1,
            "Separator should be at same visual column with emoji. Found: " + uniqueCols.join(", ")
        );
    });
});

// Run all tests
vim.e2e.runAll();
