// vim.diagnostic API E2E Tests
// TDD: Write tests first, then implement
//
// Neovim-compatible diagnostic API for LSP support:
// - vim.diagnostic.set(namespace, bufnr, diagnostics) - Set diagnostics for a buffer
// - vim.diagnostic.get(bufnr?, opts?) - Get diagnostics from buffer(s)
// - vim.diagnostic.reset(namespace?, bufnr?) - Clear diagnostics
// - vim.diagnostic.count(bufnr?, opts?) - Count diagnostics by severity
// - vim.diagnostic.severity - Severity levels (ERROR=1, WARN=2, INFO=3, HINT=4)

vim.e2e.describe("vim.diagnostic", function () {
  vim.e2e.describe("severity", function () {
    vim.e2e.test("has correct severity levels", function () {
      vim.e2e.assert.equal(vim.diagnostic.severity.ERROR, 1);
      vim.e2e.assert.equal(vim.diagnostic.severity.WARN, 2);
      vim.e2e.assert.equal(vim.diagnostic.severity.INFO, 3);
      vim.e2e.assert.equal(vim.diagnostic.severity.HINT, 4);
    });

    vim.e2e.test("has reverse mappings", function () {
      // Neovim also has numeric index -> string mappings
      vim.e2e.assert.equal(vim.diagnostic.severity[1], "ERROR");
      vim.e2e.assert.equal(vim.diagnostic.severity[2], "WARN");
      vim.e2e.assert.equal(vim.diagnostic.severity[3], "INFO");
      vim.e2e.assert.equal(vim.diagnostic.severity[4], "HINT");
    });
  });

  vim.e2e.describe("set and get", function () {
    vim.e2e.test("sets and retrieves a single diagnostic", function () {
      const ns = vim.api.createNamespace("test_diagnostic");
      const buf = vim.api.getCurrentBuf();

      // Set a diagnostic
      vim.diagnostic.set(ns, buf, [
        {
          lnum: 0,
          col: 0,
          message: "Test error",
          severity: vim.diagnostic.severity.ERROR,
        },
      ]);

      // Get diagnostics
      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics.length, 1);
      vim.e2e.assert.equal(diagnostics[0].message, "Test error");
      vim.e2e.assert.equal(diagnostics[0].severity, vim.diagnostic.severity.ERROR);
      vim.e2e.assert.equal(diagnostics[0].lnum, 0);
      vim.e2e.assert.equal(diagnostics[0].col, 0);

      // Clean up
      vim.diagnostic.reset(ns, buf);
    });

    vim.e2e.test("sets multiple diagnostics", function () {
      const ns = vim.api.createNamespace("test_multi");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        {
          lnum: 0,
          col: 0,
          message: "Error 1",
          severity: vim.diagnostic.severity.ERROR,
        },
        {
          lnum: 1,
          col: 5,
          message: "Warning 1",
          severity: vim.diagnostic.severity.WARN,
        },
        {
          lnum: 2,
          col: 10,
          message: "Hint 1",
          severity: vim.diagnostic.severity.HINT,
        },
      ]);

      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics.length, 3);

      // Clean up
      vim.diagnostic.reset(ns, buf);
    });

    vim.e2e.test("defaults severity to ERROR", function () {
      const ns = vim.api.createNamespace("test_default_severity");
      const buf = vim.api.getCurrentBuf();

      // Set diagnostic without severity
      vim.diagnostic.set(ns, buf, [
        {
          lnum: 0,
          col: 0,
          message: "No severity specified",
        },
      ]);

      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics.length, 1);
      vim.e2e.assert.equal(diagnostics[0].severity, vim.diagnostic.severity.ERROR);

      vim.diagnostic.reset(ns, buf);
    });

    vim.e2e.test("normalizes endLnum and endCol", function () {
      const ns = vim.api.createNamespace("test_normalize");
      const buf = vim.api.getCurrentBuf();

      // Set diagnostic without end positions
      vim.diagnostic.set(ns, buf, [
        {
          lnum: 1,
          col: 5,
          message: "No end position",
        },
      ]);

      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics.length, 1);
      // endLnum defaults to lnum, endCol defaults to col
      vim.e2e.assert.equal(diagnostics[0].endLnum, 1);
      vim.e2e.assert.equal(diagnostics[0].endCol, 5);

      vim.diagnostic.reset(ns, buf);
    });

    vim.e2e.test("includes bufnr in returned diagnostics", function () {
      const ns = vim.api.createNamespace("test_bufnr");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        {
          lnum: 0,
          col: 0,
          message: "Test",
        },
      ]);

      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics[0].bufnr, buf);

      vim.diagnostic.reset(ns, buf);
    });
  });

  vim.e2e.describe("get with filters", function () {
    vim.e2e.test("filters by namespace", function () {
      const ns1 = vim.api.createNamespace("test_ns1");
      const ns2 = vim.api.createNamespace("test_ns2");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns1, buf, [
        { lnum: 0, col: 0, message: "From NS1" },
      ]);
      vim.diagnostic.set(ns2, buf, [
        { lnum: 1, col: 0, message: "From NS2" },
      ]);

      // Get all
      const all = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(all.length, 2);

      // Filter by namespace
      const fromNs1 = vim.diagnostic.get(buf, { namespace: ns1 });
      vim.e2e.assert.equal(fromNs1.length, 1);
      vim.e2e.assert.equal(fromNs1[0].message, "From NS1");

      vim.diagnostic.reset(ns1, buf);
      vim.diagnostic.reset(ns2, buf);
    });

    vim.e2e.test("filters by severity", function () {
      const ns = vim.api.createNamespace("test_severity_filter");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Error", severity: vim.diagnostic.severity.ERROR },
        { lnum: 1, col: 0, message: "Warning", severity: vim.diagnostic.severity.WARN },
        { lnum: 2, col: 0, message: "Info", severity: vim.diagnostic.severity.INFO },
      ]);

      const errors = vim.diagnostic.get(buf, { severity: vim.diagnostic.severity.ERROR });
      vim.e2e.assert.equal(errors.length, 1);
      vim.e2e.assert.equal(errors[0].message, "Error");

      vim.diagnostic.reset(ns, buf);
    });

    vim.e2e.test("filters by line number", function () {
      const ns = vim.api.createNamespace("test_lnum_filter");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Line 0" },
        { lnum: 1, col: 0, message: "Line 1" },
        { lnum: 2, col: 0, message: "Line 2" },
      ]);

      const line1 = vim.diagnostic.get(buf, { lnum: 1 });
      vim.e2e.assert.equal(line1.length, 1);
      vim.e2e.assert.equal(line1[0].message, "Line 1");

      vim.diagnostic.reset(ns, buf);
    });
  });

  vim.e2e.describe("reset", function () {
    vim.e2e.test("clears diagnostics for specific namespace and buffer", function () {
      const ns = vim.api.createNamespace("test_reset");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Test" },
      ]);

      vim.e2e.assert.equal(vim.diagnostic.get(buf).length, 1);

      vim.diagnostic.reset(ns, buf);

      vim.e2e.assert.equal(vim.diagnostic.get(buf).length, 0);
    });

    vim.e2e.test("clears all diagnostics for namespace when bufnr is nil", function () {
      const ns = vim.api.createNamespace("test_reset_all");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Test" },
      ]);

      // Reset all for this namespace (no bufnr)
      vim.diagnostic.reset(ns);

      vim.e2e.assert.equal(vim.diagnostic.get(buf).length, 0);
    });
  });

  vim.e2e.describe("count", function () {
    vim.e2e.test("counts diagnostics by severity", function () {
      const ns = vim.api.createNamespace("test_count");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Error 1", severity: vim.diagnostic.severity.ERROR },
        { lnum: 1, col: 0, message: "Error 2", severity: vim.diagnostic.severity.ERROR },
        { lnum: 2, col: 0, message: "Warning", severity: vim.diagnostic.severity.WARN },
        { lnum: 3, col: 0, message: "Hint", severity: vim.diagnostic.severity.HINT },
      ]);

      const counts = vim.diagnostic.count(buf);
      vim.e2e.assert.equal(counts[vim.diagnostic.severity.ERROR], 2);
      vim.e2e.assert.equal(counts[vim.diagnostic.severity.WARN], 1);
      vim.e2e.assert.equal(counts[vim.diagnostic.severity.HINT], 1);
      // INFO not present, should be undefined or 0
      vim.e2e.assert.true(
        counts[vim.diagnostic.severity.INFO] === undefined ||
          counts[vim.diagnostic.severity.INFO] === 0
      );

      vim.diagnostic.reset(ns, buf);
    });
  });

  vim.e2e.describe("diagnostic with source and code", function () {
    vim.e2e.test("preserves source and code fields", function () {
      const ns = vim.api.createNamespace("test_source_code");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        {
          lnum: 0,
          col: 0,
          message: "Unused variable",
          severity: vim.diagnostic.severity.WARN,
          source: "typescript",
          code: "TS6133",
        },
      ]);

      const diagnostics = vim.diagnostic.get(buf);
      vim.e2e.assert.equal(diagnostics.length, 1);
      vim.e2e.assert.equal(diagnostics[0].source, "typescript");
      vim.e2e.assert.equal(diagnostics[0].code, "TS6133");

      vim.diagnostic.reset(ns, buf);
    });
  });

  vim.e2e.describe("multiple namespaces", function () {
    vim.e2e.test("maintains separate diagnostics per namespace", function () {
      const ns1 = vim.api.createNamespace("lsp_server_1");
      const ns2 = vim.api.createNamespace("lsp_server_2");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns1, buf, [
        { lnum: 0, col: 0, message: "LSP1 Error" },
      ]);
      vim.diagnostic.set(ns2, buf, [
        { lnum: 0, col: 0, message: "LSP2 Error" },
      ]);

      // Total should be 2
      vim.e2e.assert.equal(vim.diagnostic.get(buf).length, 2);

      // Reset only ns1
      vim.diagnostic.reset(ns1, buf);
      vim.e2e.assert.equal(vim.diagnostic.get(buf).length, 1);
      vim.e2e.assert.equal(vim.diagnostic.get(buf)[0].message, "LSP2 Error");

      vim.diagnostic.reset(ns2, buf);
    });
  });

  vim.e2e.describe("get without bufnr", function () {
    vim.e2e.test("returns diagnostics from all buffers when bufnr is nil", function () {
      const ns = vim.api.createNamespace("test_all_buffers");
      const buf = vim.api.getCurrentBuf();

      vim.diagnostic.set(ns, buf, [
        { lnum: 0, col: 0, message: "Current buffer diagnostic" },
      ]);

      // Get all diagnostics (nil bufnr)
      const all = vim.diagnostic.get();
      vim.e2e.assert.true(all.length >= 1);

      vim.diagnostic.reset(ns, buf);
    });
  });
});

vim.e2e.runAll();
