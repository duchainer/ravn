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

# Build the hot-reload runner with debug info
echo "=== Building hot-reload runner ==="
odin build build/ -out:build_runner -debug "$@"

# Create a gdb script for better hot-reload experience
cat > .gdbinit-ravn-hot <<'EOF'
# Auto-load shared libraries (needed for hot-reload .so files)
set auto-solib-add on
set stop-on-solib-events 0

# Don't paginate output
set pagination off
set confirm off

# Break at main so you can set initial breakpoints before the game starts
break main
EOF

echo ""
echo "=== Starting Emacs with gud-gdb ==="
echo "GDB will auto-load symbols when new .so files are dlopen'd."
echo "After editing code, run in another terminal:"
echo "  ./build-hot.sh $PKG $*"
echo ""

# Build the gdb command string, preserving extra flags
GDB_CMD="gdb -i=mi -x .gdbinit-ravn-hot --args ./build_runner run-hot $PKG"
for arg in "$@"; do
    GDB_CMD="$GDB_CMD $arg"
done

# Launch Emacs with gud-gdb
emacs --eval "(gud-gdb \"$GDB_CMD\")"
