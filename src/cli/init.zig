/// vimc init - Initialize ~/.config/vimcraft with TypeScript tooling
///
/// Creates:
/// - tsconfig.json (TypeScript compiler options)
/// - vim.d.ts (Vim API type definitions - single file)
/// - init.ts (if doesn't exist)
/// - plugins/ (plugin directory)
/// - .vimcraft/ (internal metadata directory)

const std = @import("std");

/// Default tsconfig.json content
const TSCONFIG_JSON =
    \\{
    \\  "compilerOptions": {
    \\    "target": "ES2020",
    \\    "module": "CommonJS",
    \\    "lib": ["ES2020"],
    \\    "strict": true,
    \\    "esModuleInterop": true,
    \\    "skipLibCheck": true,
    \\    "forceConsistentCasingInFileNames": true,
    \\    "moduleResolution": "node",
    \\    "resolveJsonModule": true,
    \\    "types": ["./vim.d.ts"]
    \\  },
    \\  "include": [
    \\    "init.ts",
    \\    "plugins/**/*.ts"
    \\  ],
    \\  "exclude": [
    \\    ".vimcraft"
    \\  ]
    \\}
    \\
;

/// Default init.ts content (if doesn't exist)
const INIT_TS =
    \\// Vimcraft Configuration (TypeScript)
    \\// This file is auto-loaded on startup and transpiled to JavaScript
    \\
    \\// Example: Enable line numbers
    \\// vim.opt.number = true;
    \\// vim.opt.relativenumber = true;
    \\
    \\// Example: Set color scheme
    \\// vim.highlight('Normal', { bg: '#1e1e1e', fg: '#d4d4d4' });
    \\// vim.highlight('CursorLine', { bg: '#2b2b2b' });
    \\
    \\// Example: Enable cursor line highlighting
    \\// vim.opt.cursorline = true;
    \\
    \\// Example: Load plugin (Phase 4+)
    \\// const smearCursor = require('@vimcraft/smear-cursor');
    \\// smearCursor.setup({ speed: 0.3 });
    \\
    \\// For more examples, see:
    \\// https://github.com/vimcraft/vimcraft/tree/main/examples
    \\
;

/// Get ~/.config/vimcraft directory
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    return try std.fmt.allocPrint(allocator, "{s}/.config/vimcraft", .{home});
}

/// Execute vimc init command
pub fn execute(allocator: std.mem.Allocator, force: bool) !void {
    std.debug.print("Initializing Vimcraft TypeScript toolchain...\n\n", .{});

    // Get config directory
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    std.debug.print("Config directory: {s}\n", .{config_dir});

    // Create config directory if doesn't exist
    std.fs.cwd().makePath(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create config directory: {}\n", .{err});
            return err;
        }
    };

    // Step 1: Create tsconfig.json
    const tsconfig_path = try std.fmt.allocPrint(allocator, "{s}/tsconfig.json", .{config_dir});
    defer allocator.free(tsconfig_path);

    if (force or !fileExists(tsconfig_path)) {
        try writeFile(tsconfig_path, TSCONFIG_JSON);
        std.debug.print("✓ Created tsconfig.json\n", .{});
    } else {
        std.debug.print("✓ tsconfig.json already exists (use --force to overwrite)\n", .{});
    }

    // Step 2: Create init.ts (if doesn't exist)
    const init_ts_path = try std.fmt.allocPrint(allocator, "{s}/init.ts", .{config_dir});
    defer allocator.free(init_ts_path);

    if (!fileExists(init_ts_path)) {
        try writeFile(init_ts_path, INIT_TS);
        std.debug.print("✓ Created init.ts\n", .{});
    } else {
        std.debug.print("✓ init.ts already exists\n", .{});
    }

    // Step 3: Create vim.d.ts (single type definition file)
    // Copy from source: src/system/jsi/vim.d.ts
    const vim_dts_source = "src/system/jsi/vim.d.ts";
    const vim_dts_path = try std.fmt.allocPrint(allocator, "{s}/vim.d.ts", .{config_dir});
    defer allocator.free(vim_dts_path);

    if (force or !fileExists(vim_dts_path)) {
        // Read from source and copy to config directory
        const vim_dts_content = std.fs.cwd().readFileAlloc(allocator, vim_dts_source, 1024 * 1024) catch |err| {
            std.debug.print("Error: Failed to read vim.d.ts from source: {}\n", .{err});
            std.debug.print("Make sure you're running from vimcraft/editor directory\n", .{});
            return err;
        };
        defer allocator.free(vim_dts_content);

        try writeFile(vim_dts_path, vim_dts_content);
        std.debug.print("✓ Created vim.d.ts\n", .{});
    } else {
        std.debug.print("✓ vim.d.ts already exists (use --force to overwrite)\n", .{});
    }

    // Step 4: Create .vimcraft directory (internal metadata)
    const vimcraft_dir = try std.fmt.allocPrint(allocator, "{s}/.vimcraft", .{config_dir});
    defer allocator.free(vimcraft_dir);

    std.fs.cwd().makePath(vimcraft_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create .vimcraft directory: {}\n", .{err});
            return err;
        }
    };
    std.debug.print("✓ Created .vimcraft/ (metadata)\n", .{});

    // Step 5: Create plugins directory
    const plugins_dir = try std.fmt.allocPrint(allocator, "{s}/plugins", .{config_dir});
    defer allocator.free(plugins_dir);

    std.fs.cwd().makePath(plugins_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error: Failed to create plugins directory: {}\n", .{err});
            return err;
        }
    };
    std.debug.print("✓ Created plugins/\n", .{});

    std.debug.print("\n", .{});
    std.debug.print("✓ Initialization complete!\n\n", .{});
    std.debug.print("Next steps:\n", .{});
    std.debug.print("  1. Open ~/.config/vimcraft/init.ts in your editor\n", .{});
    std.debug.print("  2. Start writing TypeScript with full vim.* IntelliSense\n", .{});
    std.debug.print("  3. Test your config with: vimc run init.ts\n\n", .{});
}

/// Check if file exists
fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Write file with content
fn writeFile(path: []const u8, content: []const u8) !void {
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = content,
    });
}
