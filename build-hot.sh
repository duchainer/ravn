#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-path> [extra-odin-flags...]"
    echo "Example: $0 my-examples/minigolf-2026-08 -error-pos-style:unix"
    exit 1
fi

PKG="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building hot-reload DLL ==="
odin run build/ -- build-hot "$PKG" "$@"

PKG_NAME=$(basename "$PKG")

# Find the latest .so that was just built
LATEST_SO=$(ls -t ./"${PKG_NAME}"*.so 2>/dev/null | head -n1)

if [ -n "$LATEST_SO" ]; then
    FULLPATH="$(realpath "$LATEST_SO")"
    echo ""
    echo "=== Built: $LATEST_SO ==="

    # Write a gdb command file in case auto-load didn't work
    echo "add-symbol-file $FULLPATH" > .gdb-hot-reload
    echo "sharedlibrary" >> .gdb-hot-reload

    echo ""
    echo "=== GDB should auto-load symbols when the runner dlopen's this .so ==="
    echo "=== If symbols didn't load, run this in the gdb prompt (or gud buffer): ==="
    echo "source .gdb-hot-reload"
    echo ""
    echo "=== Or manually: ==="
    echo "add-symbol-file $FULLPATH"
    echo ""
else
    echo "Warning: Could not find newly built .so file for '$PKG_NAME'"
fi
