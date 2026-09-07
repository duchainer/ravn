# WebGL Export (Emscripten)

This document describes the new WebGL/Emscripten web export pipeline for ravn-engine, replacing the previous broken WebGPU approach.

## Overview

The web export uses a two-stage build process similar to the [odin-raylib-hot-reload-game-template](https://github.com/odin-lang/odin-raylib-hot-reload-game-template):

1. **Odin compiles to WASM object**: `odin build -target:js_wasm32 -build-mode:obj`
2. **Emscripten links**: `emcc` takes the object file and produces a self-contained `index.html`

## Why Emscripten + WebGL?

The previous WebGPU approach relied on raw WebGPU bindings that were brittle across browsers. Emscripten provides:

- Stable WebGL 2.0 (OpenGL ES 3.0) translation via `EM_JS`/`EM_ASM` bindings
- Mature memory management (`malloc`/`free`) integration with Odin's WASM allocator
- Built-in `index.html` shell generation with `--shell-file`
- Better browser compatibility (WebGL 2.0 is supported everywhere WebGPU isn't)

## Build Steps

### For the Minigolf Example

```bash
cd my-examples/minigolf-2026-08
./build_web.sh
```

Output: `build_web/index.html` (self-contained, with `index.js` and `index.wasm`)

### For Other Projects

Use the `ravn_build` tool:

```bash
odin run build export-web <pkg-name> <pkg-path>
```

This calls `export_web()` in `build/build_web.odin`, which:
1. Compiles the package to a `.wasm.o` object file with `-build-mode:obj`
2. Copies `odin.js` from the Odin distribution
3. Generates `index_template.html` with the Emscripten shell and Odin import stubs
4. Links with `emcc` to produce the final `index.html`

## Key Files

| File | Purpose |
|------|---------|
| `build/build_web.odin` | Build tool logic (`export_web`, `compile_web_obj`, `link_emcc`) |
| `gpu/gpu_webgl.odin` | WebGL backend skeleton (GPU abstraction layer) |
| `gpu/gpu.odin` | Updated to default to `BACKEND_WEBGL` on `ODIN_OS == .JS` |
| `shader_compiler/shader_compiler.odin` | Added `GLSL_ES` target |
| `shader_compiler/shader_compiler_slang.odin` | Slang compiler path for GLSL ES |
| `data/*.hlsl.glsl_es` | Placeholder GLSL ES shaders (compile with `build builtin-shaders`) |

## HTML Template

The `index_template.html` (used by both the example and `build/build_web.odin`) sets up:

1. **Odin WASM interface**: Loads `odin.js`, creates `WasmMemoryInterface`, calls `setupDefaultImports()`
2. **Custom import stubs**: Provides stub implementations for missing foreign imports:
   - `stbi_*` (image loading) — stub returns 0/failure
   - `ravn_platform` (canvas, input, pointer lock) — stub does nothing
   - `ravn_audio` (audio buffer push) — stub does nothing
3. **Emscripten `Module` configuration**:
   - `instantiateWasm`: Merges Odin imports with Emscripten imports, then instantiates the WASM module
   - `onRuntimeInitialized`: Calls `_web_start()` (exported entry point), then drives the frame loop via `_step()` and `requestAnimationFrame`
   - `canvas`: Binds the `<canvas>` element for Emscripten's SDL/GLFW canvas handling

## GPU Backend (`gpu_webgl.odin`)

This is a **structural skeleton** that implements the full `ravn_gpu` abstraction. All procedures are declared but currently either do nothing or `panic()` on compute operations (WebGL 2.0 does not support compute shaders).

### Implementation TODO

The following need to be filled in with actual WebGL/OpenGL ES calls:

- `_init()`: Create WebGL 2.0 context on the canvas, set up initial GL state
- `_begin_frame()` / `_end_frame()`: Bind default framebuffer, clear, swap
- `_create_pipeline()`: Compile GLSL ES shaders, link program, create VAO
- `_create_texture_2d()`: `glTexImage2D` / `glTexStorage2D`
- `_create_buffer()` / `_create_index_buffer()`: `glGenBuffers` + `glBufferData`
- `_update_buffer()` / `_update_texture_2d()`: `glBufferSubData` / `glTexSubImage2D`
- `_begin_pass()`: Bind FBO, set clear values
- `_set_pipeline()`: `glUseProgram`, set vertex attrib pointers
- `_draw_non_indexed()` / `_draw_indexed()`: `glDrawArrays` / `glDrawElements` (with instancing via `glDrawArraysInstanced` / `glDrawElementsInstanced` in WebGL 2)
- `_update_constants()`: `glBufferSubData` for UBOs, or `glUniform*` for legacy uniforms
- `_destroy_*()`: `glDelete*` cleanup

## Shader Compilation

Shaders are compiled from HLSL to GLSL ES via the Slang compiler:

```bash
odin run build builtin-shaders
```

This produces:
- `data/default.vs.hlsl.glsl_es` — vertex shader
- `data/default.ps.hlsl.glsl_es` — pixel shader
- `data/default_sprite.vs.hlsl.glsl_es` — sprite vertex shader

The `GLSL_ES` target uses Slang's `GLSL` target with the `glsl_es_310` profile (OpenGL ES 3.1 / WebGL 2.0 compatible).

## Known Issues / Warnings

### Undefined Symbol Warnings

During `emcc` linking, you may see warnings like:

```
warning: undefined symbol: add_window_event_listener
warning: undefined symbol: stbi_load_from_memory
```

These are **expected** — the Odin code declares these as foreign imports, but the actual implementations are provided as JS stubs in the HTML template. Emscripten warns because it doesn't see them at link time, but they are resolved at runtime via the `customImports` object passed to `WebAssembly.instantiate()`.

### Missing Image Loading

The `stbi_*` stubs return failure, so `load_texture()` from PNG data will fail. To fix this, either:
- Compile `stb_image.c` with `emcc` and link the resulting `.a` library
- Replace with a browser-side JS image decoder that writes to a WebGL texture directly

### Missing Audio

The `ravn_audio` stubs do nothing. To enable audio, include `ravn_webaudio.js` and `ravn_webaudio_processor.js` in the HTML and wire their `getInterface()` exports into `customImports`.

### Missing Platform Features

Pointer lock, window events, and gamepad input are stubbed. To enable them, include `ravn_platform.js` in the HTML and wire its `RavnPlatformInterface.getInterface()` into `customImports`.

## Switching Back to WGPU

If you need to test the old WebGPU backend, override the default at compile time:

```bash
odin build . -target:js_wasm32 -define:GPU_BACKEND=WGPU
```

The default for `js_wasm32` is now `WebGL`:

```odin
// gpu/gpu.odin
when ODIN_OS == .JS {
    DEFAULT_BACKEND :: BACKEND_WEBGL
}
```
