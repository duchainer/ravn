#!/usr/bin/env bash
set -eu

# ravn-engine web build with raylib backend (Emscripten + WebGL2).
#
# Prereqs:
#   1. emscripten on PATH (or set EMSCRIPTEN_SDK_DIR)
#   2. raylib built for web:
#      cd <raylib>/src && make PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES3 -B
#      Then set RAYLIB_WEB_DIR below to that src/ directory.
#
# Usage: ./build_web_raylib.sh <package-path>
# Example: ./build_web_raylib.sh examples/snake_planet

EMSCRIPTEN_SDK_DIR="${EMSCRIPTEN_SDK_DIR:-$HOME/repos/emsdk}"
RAYLIB_WEB_DIR="${RAYLIB_WEB_DIR:-$HOME/repos/raylib/src}"
OUT_DIR="build_web"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package-path> [extra-odin-flags...]"
    echo "Example: $0 examples/snake_planet"
    exit 1
fi

PKG="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$OUT_DIR"

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

ODIN_PATH=$(odin root)
PKG_NAME=$(basename "$PKG")
OUT_OBJ="$OUT_DIR/${PKG_NAME}.o"

echo "=== Building Odin object file for js_wasm32 (raylib backend) ==="

odin build "$PKG" \
    -target:js_wasm32 \
    -build-mode:obj \
    -o:speed \
    -define:RELEASE=true \
    -define:PLATFORM_BACKEND=Raylib \
    -define:GPU_BACKEND=Raylib \
    -out:"$OUT_OBJ" \
    "$@"

echo "=== Copying odin.js runtime ==="
cp "$ODIN_PATH/core/sys/wasm/js/odin.js" "$OUT_DIR/"

echo "=== Linking with emcc + raylib (web) ==="

emcc -o "$OUT_DIR/index.html" "$OUT_OBJ" \
    -L"$RAYLIB_WEB_DIR" -lraylib \
    -sUSE_GLFW=3 \
    -sUSE_WEBGL2=1 \
    -sFULL-ES3=1 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sINITIAL_MEMORY=64MB \
    -sMAXIMUM_MEMORY=256MB \
    -sWASM_BIGINT \
    -sASSERTIONS=1 \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 \
    "-sEXPORTED_FUNCTIONS=[_web_start,_step,_malloc,_free]" \
    "-sEXPORTED_RUNTIME_METHODS=[ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,lengthBytesUTF8]" \
    --shell-file "$SCRIPT_DIR/web/shell_minimal.html"

rm -f "$OUT_OBJ"

echo "=== Web build created: ${OUT_DIR}/index.html ==="
echo "Serve: python3 -m http.server -d ${OUT_DIR}"
