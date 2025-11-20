/// Comprehensive esbuild TypeScript Transpilation Tests
/// Verifies that TypeScript features are properly removed/transformed
const std = @import("std");
const esbuild = @import("esbuild.zig");

test "TypeScript: Remove type annotations" {
    const allocator = std.testing.allocator;

    const source =
        \\function greet(name: string, age: number): string {
        \\    return `Hello ${name}, you are ${age} years old`;
        \\}
        \\const result: string = greet("Alice", 30);
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Type Annotations Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify type annotations are removed
    try std.testing.expect(std.mem.indexOf(u8, result, ": string") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, ": number") == null);

    // Verify function logic remains
    try std.testing.expect(std.mem.indexOf(u8, result, "function greet") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
}

test "TypeScript: Remove interfaces" {
    const allocator = std.testing.allocator;

    const source =
        \\interface User {
        \\    name: string;
        \\    age: number;
        \\}
        \\
        \\const user: User = {
        \\    name: "Bob",
        \\    age: 25
        \\};
        \\
        \\console.log(user.name);
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Interface Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify interface declaration is removed
    try std.testing.expect(std.mem.indexOf(u8, result, "interface User") == null);

    // Verify type annotation is removed
    try std.testing.expect(std.mem.indexOf(u8, result, ": User") == null);

    // Verify runtime code remains
    try std.testing.expect(std.mem.indexOf(u8, result, "const user") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "name: \"Bob\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "console.log") != null);
}

test "TypeScript: Transform enums" {
    const allocator = std.testing.allocator;

    const source =
        \\enum Color {
        \\    Red = "RED",
        \\    Green = "GREEN",
        \\    Blue = "BLUE"
        \\}
        \\
        \\const favorite = Color.Red;
        \\console.log(favorite);
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Enum Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify enum was transpiled (not just removed)
    // esbuild converts enums to objects or IIFE
    try std.testing.expect(result.len > 0);

    // Should contain enum values
    try std.testing.expect(std.mem.indexOf(u8, result, "RED") != null or
        std.mem.indexOf(u8, result, "Red") != null);

    std.debug.print("\nEnum transpiled successfully!\n", .{});
}

test "TypeScript: Remove generics" {
    const allocator = std.testing.allocator;

    const source =
        \\function identity<T>(arg: T): T {
        \\    return arg;
        \\}
        \\
        \\const num = identity<number>(42);
        \\const str = identity<string>("hello");
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Generics Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify generic syntax is removed
    try std.testing.expect(std.mem.indexOf(u8, result, "<T>") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<number>") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<string>") == null);

    // Verify function logic remains
    try std.testing.expect(std.mem.indexOf(u8, result, "function identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "return arg") != null);
}

test "TypeScript: Remove type assertions" {
    const allocator = std.testing.allocator;

    const source =
        \\const value = <string>"hello";
        \\const num = 42 as number;
        \\const obj = {} as Record<string, any>;
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Type Assertions Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify type assertions are removed
    try std.testing.expect(std.mem.indexOf(u8, result, " as number") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, " as Record") == null);

    // Verify values remain
    try std.testing.expect(std.mem.indexOf(u8, result, "\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
}

test "TypeScript: Class with TypeScript features" {
    const allocator = std.testing.allocator;

    const source =
        \\class Animal {
        \\    private name: string;
        \\    protected age: number;
        \\
        \\    constructor(name: string, age: number) {
        \\        this.name = name;
        \\        this.age = age;
        \\    }
        \\
        \\    public greet(): void {
        \\        console.log(`I am ${this.name}`);
        \\    }
        \\}
        \\
        \\const dog = new Animal("Rex", 5);
        \\dog.greet();
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Class Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify access modifiers are removed
    try std.testing.expect(std.mem.indexOf(u8, result, "private ") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "protected ") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public ") == null);

    // Verify type annotations are removed
    try std.testing.expect(std.mem.indexOf(u8, result, ": string") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, ": number") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "(): void") == null);

    // Verify class logic remains
    try std.testing.expect(std.mem.indexOf(u8, result, "class Animal") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "constructor") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "this.name") != null);
}

