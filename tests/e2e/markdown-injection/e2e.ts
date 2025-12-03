// Test Tree-sitter language injection detection in Markdown files

vim.e2e.describe("Markdown Injection Detection", () => {
  vim.e2e.test("hasParser returns true for markdown", () => {
    vim.e2e.assert.ok(vim.treesitter.hasParser("markdown"), "Should have markdown parser");
  });

  vim.e2e.test("hasParser returns true for typescript", () => {
    vim.e2e.assert.ok(vim.treesitter.hasParser("typescript"), "Should have typescript parser");
  });

  vim.e2e.test("getLanguageTree initializes parser", () => {
    const result = vim.treesitter.getLanguageTree();
    console.log("getLanguageTree result:", result);
    vim.e2e.assert.ok(result, "getLanguageTree should succeed");
  });

  vim.e2e.test("hasLanguageTree returns true after init", () => {
    const hasTree = vim.treesitter.hasLanguageTree();
    console.log("hasLanguageTree:", hasTree);
    vim.e2e.assert.ok(hasTree, "Should have LanguageTree");
  });

  vim.e2e.test("getLanguages returns supported languages", () => {
    const langs = vim.treesitter.getLanguages();
    console.log("Supported languages count:", langs.length);
    vim.e2e.assert.ok(langs.length > 0, "Should have languages");
    vim.e2e.assert.ok(langs.includes("markdown"), "Should include markdown");
    vim.e2e.assert.ok(langs.includes("typescript"), "Should include typescript");
  });

  vim.e2e.test("languageForRange returns markdown for header", () => {
    // Byte 0 should be in markdown (the heading)
    const lang = vim.treesitter.languageForRange(0, 10);
    console.log("Language at 0-10:", lang);
    vim.e2e.assert.equal(lang, "markdown", "Should return markdown for header");
  });

  vim.e2e.test("getInjectedLanguages detects typescript and javascript", () => {
    const injected = vim.treesitter.getInjectedLanguages();
    console.log("Injected languages:", JSON.stringify(injected));
    vim.e2e.assert.ok(Array.isArray(injected), "Should return array");
    vim.e2e.assert.ok(injected.includes("typescript"), "Should include typescript");
    vim.e2e.assert.ok(injected.includes("javascript"), "Should include javascript");
    vim.e2e.assert.ok(injected.includes("markdown_inline"), "Should include markdown_inline");
  });
});

vim.e2e.runAll();
