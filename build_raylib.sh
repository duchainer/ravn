#!/usr/bin/env bash
set -eu

# Build ravn-engine examples with the raylib backend (desktop).
#
# Prereqs: raylib installed system-wide (libraylib.so / libraylib.a + headers)
#   Ubuntu/Debian: sudo apt install libraylib-dev
#   Or build from source: https://github.com/raysan5/raylib/wiki/Working-on-GNU-Linux
#
# Usage: ./build_raylib.sh <package-path>
# Example: ./build_raylib.sh examples/snake_planet

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-path> [extra-odin-flags...]"
    echo "Example: $0 examples/snake_planet"
    exit 1
fi

PKG="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT="${PKG##*/}_raylib"

echo "=== Building ${PKG} with raylib backend ==="

odin build "$PKG" \
    -define:PLATFORM_BACKEND=Raylib \
    -define:GPU_BACKEND=Raylib \
    -out:"$OUT" \
    -extra-linker-flags:"-lraylib -lGL -lm -lpthread -ldl -lrt -lX11" \
    "$@"

echo "=== Built: ${OUT} ==="
echo "Run: ./${OUT}"
