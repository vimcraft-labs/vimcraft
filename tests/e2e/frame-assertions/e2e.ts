// E2E Test: Frame Assertion Helpers
// Tests the new vim.e2e.assert.frame* methods for animation testing

vim.e2e.describe("Frame Count Assertion", function() {

  vim.e2e.test("frameCount passes with correct count", function() {
    vim.e2e.pty.startFrameCapture();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Should have exactly 3 frames
    vim.e2e.assert.frameCount(3);

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("frameCount works with zero frames", function() {
    vim.e2e.pty.startFrameCapture();
    // No frames captured
    vim.e2e.assert.frameCount(0);
    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Frames Increasing Timestamps", function() {

  vim.e2e.test("framesIncreasing passes with sequential timestamps", function() {
    vim.e2e.pty.startFrameCapture();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.wait(10);
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.wait(10);
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // All timestamps should be increasing
    vim.e2e.assert.framesIncreasing();

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("framesIncreasing passes with single frame", function() {
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    // Single frame is trivially increasing
    vim.e2e.assert.framesIncreasing();
    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Frames Not Empty", function() {

  vim.e2e.test("framesNotEmpty passes with rendered frames", function() {
    vim.e2e.keys("iHello World<Esc>");

    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // All frames should have output
    vim.e2e.assert.framesNotEmpty();

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("framesNotEmpty passes with empty frame list", function() {
    vim.e2e.pty.startFrameCapture();
    // No frames captured - trivially passes
    vim.e2e.assert.framesNotEmpty();
    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Frames Unique", function() {

  vim.e2e.test("framesUnique passes with different cursor positions", function() {
    vim.e2e.keys("iABCDEFGHIJ<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Each movement should produce different output
    vim.e2e.keys("l");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("l");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("l");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // All frames should be unique (cursor at different positions)
    vim.e2e.assert.framesUnique();

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("framesUnique passes with single frame", function() {
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    // Single frame is trivially unique
    vim.e2e.assert.framesUnique();
    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Frame Duration", function() {

  vim.e2e.test("frameDuration passes within bounds", function() {
    vim.e2e.pty.startFrameCapture();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.wait(50);

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Duration should be around 50ms (allow 30-150ms for variance)
    vim.e2e.assert.frameDuration(30, 150);

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("frameDuration passes with single frame", function() {
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();
    // Single frame has zero duration - any range passes
    vim.e2e.assert.frameDuration(0, 1000);
    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Frame Contains", function() {

  vim.e2e.test("frameContains passes when pattern exists", function() {
    vim.e2e.keys("iUniqueTestPattern<Esc>");

    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Frame should contain the typed text
    vim.e2e.assert.frameContains(0, "UniqueTestPattern");

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("frameContains passes with escape codes", function() {
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Frame should contain CSI escape sequences
    vim.e2e.assert.frameContains(0, "\x1b[");

    vim.e2e.pty.stopFrameCapture();
  });

  vim.e2e.test("frameContains works with middle frame", function() {
    vim.e2e.keys("iFrame0<Esc>");

    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("oFrame1<Esc>");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("oFrame2<Esc>");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Check specific frame index
    vim.e2e.assert.frameContains(1, "Frame1");
    vim.e2e.assert.frameContains(2, "Frame2");

    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.describe("Combined Assertions", function() {

  vim.e2e.test("all frame assertions work together", function() {
    vim.e2e.keys("iAnimation Test<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Simulate animation frames
    for (let i = 0; i < 5; i++) {
      vim.e2e.keys("l");
      vim.e2e.pty.render();
      vim.e2e.pty.captureFrame();
      vim.e2e.wait(10);
    }

    // Test all assertions
    vim.e2e.assert.frameCount(5);
    vim.e2e.assert.framesIncreasing();
    vim.e2e.assert.framesNotEmpty();
    vim.e2e.assert.framesUnique();
    vim.e2e.assert.frameDuration(0, 500);
    vim.e2e.assert.frameContains(0, "Animation");

    vim.e2e.pty.stopFrameCapture();
  });
});

vim.e2e.runAll();
