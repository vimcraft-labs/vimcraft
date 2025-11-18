// Filetype Detection Demo
// Demonstrates vim.filetype.match() API with go-enry (GitHub Linguist)
// 697 languages with content-based disambiguation

// vim.filetype namespace (registered via HostObject in runtime.js)
// Already available as globalThis.vim.filetype

console.log('=== Filetype Detection Demo ===');
console.log('Using go-enry (GitHub Linguist engine - 697 languages)');
console.log('Content-based disambiguation for ambiguous extensions\n');

// Test 1: Extension-based detection (Tier 1 - O(1) lookup)
console.log('--- Extension Detection (Tier 1) ---');
console.log('vim.filetype.match({ filename: "main.rs" }):', vim.filetype.match({ filename: "main.rs" }));
console.log('vim.filetype.match({ filename: "app.js" }):', vim.filetype.match({ filename: "app.js" }));
console.log('vim.filetype.match({ filename: "build.zig" }):', vim.filetype.match({ filename: "build.zig" }));
console.log('vim.filetype.match({ filename: "server.go" }):', vim.filetype.match({ filename: "server.go" }));
console.log('vim.filetype.match({ filename: "script.py" }):', vim.filetype.match({ filename: "script.py" }));
console.log('vim.filetype.match({ filename: "app.rb" }):', vim.filetype.match({ filename: "app.rb" }));
console.log('vim.filetype.match({ filename: "init.lua" }):', vim.filetype.match({ filename: "init.lua" }));

// Test 2: Exact filename detection (Tier 2 - O(1) lookup)
console.log('\n--- Exact Filename Detection (Tier 2) ---');
console.log('vim.filetype.match({ filename: "Makefile" }):', vim.filetype.match({ filename: "Makefile" }));
console.log('vim.filetype.match({ filename: "Dockerfile" }):', vim.filetype.match({ filename: "Dockerfile" }));
console.log('vim.filetype.match({ filename: ".gitignore" }):', vim.filetype.match({ filename: ".gitignore" }));
console.log('vim.filetype.match({ filename: ".bashrc" }):', vim.filetype.match({ filename: ".bashrc" }));
console.log('vim.filetype.match({ filename: "Cargo.toml" }):', vim.filetype.match({ filename: "Cargo.toml" }));

// Test 3: Multiple JavaScript extensions
console.log('\n--- JavaScript Variants ---');
console.log('vim.filetype.match({ filename: "app.js" }):', vim.filetype.match({ filename: "app.js" }));
console.log('vim.filetype.match({ filename: "module.mjs" }):', vim.filetype.match({ filename: "module.mjs" }));
console.log('vim.filetype.match({ filename: "common.cjs" }):', vim.filetype.match({ filename: "common.cjs" }));
console.log('vim.filetype.match({ filename: "types.ts" }):', vim.filetype.match({ filename: "types.ts" }));
console.log('vim.filetype.match({ filename: "component.tsx" }):', vim.filetype.match({ filename: "component.tsx" }));
console.log('vim.filetype.match({ filename: "component.jsx" }):', vim.filetype.match({ filename: "component.jsx" }));

// Test 4: Paths with directories
console.log('\n--- Paths with Directories ---');
console.log('vim.filetype.match({ filename: "/path/to/main.rs" }):', vim.filetype.match({ filename: "/path/to/main.rs" }));
console.log('vim.filetype.match({ filename: "src/lib.zig" }):', vim.filetype.match({ filename: "src/lib.zig" }));
console.log('vim.filetype.match({ filename: "../build.zig" }):', vim.filetype.match({ filename: "../build.zig" }));

// Test 5: Unknown filetypes
console.log('\n--- Unknown Filetypes (returns null) ---');
console.log('vim.filetype.match({ filename: "unknown.xyz" }):', vim.filetype.match({ filename: "unknown.xyz" }));
console.log('vim.filetype.match({ filename: "no-extension" }):', vim.filetype.match({ filename: "no-extension" }));

// Test 6: Current buffer detection (buf: 0)
console.log('\n--- Current Buffer Detection ---');
console.log('vim.filetype.match({ buf: 0 }):', vim.filetype.match({ buf: 0 }));
console.log('(returns null if no file loaded or shebang detection not supported yet)');

// Test 7: Edge cases
console.log('\n--- Edge Cases ---');
console.log('vim.filetype.match({ filename: "" }):', vim.filetype.match({ filename: "" }));
console.log('vim.filetype.match({ }):', vim.filetype.match({ }));

console.log('\n=== Demo Complete ===');
console.log('GitHub Linguist-based detection ready for plugins!');
console.log('');
console.log('📝 IMPORTANT: Ambiguous extensions (.rs, .h, .inc)');
console.log('   Use { buf: 0 } or matching filename for content-based disambiguation');
console.log('   Example: .rs can be Rust or RenderScript - content detection resolves this');
console.log('');
console.log('Total languages supported: 697');
