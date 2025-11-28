// Minimal test to debug frame capture issues

vim.e2e.describe("Simple Frame Test", function() {
  vim.e2e.test("basic check", function() {
    try {
      vim.e2e.assert.true(true, "Sanity check");
      console.log("✓ Basic assert works");
    } catch (e) {
      console.log("✗ Basic assert failed:", e);
      throw e;
    }

    try {
      const capturing = vim.e2e.pty.isCapturingFrames();
      console.log("✓ isCapturingFrames() returned:", capturing);
    } catch (e) {
      console.log("✗ isCapturingFrames() failed:", e);
      throw e;
    }

    try {
      vim.e2e.pty.startFrameCapture();
      console.log("✓ startFrameCapture() worked");
    } catch (e) {
      console.log("✗ startFrameCapture() failed:", e);
      throw e;
    }

    try {
      const capturing2 = vim.e2e.pty.isCapturingFrames();
      console.log("✓ After start, isCapturingFrames():", capturing2);
      vim.e2e.assert.true(capturing2, "Should be capturing after start");
    } catch (e) {
      console.log("✗ After start check failed:", e);
      throw e;
    }

    try {
      const count = vim.e2e.pty.stopFrameCapture();
      console.log("✓ stopFrameCapture() returned:", count);
    } catch (e) {
      console.log("✗ stopFrameCapture() failed:", e);
      throw e;
    }
  });
});

vim.e2e.runAll();
