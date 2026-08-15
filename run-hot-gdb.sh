#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-path> [extra-odin-flags...]"
    echo "Example: $0 examples/hello -error-pos-style:unix"
    echo ""
    echo "Starts the hot-reload runner under plain GDB."
    echo "GDB will auto-load symbols when new .so files are dlopen'd."
    echo ""
    echo "Recommended GDB commands after startup:"
    echo "  set breakpoint pending on"
    echo "  break <your_package>::_update"
    echo "  continue"
    echo ""
    echo "Then in another terminal, rebuild with:"
    echo "  ./build-hot.sh <package-path> [extra-odin-flags...]"
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

# Allow setting breakpoints in libraries that haven't loaded yet
set breakpoint pending on

# Don't paginate output
set pagination off
set confirm off
EOF

echo ""
echo "=== Starting plain GDB ==="
echo "GDB will auto-load symbols when new .so files are dlopen'd."
echo ""
echo "Recommended commands after startup:"
echo "  set breakpoint pending on    # (already in .gdbinit-ravn-hot)"
echo "  break <your_package>::_update"
echo "  continue"
echo ""
echo "After editing code, run in another terminal:"
echo "  ./build-hot.sh $PKG $*"
echo ""
echo "If auto-solib-add fails, the build-hot script prints a fallback"
echo "  source .gdb-hot-reload"
echo ""

# Launch plain gdb directly
gdb -x .gdbinit-ravn-hot --args ./build_runner run-hot "$PKG" "$@"
