/// Lightweight CLI argument parser inspired by zig-clap
/// Provides yargs-like experience for Vimcraft CLI commands
const std = @import("std");

/// Command-line argument parsing result
pub const ParseResult = struct {
    command: ?[]const u8,
    file_path: ?[]const u8,
    force: bool,
    debug: bool,
    no_cache: bool,
    metrics: bool,
    check: bool, // For 'types --check'
    verbose: bool, // For 'test --verbose'
    help: bool,
    version: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        // Free duplicated strings
        if (self.command) |cmd| {
            self.allocator.free(cmd);
        }
        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }
};

/// Parse command-line arguments
pub fn parse(allocator: std.mem.Allocator) !ParseResult {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var result = ParseResult{
        .command = null,
        .file_path = null,
        .force = false,
        .debug = false,
        .no_cache = false,
        .metrics = false,
        .check = false,
        .verbose = false,
        .help = false,
        .version = false,
        .allocator = allocator,
    };

    if (args.len < 2) {
        // No arguments - open empty buffer (like nvim)
        // Leave command and file_path as null to trigger editor mode
        return result;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            result.force = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            result.debug = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            result.no_cache = true;
        } else if (std.mem.eql(u8, arg, "--metrics")) {
            result.metrics = true;
        } else if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            result.check = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-V")) {
            result.verbose = true;
        } else if (std.mem.eql(u8, arg, "test")) {
            // Test runner - PTY + Hermes + JSON report
            result.command = try allocator.dupe(u8, "test");
            // Parse remaining arguments for test command
            i += 1;
            while (i < args.len) : (i += 1) {
                const test_arg = args[i];
                if (std.mem.eql(u8, test_arg, "--verbose") or std.mem.eql(u8, test_arg, "-V")) {
                    result.verbose = true;
                } else if (!std.mem.startsWith(u8, test_arg, "-")) {
                    // Sandbox path (positional)
                    if (result.file_path == null) {
                        result.file_path = try allocator.dupe(u8, test_arg);
                    }
                }
            }
            return result;
        } else if (std.mem.eql(u8, arg, "--test")) {
            result.command = try allocator.dupe(u8, arg);
            if (i + 1 < args.len) {
                i += 1;
                result.file_path = try allocator.dupe(u8, args[i]);
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // Unknown flag
            std.debug.print("Unknown flag: {s}\n", .{arg});
            result.help = true;
            return result;
        } else if (result.command == null) {
            // First positional argument is the command
            result.command = try allocator.dupe(u8, arg);
        } else if (result.file_path == null) {
            // Second positional argument is the file path
            result.file_path = try allocator.dupe(u8, arg);
        }
    }

    return result;
}

/// Print help message
pub fn printHelp() void {
    std.debug.print(
        \\Vimcraft - Neovim-compatible text editor
        \\
        \\USAGE:
        \\  vimc [OPTIONS] [COMMAND|FILE]
        \\
        \\COMMANDS:
        \\  init [--force]              Initialize TypeScript toolchain
        \\  run <file> [--debug] [--no-cache]  Execute TypeScript/JavaScript file
        \\  test <sandbox_path> [-V]    Run tests (--verbose for detailed output)
        \\  install <package>           Install plugin from Git URL (TODO)
        \\  list                        List installed plugins (TODO)
        \\  types [--check]             Sync vim.d.ts (--check to verify without updating)
        \\
        \\OPTIONS:
        \\  -h, --help                  Display this help and exit
        \\  -v, --version               Show version information
        \\  -f, --force                 Force overwrite existing files (init command)
        \\  -d, --debug                 Enable debug mode
        \\  -c, --check                 Check mode (types command)
        \\  -V, --verbose               Verbose output (test command)
        \\      --no-cache              Disable bytecode caching
        \\      --metrics               Enable performance metrics tracking
        \\
        \\EDITOR MODES:
        \\  vimc                        Open empty buffer (uses cwd as working dir)
        \\  vimc <file>                 Open file in interactive editor
        \\  vimc --debug <file>         Open file with Chrome DevTools debugging
        \\  vimc --test <test_file>     Run automated test script
        \\  vimc --repl                 Interactive debugging REPL
        \\
        \\EXAMPLES:
        \\  vimc                        Start with empty buffer (like nvim)
        \\  vimc init                   Initialize TypeScript toolchain
        \\  vimc run plugin.ts          Execute TypeScript plugin
        \\  vimc test tests/e2e/basic   Run tests in sandbox
        \\  vimc README.md              Edit file in Vim mode
        \\  vimc --debug init.js        Debug JavaScript config
        \\
        \\For more information, visit: https://github.com/vimcraft/vimcraft
        \\
    , .{});
}

/// Print version information
pub fn printVersion() void {
    std.debug.print("vimc 0.1.0 (Vimcraft Editor)\n", .{});
}
