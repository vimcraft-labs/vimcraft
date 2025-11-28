// Extmarks API E2E Tests
// Tests vim.api.bufSetExtmark, bufGetExtmarks, bufDelExtmark, bufGetExtmarkById
vim.e2e.describe('Extmarks API', function () {
    vim.e2e.test('bufSetExtmark creates extmark and returns ID', function () {
        const ns = vim.api.createNamespace('extmark-test-1');
        const buf = vim.api.getCurrentBuf();
        // Create an extmark at line 0, col 0
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        // ID should be positive
        vim.e2e.assert.true(id > 0, 'extmark ID should be positive');
    });
    vim.e2e.test('bufSetExtmark with custom ID', function () {
        const ns = vim.api.createNamespace('extmark-test-2');
        const buf = vim.api.getCurrentBuf();
        // Create an extmark with custom ID
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, { id: 42 });
        vim.e2e.assert.equal(id, 42, 'should return the custom ID');
    });
    vim.e2e.test('bufGetExtmarks returns extmarks in range', function () {
        const ns = vim.api.createNamespace('extmark-test-3');
        const buf = vim.api.getCurrentBuf();
        // Create multiple extmarks
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufSetExtmark(buf, ns, 0, 5, {});
        vim.api.bufSetExtmark(buf, ns, 1, 0, {});
        // Get all extmarks (line 0 to line 100)
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, 100);
        // Should have at least 3 extmarks
        vim.e2e.assert.true(extmarks.length >= 3, 'should have at least 3 extmarks');
        // Each extmark should be [id, line, col]
        vim.e2e.assert.true(Array.isArray(extmarks[0]), 'extmark should be an array');
        vim.e2e.assert.true(extmarks[0].length === 3, 'extmark should have 3 elements [id, line, col]');
    });
    vim.e2e.test('bufDelExtmark removes extmark', function () {
        const ns = vim.api.createNamespace('extmark-test-4');
        const buf = vim.api.getCurrentBuf();
        // Create an extmark
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        // Delete it
        const deleted = vim.api.bufDelExtmark(buf, ns, id);
        vim.e2e.assert.true(deleted, 'bufDelExtmark should return true');
        // Try to delete again - should return false
        const deletedAgain = vim.api.bufDelExtmark(buf, ns, id);
        vim.e2e.assert.true(!deletedAgain, 'deleting non-existent extmark should return false');
    });
    vim.e2e.test('bufGetExtmarkById returns position', function () {
        const ns = vim.api.createNamespace('extmark-test-5');
        const buf = vim.api.getCurrentBuf();
        // Create an extmark at specific position
        const id = vim.api.bufSetExtmark(buf, ns, 2, 5, {});
        // Get it by ID
        const pos = vim.api.bufGetExtmarkById(buf, ns, id, {});
        vim.e2e.assert.true(pos !== null, 'should find the extmark');
        vim.e2e.assert.true(Array.isArray(pos), 'position should be an array');
        if (pos) {
            vim.e2e.assert.equal(pos[0], 2, 'line should be 2');
            vim.e2e.assert.equal(pos[1], 5, 'col should be 5');
        }
    });
    vim.e2e.test('bufGetExtmarkById returns null for non-existent ID', function () {
        const ns = vim.api.createNamespace('extmark-test-6');
        const buf = vim.api.getCurrentBuf();
        // Get non-existent extmark
        const pos = vim.api.bufGetExtmarkById(buf, ns, 99999, {});
        vim.e2e.assert.true(pos === null, 'should return null for non-existent extmark');
    });
    vim.e2e.test('extmarks are namespace-isolated', function () {
        const ns1 = vim.api.createNamespace('extmark-ns-1');
        const ns2 = vim.api.createNamespace('extmark-ns-2');
        const buf = vim.api.getCurrentBuf();
        // Create extmarks in different namespaces
        const id1 = vim.api.bufSetExtmark(buf, ns1, 0, 0, {});
        const id2 = vim.api.bufSetExtmark(buf, ns2, 0, 0, {});
        // Each namespace should only see its own extmarks
        const extmarks1 = vim.api.bufGetExtmarks(buf, ns1, 0, 100);
        const extmarks2 = vim.api.bufGetExtmarks(buf, ns2, 0, 100);
        // Find the specific extmarks we created
        const found1 = extmarks1.some(function (e) { return e[0] === id1; });
        const found2 = extmarks2.some(function (e) { return e[0] === id2; });
        vim.e2e.assert.true(found1, 'ns1 should find its extmark');
        vim.e2e.assert.true(found2, 'ns2 should find its extmark');
        // Cross-check: ns1 shouldn't see ns2's extmark
        const crossFound = extmarks1.some(function (e) { return e[0] === id2; });
        vim.e2e.assert.true(!crossFound, 'ns1 should not see ns2 extmark');
    });
    vim.e2e.test('bufSetExtmark with end position', function () {
        const ns = vim.api.createNamespace('extmark-test-7');
        const buf = vim.api.getCurrentBuf();
        // Create extmark with end position (for ranges)
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {
            endLine: 1,
            endCol: 5
        });
        vim.e2e.assert.true(id > 0, 'should create extmark with end position');
    });
    vim.e2e.test('bufSetExtmark with highlight group', function () {
        const ns = vim.api.createNamespace('extmark-test-8');
        const buf = vim.api.getCurrentBuf();
        // Create extmark with highlight group
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {
            hlGroup: 'Error',
            endCol: 10
        });
        vim.e2e.assert.true(id > 0, 'should create extmark with highlight group');
    });
    vim.e2e.test('bufGetExtmarks with Neovim-compatible positions', function () {
        const ns = vim.api.createNamespace('extmark-test-9');
        const buf = vim.api.getCurrentBuf();
        // Create extmarks at various positions
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufSetExtmark(buf, ns, 1, 3, {});
        vim.api.bufSetExtmark(buf, ns, 2, 5, {});
        // Test 0 = buffer start, -1 = buffer end (Neovim convention)
        const allExtmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, {});
        vim.e2e.assert.true(allExtmarks.length >= 3, 'should get all extmarks with 0 to -1');
        // Test [line, col] array positions
        const rangeExtmarks = vim.api.bufGetExtmarks(buf, ns, [0, 0], [1, 10], {});
        vim.e2e.assert.true(rangeExtmarks.length >= 2, 'should get extmarks in [0,0] to [1,10] range');
    });
    vim.e2e.test('bufGetExtmarks with limit option', function () {
        const ns = vim.api.createNamespace('extmark-test-10');
        const buf = vim.api.getCurrentBuf();
        // Create multiple extmarks
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufSetExtmark(buf, ns, 0, 5, {});
        vim.api.bufSetExtmark(buf, ns, 1, 0, {});
        vim.api.bufSetExtmark(buf, ns, 2, 0, {});
        // Get with limit
        const limited = vim.api.bufGetExtmarks(buf, ns, 0, -1, { limit: 2 });
        vim.e2e.assert.equal(limited.length, 2, 'should respect limit option');
    });
    vim.e2e.test('bufGetExtmarks with details option', function () {
        const ns = vim.api.createNamespace('extmark-test-11');
        const buf = vim.api.getCurrentBuf();
        // Create extmark with end position and highlight
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {
            endLine: 1,
            endCol: 5,
            hlGroup: 'Comment'
        });
        // Get with details
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { details: true });
        // Find our extmark
        const found = extmarks.find(function (e) { return e[0] === id; });
        vim.e2e.assert.true(found !== undefined, 'should find the extmark');
        if (found && found.length === 4) {
            const details = found[3];
            vim.e2e.assert.equal(details.endLine, 1, 'details should have endLine');
            vim.e2e.assert.equal(details.endCol, 5, 'details should have endCol');
            vim.e2e.assert.equal(details.hlGroup, 'Comment', 'details should have hlGroup');
        }
    });
    // TDD: New test for extmark ID as start/end position (Neovim feature)
    vim.e2e.test('bufGetExtmarks with extmark ID as position', function () {
        const ns = vim.api.createNamespace('extmark-test-12');
        const buf = vim.api.getCurrentBuf();
        // Create extmarks at different positions
        const id1 = vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        const id2 = vim.api.bufSetExtmark(buf, ns, 1, 5, {});
        const id3 = vim.api.bufSetExtmark(buf, ns, 2, 10, {});
        // Use extmark ID as start position - should get extmarks from that position onwards
        // In Neovim, passing a positive integer (extmark ID) uses that extmark's position
        const fromId2 = vim.api.bufGetExtmarks(buf, ns, id2, -1, {});
        // Should get id2 and id3 (extmarks from id2's position to end)
        vim.e2e.assert.true(fromId2.length >= 2, 'should get extmarks from id2 position onwards');
        // First result should be id2
        vim.e2e.assert.equal(fromId2[0][0], id2, 'first extmark should be id2');
    });
    // Edge case: empty namespace returns empty array
    vim.e2e.test('bufGetExtmarks on empty namespace returns empty array', function () {
        const ns = vim.api.createNamespace('extmark-empty-ns');
        const buf = vim.api.getCurrentBuf();
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, {});
        vim.e2e.assert.equal(extmarks.length, 0, 'empty namespace should return empty array');
    });
    // Edge case: deleting extmark that was already deleted
    vim.e2e.test('bufDelExtmark on already deleted extmark returns false', function () {
        const ns = vim.api.createNamespace('extmark-del-twice');
        const buf = vim.api.getCurrentBuf();
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufDelExtmark(buf, ns, id);
        const result = vim.api.bufDelExtmark(buf, ns, id);
        vim.e2e.assert.true(!result, 'second delete should return false');
    });
    // Edge case: bufGetExtmarkById with details option
    vim.e2e.test('bufGetExtmarkById with details returns extended info', function () {
        const ns = vim.api.createNamespace('extmark-byid-details');
        const buf = vim.api.getCurrentBuf();
        const id = vim.api.bufSetExtmark(buf, ns, 1, 3, {
            endLine: 2,
            endCol: 7,
            hlGroup: 'Warning'
        });
        const pos = vim.api.bufGetExtmarkById(buf, ns, id, { details: true });
        vim.e2e.assert.true(pos !== null, 'should find extmark');
        if (pos) {
            vim.e2e.assert.equal(pos[0], 1, 'line should be 1');
            vim.e2e.assert.equal(pos[1], 3, 'col should be 3');
            // With details, should have 3rd element
            if (pos.length === 3) {
                const details = pos[2];
                vim.e2e.assert.equal(details.endLine, 2, 'endLine should be 2');
                vim.e2e.assert.equal(details.endCol, 7, 'endCol should be 7');
                vim.e2e.assert.equal(details.hlGroup, 'Warning', 'hlGroup should be Warning');
            }
        }
    });
    // Edge case: updating extmark by reusing ID
    vim.e2e.test('bufSetExtmark with existing ID updates position', function () {
        const ns = vim.api.createNamespace('extmark-update-id');
        const buf = vim.api.getCurrentBuf();
        // Create extmark with custom ID
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, { id: 100 });
        vim.e2e.assert.equal(id, 100, 'should return custom ID');
        // Update same extmark to new position
        const id2 = vim.api.bufSetExtmark(buf, ns, 2, 5, { id: 100 });
        vim.e2e.assert.equal(id2, 100, 'should return same ID');
        // Verify new position
        const pos = vim.api.bufGetExtmarkById(buf, ns, 100, {});
        vim.e2e.assert.true(pos !== null, 'should find extmark');
        if (pos) {
            vim.e2e.assert.equal(pos[0], 2, 'line should be updated to 2');
            vim.e2e.assert.equal(pos[1], 5, 'col should be updated to 5');
        }
        // Should only have one extmark with this ID
        const all = vim.api.bufGetExtmarks(buf, ns, 0, -1, {});
        const count = all.filter(function (e) { return e[0] === 100; }).length;
        vim.e2e.assert.equal(count, 1, 'should only have one extmark with ID 100');
    });
    // Edge case: limit=0 should return empty
    vim.e2e.test('bufGetExtmarks with limit=0 returns empty', function () {
        const ns = vim.api.createNamespace('extmark-limit-zero');
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufSetExtmark(buf, ns, 1, 0, {});
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { limit: 0 });
        vim.e2e.assert.equal(extmarks.length, 0, 'limit=0 should return empty');
    });
    // Edge case: extmarks sorted by position
    vim.e2e.test('bufGetExtmarks returns extmarks sorted by position', function () {
        const ns = vim.api.createNamespace('extmark-sorted');
        const buf = vim.api.getCurrentBuf();
        // Create extmarks in reverse order
        vim.api.bufSetExtmark(buf, ns, 2, 0, {});
        vim.api.bufSetExtmark(buf, ns, 0, 5, {});
        vim.api.bufSetExtmark(buf, ns, 1, 3, {});
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, {});
        // Should be sorted: (0,0), (0,5), (1,3), (2,0)
        vim.e2e.assert.true(extmarks.length >= 4, 'should have 4 extmarks');
        // Verify ordering
        for (let i = 1; i < extmarks.length; i++) {
            const prev = extmarks[i - 1];
            const curr = extmarks[i];
            const prevPos = prev[1] * 10000 + prev[2];
            const currPos = curr[1] * 10000 + curr[2];
            vim.e2e.assert.true(prevPos <= currPos, 'extmarks should be sorted by position');
        }
    });
    // Edge case: [line, col] range that excludes some extmarks
    vim.e2e.test('bufGetExtmarks with precise [line, col] range', function () {
        const ns = vim.api.createNamespace('extmark-precise-range');
        const buf = vim.api.getCurrentBuf();
        vim.api.bufSetExtmark(buf, ns, 0, 0, {}); // before range
        vim.api.bufSetExtmark(buf, ns, 0, 5, {}); // at start
        vim.api.bufSetExtmark(buf, ns, 1, 3, {}); // in range
        vim.api.bufSetExtmark(buf, ns, 2, 0, {}); // at end
        vim.api.bufSetExtmark(buf, ns, 2, 5, {}); // after range
        // Get extmarks from [0,5] to [2,0]
        const extmarks = vim.api.bufGetExtmarks(buf, ns, [0, 5], [2, 0], {});
        // Should include (0,5), (1,3), (2,0) but not (0,0) or (2,5)
        vim.e2e.assert.true(extmarks.length >= 3, 'should have at least 3 extmarks in range');
        // Verify no extmark before [0,5]
        const beforeRange = extmarks.some(function (e) {
            return e[1] === 0 && e[2] < 5;
        });
        vim.e2e.assert.true(!beforeRange, 'should not include extmarks before [0,5]');
    });
    // Edge case: priority is preserved
    vim.e2e.test('bufSetExtmark preserves priority in details', function () {
        const ns = vim.api.createNamespace('extmark-priority');
        const buf = vim.api.getCurrentBuf();
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {
            priority: 150
        });
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { details: true });
        const found = extmarks.find(function (e) { return e[0] === id; });
        vim.e2e.assert.true(found !== undefined, 'should find extmark');
        if (found && found.length === 4) {
            const details = found[3];
            vim.e2e.assert.equal(details.priority, 150, 'priority should be 150');
        }
    });
    // Edge case: negative line/col should return 0 (no extmark created)
    vim.e2e.test('bufSetExtmark with negative line returns 0', function () {
        const ns = vim.api.createNamespace('extmark-negative-line');
        const buf = vim.api.getCurrentBuf();
        // Negative line should fail gracefully
        const id = vim.api.bufSetExtmark(buf, ns, -1, 0, {});
        vim.e2e.assert.equal(id, 0, 'negative line should return 0');
    });
    vim.e2e.test('bufSetExtmark with negative col returns 0', function () {
        const ns = vim.api.createNamespace('extmark-negative-col');
        const buf = vim.api.getCurrentBuf();
        // Negative col should fail gracefully
        const id = vim.api.bufSetExtmark(buf, ns, 0, -5, {});
        vim.e2e.assert.equal(id, 0, 'negative col should return 0');
    });
    // Edge case: negative ns_id validation
    vim.e2e.test('bufGetExtmarks with negative ns_id returns empty', function () {
        const buf = vim.api.getCurrentBuf();
        const extmarks = vim.api.bufGetExtmarks(buf, -1, 0, -1, {});
        vim.e2e.assert.equal(extmarks.length, 0, 'negative ns_id should return empty array');
    });
    vim.e2e.test('bufDelExtmark with negative ns_id returns false', function () {
        const buf = vim.api.getCurrentBuf();
        const result = vim.api.bufDelExtmark(buf, -1, 1);
        vim.e2e.assert.true(!result, 'negative ns_id should return false');
    });
    vim.e2e.test('bufDelExtmark with negative id returns false', function () {
        const ns = vim.api.createNamespace('extmark-del-neg-id');
        const buf = vim.api.getCurrentBuf();
        const result = vim.api.bufDelExtmark(buf, ns, -1);
        vim.e2e.assert.true(!result, 'negative id should return false');
    });
    vim.e2e.test('bufGetExtmarkById with negative ns_id returns null', function () {
        const buf = vim.api.getCurrentBuf();
        const pos = vim.api.bufGetExtmarkById(buf, -1, 1, {});
        vim.e2e.assert.true(pos === null, 'negative ns_id should return null');
    });
    vim.e2e.test('bufGetExtmarkById with negative id returns null', function () {
        const ns = vim.api.createNamespace('extmark-byid-neg-id');
        const buf = vim.api.getCurrentBuf();
        const pos = vim.api.bufGetExtmarkById(buf, ns, -1, {});
        vim.e2e.assert.true(pos === null, 'negative id should return null');
    });
    // Edge case: negative values in array positions
    vim.e2e.test('bufGetExtmarks with negative array position returns empty', function () {
        const ns = vim.api.createNamespace('extmark-neg-array-pos');
        const buf = vim.api.getCurrentBuf();
        // Create an extmark first
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        // Negative line in array should fail
        const extmarks = vim.api.bufGetExtmarks(buf, ns, [-1, 0], [5, 0], {});
        vim.e2e.assert.equal(extmarks.length, 0, 'negative array line should return empty');
    });
    // Edge case: negative id in options is ignored (auto-generates ID)
    vim.e2e.test('bufSetExtmark with negative id option auto-generates ID', function () {
        const ns = vim.api.createNamespace('extmark-neg-opt-id');
        const buf = vim.api.getCurrentBuf();
        // Negative id should be ignored, auto-generate instead
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, { id: -5 });
        vim.e2e.assert.true(id > 0, 'negative id option should be ignored, auto-generate positive ID');
    });
    // Edge case: negative endLine/endCol are ignored
    vim.e2e.test('bufSetExtmark with negative endLine/endCol ignores them', function () {
        const ns = vim.api.createNamespace('extmark-neg-end');
        const buf = vim.api.getCurrentBuf();
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, {
            endLine: -1,
            endCol: -5
        });
        vim.e2e.assert.true(id > 0, 'should create extmark despite negative endLine/endCol');
        // Verify endLine/endCol were not set
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { details: true });
        const found = extmarks.find(function (e) { return e[0] === id; });
        vim.e2e.assert.true(found !== undefined, 'should find extmark');
        if (found && found.length === 4) {
            const details = found[3];
            vim.e2e.assert.true(details.endLine === undefined, 'endLine should be undefined');
            vim.e2e.assert.true(details.endCol === undefined, 'endCol should be undefined');
        }
    });
    // Edge case: negative priority is ignored (defaults to 0)
    vim.e2e.test('bufSetExtmark with negative priority uses default', function () {
        const ns = vim.api.createNamespace('extmark-neg-priority');
        const buf = vim.api.getCurrentBuf();
        const id = vim.api.bufSetExtmark(buf, ns, 0, 0, { priority: -100 });
        vim.e2e.assert.true(id > 0, 'should create extmark despite negative priority');
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { details: true });
        const found = extmarks.find(function (e) { return e[0] === id; });
        vim.e2e.assert.true(found !== undefined, 'should find extmark');
        if (found && found.length === 4) {
            const details = found[3];
            vim.e2e.assert.equal(details.priority, 0, 'negative priority should default to 0');
        }
    });
    // Edge case: negative limit option is ignored (returns all extmarks)
    vim.e2e.test('bufGetExtmarks with negative limit returns all extmarks', function () {
        const ns = vim.api.createNamespace('extmark-neg-limit');
        const buf = vim.api.getCurrentBuf();
        // Create multiple extmarks
        vim.api.bufSetExtmark(buf, ns, 0, 0, {});
        vim.api.bufSetExtmark(buf, ns, 0, 5, {});
        vim.api.bufSetExtmark(buf, ns, 1, 0, {});
        // Negative limit should be ignored (no limit applied)
        const extmarks = vim.api.bufGetExtmarks(buf, ns, 0, -1, { limit: -5 });
        vim.e2e.assert.true(extmarks.length >= 3, 'negative limit should return all extmarks');
    });
});
vim.e2e.runAll();
