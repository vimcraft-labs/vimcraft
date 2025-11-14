/// vim.motion API
/// JavaScript wrapper for motion commands
/// This file is loaded automatically by the JSI runtime

(function() {
  // Create vim namespace if it doesn't exist
  if (typeof vim === 'undefined') {
    globalThis.vim = {};
  }

  // Create vim.motion namespace
  vim.motion = {
    // Character motion (h/j/k/l)
    left: function() {
      moveLeft();
    },
    right: function() {
      moveRight();
    },
    up: function() {
      moveUp();
    },
    down: function() {
      moveDown();
    },

    // Line motion (0/$^)
    toLineStart: function() {
      moveToLineStart();
    },
    toLineEnd: function() {
      moveToLineEnd();
    },
    toFirstNonBlank: function() {
      moveToFirstNonBlank();
    },

    // Word motion (w/b/e)
    wordForward: function() {
      moveWordForward();
    },
    wordBackward: function() {
      moveWordBackward();
    },
    wordEnd: function() {
      moveWordEnd();
    },

    // File motion (gg/G)
    toFileStart: function() {
      moveToFileStart();
    },
    toFileEnd: function() {
      moveToFileEnd();
    },

    // Viewport motion (H/M/L)
    toViewportTop: function() {
      moveToViewportTop();
    },
    toViewportMiddle: function() {
      moveToViewportMiddle();
    },
    toViewportBottom: function() {
      moveToViewportBottom();
    },

    // Scrolling (Ctrl+D/U)
    scrollHalfPageDown: function() {
      scrollHalfPageDown();
    },
    scrollHalfPageUp: function() {
      scrollHalfPageUp();
    },
  };

  // Freeze to prevent modifications
  Object.freeze(vim.motion);
})();
