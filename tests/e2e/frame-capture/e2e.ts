// E2E Test: Animation Frame Capture API
// Tests the new frame capture functionality for debugging animated rendering
// (e.g., smear-cursor plugin)

vim.e2e.describe("Animation Frame Capture", function() {

  vim.e2e.test("startFrameCapture and stopFrameCapture work", function() {
    // Initially not capturing
    vim.e2e.assert.false(vim.e2e.pty.isCapturingFrames(), "Should not be capturing initially");

    // Start capture
    vim.e2e.pty.startFrameCapture();
    vim.e2e.assert.true(vim.e2e.pty.isCapturingFrames(), "Should be capturing after start");

    // Stop capture
    const frameCount = vim.e2e.pty.stopFrameCapture();
    vim.e2e.assert.false(vim.e2e.pty.isCapturingFrames(), "Should not be capturing after stop");
    vim.e2e.assert.equal(frameCount, 0); // No frames captured (no renders)
  });

  vim.e2e.test("captureFrame stores frame with timestamp", function() {
    vim.e2e.pty.startFrameCapture();

    // Trigger a render and capture the frame
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Should have 1 frame
    const count = vim.e2e.pty.getFrameCount();
    vim.e2e.assert.equal(count, 1);

    // Get frames and verify structure
    const frames = vim.e2e.pty.getFrames();
    vim.e2e.assert.equal(frames.length, 1);

    // Frame should have timestamp >= 0
    vim.e2e.assert.true(frames[0].timestamp >= 0, "Timestamp should be non-negative");

    // Frame should have output (render generates ANSI codes)
    vim.e2e.assert.true(frames[0].output.length > 0, "Frame should have output");

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("multiple frames have increasing timestamps", function() {
    vim.e2e.pty.startFrameCapture();

    // Capture multiple frames with small delays
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.wait(10); // 10ms delay
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.wait(10);
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.assert.equal(frames.length, 3);

    // Timestamps should be increasing (or at least non-decreasing)
    vim.e2e.assert.true(
      frames[1].timestamp >= frames[0].timestamp,
      "Second frame timestamp should be >= first"
    );
    vim.e2e.assert.true(
      frames[2].timestamp >= frames[1].timestamp,
      "Third frame timestamp should be >= second"
    );

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("stopFrameCapture returns frame count", function() {
    vim.e2e.pty.startFrameCapture();

    // Capture 2 frames
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const count = vim.e2e.pty.stopFrameCapture();
    vim.e2e.assert.equal(count, 2);
  });

  vim.e2e.test("startFrameCapture clears previous frames", function() {
    // First capture session
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    vim.e2e.pty.stopFrameCapture();

    // Second capture session should start fresh
    vim.e2e.pty.startFrameCapture();
    vim.e2e.assert.equal(vim.e2e.pty.getFrameCount(), 0); // No frames yet
    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("frame output contains terminal escape codes", function() {
    vim.e2e.pty.startFrameCapture();

    // Set up some text to render
    vim.e2e.keys("iHello World<Esc>");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.assert.equal(frames.length, 1);

    const output = frames[0].output;

    // Output should contain escape sequences (ESC character = \x1b)
    vim.e2e.assert.true(output.includes("\x1b"), "Output should contain escape codes");

    // Output should contain the rendered text
    vim.e2e.assert.true(output.includes("Hello World"), "Output should contain rendered text");

    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.runAll();