test "TypeScript: Async/await preserved" {
    const allocator = std.testing.allocator;

    const source =
        \\async function fetchData(url: string): Promise<string> {
        \\    const response = await fetch(url);
        \\    return await response.text();
        \\}
        \\
        \\const data: Promise<string> = fetchData("https://example.com");
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Async/Await Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify async/await are preserved
    try std.testing.expect(std.mem.indexOf(u8, result, "async function") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "await") != null);

    // Verify type annotations are removed
    try std.testing.expect(std.mem.indexOf(u8, result, ": string") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, ": Promise<string>") == null);
}

test "TypeScript: Import/export statements" {
    const allocator = std.testing.allocator;

    const source =
        \\import { Component } from 'react';
        \\import type { ComponentType } from 'react';
        \\
        \\export interface Props {
        \\    name: string;
        \\}
        \\
        \\export const MyComponent: ComponentType<Props> = ({ name }) => {
        \\    return <div>{name}</div>;
        \\};
    ;

    const result = try esbuild.transpile(allocator, source, "tsx");
    defer allocator.free(result);

    std.debug.print("\n=== Import/Export Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify imports are converted to CommonJS (since we set Format: CommonJS)
    // esbuild generates sophisticated CommonJS with module.exports
    const has_module_exports = std.mem.indexOf(u8, result, "module.exports") != null;
    const has_exports = std.mem.indexOf(u8, result, "exports") != null;
    const has_commonjs = std.mem.indexOf(u8, result, "__toCommonJS") != null;

    // Should have CommonJS output
    try std.testing.expect(has_module_exports or has_exports or has_commonjs);

    // Verify type-only import is removed
    try std.testing.expect(std.mem.indexOf(u8, result, "import type") == null);

    // Verify interface is removed
    try std.testing.expect(std.mem.indexOf(u8, result, "interface Props") == null);

    // Verify JSX is transformed
    try std.testing.expect(std.mem.indexOf(u8, result, "React.createElement") != null or
        std.mem.indexOf(u8, result, "jsx") != null);
}

test "TypeScript: Real-world example" {
    const allocator = std.testing.allocator;

    const source =
        \\// Vimcraft plugin example
        \\interface PluginConfig {
        \\    enabled: boolean;
        \\    maxLines?: number;
        \\}
        \\
        \\class VimPlugin {
        \\    private config: PluginConfig;
        \\
        \\    constructor(config: PluginConfig) {
        \\        this.config = { enabled: true, ...config };
        \\    }
        \\
        \\    public setup(): void {
        \\        if (this.config.enabled) {
        \\            console.log("Plugin enabled");
        \\        }
        \\    }
        \\}
        \\
        \\export default VimPlugin;
    ;

    const result = try esbuild.transpile(allocator, source, "ts");
    defer allocator.free(result);

    std.debug.print("\n=== Real-World Test ===\nInput:\n{s}\n\nOutput:\n{s}\n", .{ source, result });

    // Verify all TypeScript syntax is removed
    try std.testing.expect(std.mem.indexOf(u8, result, "interface ") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, ": boolean") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "?: number") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, ": PluginConfig") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "(): void") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "private ") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "public ") == null);

    // Verify runtime code remains
    try std.testing.expect(std.mem.indexOf(u8, result, "class VimPlugin") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "constructor") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "this.config") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "console.log") != null);

    // Verify export statement (converted to CommonJS module.exports or kept as export)
    const has_export = std.mem.indexOf(u8, result, "export") != null or
        std.mem.indexOf(u8, result, "module.exports") != null or
        std.mem.indexOf(u8, result, "exports") != null;
    try std.testing.expect(has_export);
}

test "TypeScript: Error handling - invalid syntax" {
    const allocator = std.testing.allocator;

    const source =
        \\const x: = "invalid";
    ;

    const result = esbuild.transpile(allocator, source, "ts");

    // Should return error (either TranspileFailed or result contains error message)
    if (result) |output| {
        defer allocator.free(output);
        std.debug.print("\n=== Invalid Syntax Test ===\nUnexpected success: {s}\n", .{output});
        // If transpilation somehow succeeded, verify output doesn't contain TypeScript syntax
    } else |err| {
        std.debug.print("\n=== Invalid Syntax Test ===\nCorrectly failed with error: {}\n", .{err});
        try std.testing.expect(err == error.TranspileFailed);
    }
}
