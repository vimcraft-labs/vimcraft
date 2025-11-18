#!/usr/bin/env bash
# Cross-platform build script for go-enry shared library
# Supports: macOS (darwin), Linux, Windows
#
# Usage:
#   ./scripts/build-enry.sh           # Auto-detect platform
#   ./scripts/build-enry.sh darwin    # Build for macOS
#   ./scripts/build-enry.sh linux     # Build for Linux
#   ./scripts/build-enry.sh windows   # Build for Windows

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect platform if not specified
if [ $# -eq 0 ]; then
    case "$OSTYPE" in
        darwin*)  PLATFORM="darwin" ;;
        linux*)   PLATFORM="linux" ;;
        msys*|cygwin*) PLATFORM="windows" ;;
        *)
            echo -e "${RED}Error: Unsupported platform: $OSTYPE${NC}"
            echo "Supported platforms: darwin (macOS), linux, windows"
            exit 1
            ;;
    esac
else
    PLATFORM="$1"
fi

# Validate platform
case "$PLATFORM" in
    darwin|linux|windows) ;;
    *)
        echo -e "${RED}Error: Invalid platform: $PLATFORM${NC}"
        echo "Valid platforms: darwin, linux, windows"
        exit 1
        ;;
esac

# Set platform-specific variables
case "$PLATFORM" in
    darwin)
        EXT="dylib"
        GOOS="darwin"
        # Build universal binary by default, unless ENRY_SINGLE_ARCH=1 (for CI/CD)
        if [ "${ENRY_SINGLE_ARCH:-0}" = "1" ]; then
            # Single-architecture build (detect current architecture)
            case "$(uname -m)" in
                x86_64)
                    GOARCH="amd64"
                    ;;
                arm64)
                    GOARCH="arm64"
                    ;;
                *)
                    echo -e "${YELLOW}Warning: Unknown architecture $(uname -m), defaulting to arm64${NC}"
                    GOARCH="arm64"
                    ;;
            esac
            BUILD_UNIVERSAL=false
        else
            # Build universal binary (local development default)
            BUILD_UNIVERSAL=true
        fi
        ;;
    linux)
        EXT="so"
        GOOS="linux"
        # Auto-detect architecture
        case "$(uname -m)" in
            x86_64)
                GOARCH="amd64"
                ;;
            aarch64|arm64)
                GOARCH="arm64"
                ;;
            *)
                echo -e "${YELLOW}Warning: Unknown architecture $(uname -m), defaulting to amd64${NC}"
                GOARCH="amd64"
                ;;
        esac
        BUILD_UNIVERSAL=false
        ;;
    windows)
        EXT="dll"
        GOOS="windows"
        GOARCH="amd64"  # Windows builds typically target amd64
        BUILD_UNIVERSAL=false
        ;;
esac

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENRY_DIR="$PROJECT_ROOT/vendor/go-enry"
OUTPUT_DIR="$ENRY_DIR/.shared/$PLATFORM"
OUTPUT_FILE="$OUTPUT_DIR/libenry.$EXT"

# Check if go-enry exists
if [ ! -d "$ENRY_DIR" ]; then
    echo -e "${RED}Error: go-enry not found at $ENRY_DIR${NC}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo "Install Go from https://golang.org/dl/"
    exit 1
fi

# Check Go version (require 1.18+)
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
REQUIRED_VERSION="1.18"
if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo -e "${YELLOW}Warning: Go $REQUIRED_VERSION+ recommended (you have $GO_VERSION)${NC}"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${GREEN}Building go-enry for $PLATFORM...${NC}"
echo "  Platform: $PLATFORM"
echo "  GOOS:     $GOOS"
if [ "$BUILD_UNIVERSAL" = true ]; then
    echo "  GOARCH:   arm64 + amd64 (universal)"
else
    echo "  GOARCH:   $GOARCH"
fi
echo "  Output:   $OUTPUT_FILE"

# Change to go-enry directory
cd "$ENRY_DIR"

# Build shared library
echo -e "${YELLOW}Compiling shared library...${NC}"

if [ "$BUILD_UNIVERSAL" = true ]; then
    # Build universal binary for macOS (arm64 + amd64)
    echo "  Building for arm64..."
    CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
        go build -mod=mod -buildmode=c-shared \
        -o "${OUTPUT_FILE}.arm64" \
        ./shared/enry.go

    echo "  Building for amd64..."
    CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
        go build -mod=mod -buildmode=c-shared \
        -o "${OUTPUT_FILE}.amd64" \
        ./shared/enry.go

    echo "  Creating universal binary..."
    lipo -create \
        "${OUTPUT_FILE}.arm64" \
        "${OUTPUT_FILE}.amd64" \
        -output "$OUTPUT_FILE"

    # Fix install names in the universal binary
    echo "  Fixing install names..."
    install_name_tool -id "@rpath/libenry.dylib" "$OUTPUT_FILE"

    # Clean up temporary files
    rm -f "${OUTPUT_FILE}.arm64" "${OUTPUT_FILE}.amd64"
    rm -f "${OUTPUT_FILE}.arm64.h" "${OUTPUT_FILE}.amd64.h"
else
    # Single-architecture build (Linux/Windows/macOS single-arch)
    CGO_ENABLED=1 \
    GOOS="$GOOS" \
    GOARCH="$GOARCH" \
    go build -mod=mod -buildmode=c-shared \
        -o "$OUTPUT_FILE" \
        ./shared/enry.go

    # Fix install name for macOS single-arch builds
    if [ "$PLATFORM" = "darwin" ]; then
        echo "  Fixing install name..."
        install_name_tool -id "@rpath/libenry.dylib" "$OUTPUT_FILE"
    fi
fi

# Verify build
if [ ! -f "$OUTPUT_FILE" ]; then
    echo -e "${RED}Error: Build failed - $OUTPUT_FILE not created${NC}"
    exit 1
fi

# Get file size
FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')

echo -e "${GREEN}✅ Build successful!${NC}"
echo "  Output: $OUTPUT_FILE"
echo "  Size:   $FILE_SIZE"

# Platform-specific post-build steps
case "$PLATFORM" in
    darwin)
        # Verify it's a universal binary
        if command -v lipo &> /dev/null; then
            echo -e "${YELLOW}Checking architecture...${NC}"
            lipo -info "$OUTPUT_FILE" || true
        fi
        ;;
    linux)
        # Verify ELF binary
        if command -v file &> /dev/null; then
            echo -e "${YELLOW}Checking binary format...${NC}"
            file "$OUTPUT_FILE"
        fi
        ;;
esac

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Update build.zig to use: vendor/go-enry/.shared/$PLATFORM"
echo "  2. Run: zig build test"
echo ""
