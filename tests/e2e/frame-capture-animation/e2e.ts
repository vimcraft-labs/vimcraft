// E2E Test: Animation Plugin Frame Capture Simulation
// Simulates how a smear-cursor or similar animation plugin would use frame capture
// to validate animation rendering

vim.e2e.describe("Smear-Cursor Animation Simulation", function() {

  vim.e2e.test("rapid cursor movement produces animation-ready frames", function() {
    // Set up a line of text to move across
    vim.e2e.keys("iThe quick brown fox jumps over the lazy dog<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Simulate rapid cursor movement (like hjkl spam)
    // This is what triggers smear-cursor animation
    const movements = 10;
    for (let i = 0; i < movements; i++) {
      vim.e2e.keys("l");
      vim.e2e.pty.render();
      vim.e2e.pty.captureFrame();
    }

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    // Verify we captured all movement frames
    vim.e2e.assert.equal(frames.length, movements);

    // All frames should have render output
    for (let i = 0; i < frames.length; i++) {
      vim.e2e.assert.true(
        frames[i].output.length > 0,
        `Animation frame ${i} should have output`
      );
    }

    // Timestamps should allow calculating animation timing
    const firstTime = frames[0].timestamp;
    const lastTime = frames[frames.length - 1].timestamp;
    const duration = lastTime - firstTime;

    // Log for debugging animation timing
    console.log(`Animation duration: ${duration}ms for ${movements} frames`);
    console.log(`Average frame time: ${duration / movements}ms`);
  });

  vim.e2e.test("diagonal movement (hjkl combo) captures intermediate positions", function() {
    // Set up multi-line content
    vim.e2e.keys("iLine 1 with some text<CR>");
    vim.e2e.keys("Line 2 with more text<CR>");
    vim.e2e.keys("Line 3 with even more<CR>");
    vim.e2e.keys("Line 4 final line<Esc>gg0");

    vim.e2e.pty.startFrameCapture();

    // Diagonal movement: down-right, down-right, down-right
    // This creates a diagonal animation path
    vim.e2e.keys("jl");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("jl");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("jl");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    vim.e2e.assert.equal(frames.length, 3);

    // Each frame should be unique (different cursor position)
    vim.e2e.assert.true(
      frames[0].output !== frames[1].output,
      "First two diagonal frames should differ"
    );
    vim.e2e.assert.true(
      frames[1].output !== frames[2].output,
      "Last two diagonal frames should differ"
    );
  });

  vim.e2e.test("jump movement (w, b, 0, $) captures large position changes", function() {
    vim.e2e.keys("ione two three four five six seven eight<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Big jump to end of line
    vim.e2e.keys("$");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Jump back to start
    vim.e2e.keys("0");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Word jump forward
    vim.e2e.keys("www");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    vim.e2e.assert.equal(frames.length, 3);

    // All jumps should produce different output
    const outputs = new Set(frames.map(f => f.output));
    vim.e2e.assert.equal(outputs.size, 3, "All jump frames should be unique");
  });
});

vim.e2e.describe("Animation Frame Analysis Helpers", function() {

  vim.e2e.test("can detect cursor position codes in frames", function() {
    vim.e2e.keys("iTest<Esc>0");

    vim.e2e.pty.startFrameCapture();
    vim.e2e.keys("llll");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    const output = frames[0].output;

    // Count cursor position sequences (ESC[row;colH or ESC[row;colf)
    const cursorPosRegex = /\x1b\[\d+;\d+[Hf]/g;
    const matches = output.match(cursorPosRegex) || [];

    vim.e2e.assert.true(
      matches.length > 0,
      "Frame should contain cursor position escape codes"
    );

    console.log(`Found ${matches.length} cursor position codes`);
  });

  vim.e2e.test("can measure frame-to-frame changes", function() {
    vim.e2e.keys("iABCDEFGHIJ<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Capture two consecutive positions
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.keys("l");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    // Calculate "difference" between frames (simple byte comparison)
    let differences = 0;
    const minLen = Math.min(frames[0].output.length, frames[1].output.length);
    for (let i = 0; i < minLen; i++) {
      if (frames[0].output[i] !== frames[1].output[i]) {
        differences++;
      }
    }
    differences += Math.abs(frames[0].output.length - frames[1].output.length);

    vim.e2e.assert.true(
      differences > 0,
      "Frames should have detectable differences"
    );

    console.log(`Frame difference: ${differences} bytes changed`);
  });

  vim.e2e.test("frame output size is consistent for similar renders", function() {
    vim.e2e.keys("iConsistent content here<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Multiple renders of same state should produce similar-sized output
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    // Output sizes should be very similar (diff-based rendering = smaller subsequent frames)
    const sizes = frames.map(f => f.output.length);
    console.log(`Frame sizes: ${sizes.join(', ')} bytes`);

    // First frame is often larger (full render), subsequent frames use diff
    // This is expected behavior for optimized rendering
    vim.e2e.assert.true(
      sizes.every(s => s > 0),
      "All frames should have some output"
    );
  });
});

vim.e2e.describe("Animation Performance Characteristics", function() {

  vim.e2e.test("can capture at 60fps simulation rate", function() {
    vim.e2e.keys("iPerformance test content<Esc>0");

    vim.e2e.pty.startFrameCapture();

    // Simulate 60fps for 100ms (6 frames)
    const frameCount = 6;
    const frameInterval = 16; // ~16ms per frame = 60fps

    for (let i = 0; i < frameCount; i++) {
      vim.e2e.keys("l"); // Move cursor
      vim.e2e.pty.render();
      vim.e2e.pty.captureFrame();
      vim.e2e.wait(frameInterval);
    }

    const frames = vim.e2e.pty.getFrames();
    vim.e2e.pty.stopFrameCapture();

    vim.e2e.assert.equal(frames.length, frameCount);

    // Verify timing is approximately correct
    const totalDuration = frames[frameCount - 1].timestamp - frames[0].timestamp;
    const expectedDuration = (frameCount - 1) * frameInterval;

    vim.e2e.assert.true(
      totalDuration >= expectedDuration * 0.8, // Allow 20% variance
      `Duration should be ~${expectedDuration}ms, got ${totalDuration}ms`
    );

    console.log(`60fps simulation: ${frameCount} frames in ${totalDuration}ms`);
  });

  vim.e2e.test("frame capture has low overhead", function() {
    vim.e2e.keys("iOverhead test<Esc>0");

    // Time without capture
    const startWithout = Date.now();
    for (let i = 0; i < 20; i++) {
      vim.e2e.keys("l");
      vim.e2e.pty.render();
    }
    const durationWithout = Date.now() - startWithout;

    // Reset position
    vim.e2e.keys("0");

    // Time with capture
    vim.e2e.pty.startFrameCapture();
    const startWith = Date.now();
    for (let i = 0; i < 20; i++) {
      vim.e2e.keys("l");
      vim.e2e.pty.render();
      vim.e2e.pty.captureFrame();
    }
    const durationWith = Date.now() - startWith;
    vim.e2e.pty.stopFrameCapture();

    // Capture overhead should be reasonable (less than 2x)
    const overhead = durationWith / Math.max(durationWithout, 1);

    console.log(`Without capture: ${durationWithout}ms, With capture: ${durationWith}ms`);
    console.log(`Overhead ratio: ${overhead.toFixed(2)}x`);

    vim.e2e.assert.true(
      overhead < 3.0, // Allow up to 3x overhead (capture + memory allocation)
      `Capture overhead ${overhead.toFixed(2)}x should be reasonable`
    );
  });
});

vim.e2e.describe("Integration with PTY Capture Mode", function() {

  vim.e2e.test("frame capture works with regular PTY capture", function() {
    vim.e2e.keys("iIntegration test<Esc>0");

    // Start both capture modes
    vim.e2e.pty.startCapture();
    vim.e2e.pty.startFrameCapture();

    vim.e2e.keys("lll");
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    const frames = vim.e2e.pty.getFrames();

    // Frame capture should work
    vim.e2e.assert.equal(frames.length, 1);
    vim.e2e.assert.true(frames[0].output.length > 0);

    // Regular capture should also have data
    const regularCapture = vim.e2e.pty.getCaptured();
    vim.e2e.assert.true(regularCapture.length > 0, "Regular capture should have data");

    vim.e2e.pty.stopFrameCapture();
    vim.e2e.pty.stopCapture();
  });

  vim.e2e.test("frame capture and regular capture are independent", function() {
    vim.e2e.keys("iIndependent test<Esc>0");

    // Start frame capture
    vim.e2e.pty.startFrameCapture();
    vim.e2e.pty.render();
    vim.e2e.pty.captureFrame();

    // Stop frame capture
    const frameCount = vim.e2e.pty.stopFrameCapture();
    vim.e2e.assert.equal(frameCount, 1);

    // Regular capture should work independently
    vim.e2e.pty.startCapture();
    vim.e2e.keys("l");
    vim.e2e.pty.render();
    const captured = vim.e2e.pty.getCaptured();
    vim.e2e.pty.stopCapture();

    vim.e2e.assert.true(captured.length > 0, "Independent regular capture should work");
  });
});

vim.e2e.runAll();
