#!/usr/bin/env bash
set -eu

# Emscripten + WebGL build script for ravn-engine games
# Based on the raylib hot-reload template approach
#
# Usage: ./build_web.sh
# Output: build_web/index.html (self-contained)

# Point this to where you installed emscripten. Optional on systems that already
# have `emcc` in the path.
EMSCRIPTEN_SDK_DIR="$HOME/repos/emsdk"
OUT_DIR="build_web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

ODIN_PATH=$(odin root)

echo "Building Odin object file for js_wasm32 ..."

# Build the game package as an object file. We compile the minigolf package
# directly (it contains main() which will be called by Emscripten on startup).
# NOTE: Replace with your package path if building something else.
\
  odin build . \
  -target:js_wasm32 \
  -build-mode:obj \
  -define:RELEASE=true \
  -define:GPU_BACKEND=WebGL \
  -out:$OUT_DIR/game.o

echo "Copying odin.js runtime ..."
cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

echo "Linking with emcc ..."

files="$OUT_DIR/game.obj"

# NOTE: Use a bash array so flags with spaces/commas are not mangled by word splitting.
emcc_flags=(
  -sWASM_BIGINT
  -sASSERTIONS=1
  -sERROR_ON_UNDEFINED_SYMBOLS=0
  -sALLOW_MEMORY_GROWTH=1
  -sMAXIMUM_MEMORY=256MB
  -sINITIAL_MEMORY=64MB
  "-sEXPORTED_FUNCTIONS=[_web_start,_step,_malloc,_free]"
  "-sEXPORTED_RUNTIME_METHODS=[ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,lengthBytesUTF8,addFunction,removeFunction]"
  --shell-file index_template.html
)

# Uncomment to enable debug symbols in the wasm output
# emcc_flags+=(-g)

# If you have runtime assets (not compile-time embedded), add:
# emcc_flags+=(--preload-file assets)

emcc -o "$OUT_DIR/index.html" "$files" "${emcc_flags[@]}"

rm "$OUT_DIR/game.obj"

echo "Web build created in ${OUT_DIR}/index.html"
