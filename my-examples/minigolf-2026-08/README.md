# Mini Golf 3D — Web Build

This example now supports a web build via Emscripten + WebGL.

## Quick Build

```bash
cd my-examples/minigolf-2026-08
./build_web.sh
```

Output goes to `build_web/`:
- `index.html` — self-contained page
- `index.js` — Emscripten runtime
- `index.wasm` — compiled game

## Serve & Test

```bash
cd build_web
python3 -m http.server 8000
# open http://localhost:8000
```

> Note: The WebGL backend is currently a skeleton. The build compiles and links, but rendering will not display until the GPU backend is implemented.

## Architecture

This uses the ravn-engine's new Emscripten export pipeline:

1. Odin compiles the package to a WASM object file (`-build-mode:obj`)
2. Emscripten (`emcc`) links the object, generating the HTML shell
3. The `index_template.html` sets up the Odin WASM memory interface, import stubs, and frame loop

See `../../WEBGL_EXPORT.md` for full documentation.
