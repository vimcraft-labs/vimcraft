#!/bin/bash
set -e

echo "=== Building esbuild C wrapper ==="

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go not found. Install from https://go.dev/dl/"
    exit 1
fi

# Download dependencies
go mod download

# Build shared library for current platform
OS=$(uname -s)
ARCH=$(uname -m)

if [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        # macOS ARM64
        go build -buildmode=c-shared -o libesbuild_darwin_arm64.dylib esbuild_c.go
        echo "Built: libesbuild_darwin_arm64.dylib"
        # Fix install_name for @rpath resolution
        install_name_tool -id "@rpath/libesbuild_darwin_arm64.dylib" libesbuild_darwin_arm64.dylib
    else
        # macOS x86_64
        go build -buildmode=c-shared -o libesbuild_darwin_x86_64.dylib esbuild_c.go
        echo "Built: libesbuild_darwin_x86_64.dylib"
        # Fix install_name for @rpath resolution
        install_name_tool -id "@rpath/libesbuild_darwin_x86_64.dylib" libesbuild_darwin_x86_64.dylib
    fi
elif [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "aarch64" ]; then
        # Linux ARM64 (aarch64)
        go build -buildmode=c-shared -o libesbuild_linux_aarch64.so esbuild_c.go
        echo "Built: libesbuild_linux_aarch64.so"
    else
        # Linux x86_64
        go build -buildmode=c-shared -o libesbuild_linux_x86_64.so esbuild_c.go
        echo "Built: libesbuild_linux_x86_64.so"
    fi
fi

echo "=== Build complete ==="
ls -lh libesbuild_*
