// E2E Test: PTY Size Control
// Tests vim.e2e.pty.setSize() and vim.e2e.pty.getSize()

vim.e2e.describe("PTY setSize", function() {

  vim.e2e.test("setSize changes terminal dimensions", function() {
    // Get default size
    const before = vim.e2e.pty.getSize();
    vim.e2e.assert.true(before.rows > 0, "Default rows should be positive");
    vim.e2e.assert.true(before.cols > 0, "Default cols should be positive");

    // Set to 10x40
    const result = vim.e2e.pty.setSize(10, 40);
    vim.e2e.assert.true(result, "setSize should return true");

    // Verify new size
    const after = vim.e2e.pty.getSize();
    vim.e2e.assert.equal(after.rows, 10);
    vim.e2e.assert.equal(after.cols, 40);
  });

  vim.e2e.test("setSize to classic 80x24", function() {
    vim.e2e.pty.setSize(24, 80);
    const size = vim.e2e.pty.getSize();
    vim.e2e.assert.equal(size.rows, 24);
    vim.e2e.assert.equal(size.cols, 80);
  });

  vim.e2e.test("setSize to large dimensions", function() {
    vim.e2e.pty.setSize(100, 200);
    const size = vim.e2e.pty.getSize();
    vim.e2e.assert.equal(size.rows, 100);
    vim.e2e.assert.equal(size.cols, 200);
  });

  vim.e2e.test("setSize works with render", function() {
    // Set small terminal
    vim.e2e.pty.setSize(5, 20);

    // Insert some text and render
    vim.e2e.keys("iHello World<Esc>");

    vim.e2e.pty.startCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.stopCapture();

    // Verify we got some output
    const output = vim.e2e.pty.getOutput();
    vim.e2e.assert.true(output.length > 0, "Should have rendered output");
  });

  vim.e2e.test("setSize same dimensions is no-op", function() {
    vim.e2e.pty.setSize(24, 80);
    const before = vim.e2e.pty.getSize();

    // Set same size again
    vim.e2e.pty.setSize(24, 80);
    const after = vim.e2e.pty.getSize();

    vim.e2e.assert.equal(before.rows, after.rows);
    vim.e2e.assert.equal(before.cols, after.cols);
  });
});

vim.e2e.describe("PTY getSize", function() {

  vim.e2e.test("getSize returns object with rows and cols", function() {
    const size = vim.e2e.pty.getSize();
    vim.e2e.assert.true(typeof size.rows === "number", "rows should be number");
    vim.e2e.assert.true(typeof size.cols === "number", "cols should be number");
  });

  vim.e2e.test("getSize reflects setSize changes", function() {
    // Set various sizes and verify
    vim.e2e.pty.setSize(15, 60);
    let size = vim.e2e.pty.getSize();
    vim.e2e.assert.equal(size.rows, 15);
    vim.e2e.assert.equal(size.cols, 60);

    vim.e2e.pty.setSize(30, 120);
    size = vim.e2e.pty.getSize();
    vim.e2e.assert.equal(size.rows, 30);
    vim.e2e.assert.equal(size.cols, 120);
  });
});

vim.e2e.describe("PTY setSize with Frame Capture", function() {

  vim.e2e.test("frame capture works after setSize", function() {
    // Set terminal size
    vim.e2e.pty.setSize(20, 60);

    // Start frame capture
    vim.e2e.pty.startFrameCapture();

    // Do some operations
    vim.e2e.keys("iTest<Esc>");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("l");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Verify frames were captured
    const count = vim.e2e.pty.getFrameCount();
    vim.e2e.assert.true(count >= 2, "Should capture at least 2 frames");

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("setSize during frame capture", function() {
    vim.e2e.pty.startFrameCapture();

    // Capture at one size
    vim.e2e.pty.setSize(10, 40);
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Change size and capture again
    vim.e2e.pty.setSize(20, 80);
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const count = vim.e2e.pty.getFrameCount();
    vim.e2e.assert.true(count >= 2, "Should capture frames at different sizes");

    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.runAll();
