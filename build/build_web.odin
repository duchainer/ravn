package ravn_build

import "../platform"
import "../base"
import "../base/ufmt"

import "core:strconv"
import "core:strings"

WASM_PAGE_SIZE :: 65536

DEFAULT_INITIAL_MEM_PAGES :: 4000
DEFAULT_MAX_MEM_PAGES :: 65536

// export_web_emscripten creates a web build using Emscripten + WebGL.
// This replaces the old raw wasm approach which relied on WebGPU.
export_web :: proc(dst_dir: string, pkg_name: string, pkg_path: string) -> bool {
	remove_all(strings.concatenate({dst_dir, platform.SEPARATOR, "*"}))
	platform.create_directory(dst_dir)

	initial_mem_pages := DEFAULT_INITIAL_MEM_PAGES
	max_mem_pages := DEFAULT_MAX_MEM_PAGES

	base.log_info("Compiling WASM object file ...")

	if !compile_web_obj(dst_dir,
		pkg_name = pkg_name,
		pkg_path = pkg_path,
		initial_mem_pages = initial_mem_pages,
		max_mem_pages = max_mem_pages,
	) {
		base.log_info("Error: failed to compile to WASM object file")
		return false
	}

	base.log_info("Copying odin.js runtime ...")

	odin_js_source := #load(ODIN_ROOT + "core/sys/wasm/js/odin.js")
	platform.write_file_by_path(
		ufmt.tprintf("%s/odin.js", dst_dir),
		odin_js_source,
	)

	base.log_info("Writing shell template ...")

	html := generate_html(
		title = pkg_name,
		pkg_name = pkg_name,
		initial_mem_pages = initial_mem_pages,
		max_mem_pages = max_mem_pages,
	)

	platform.write_file_by_path(
		ufmt.tprintf("%s/index_template.html", dst_dir),
		transmute([]byte)html,
	)

	base.log_info("Linking with emcc ...")

	if !link_emcc(dst_dir,
		pkg_name = pkg_name,
		initial_mem_pages = initial_mem_pages,
		max_mem_pages = max_mem_pages,
	) {
		base.log_info("Error: emcc linking failed")
		return false
	}

	return true
}

compile_web_obj :: proc(dst_dir: string, pkg_name: string, pkg_path: string, initial_mem_pages: int, max_mem_pages: int) -> bool {
	OPT_FLAGS :: "-debug "
	// OPT_FLAGS :: "-o:size -no-bounds-check -disable-assert -define:GPU_RELEASE=true "

	GPU_BACKEND_VAL :: #config(WEB_GPU_BACKEND, "WebGL")
	FORMAT :: "%s build %s -target:js_wasm32 -build-mode:obj -out:%s/%s.wasm.o " +
		"-define:RELEASE=true " +
		"-define:GPU_BACKEND=" + GPU_BACKEND_VAL + " " +
		OPT_FLAGS +
		"-extra-linker-flags:\"--export-table --initial-memory=%i --max-memory=%i\""

	return exec(ufmt.tprintf(FORMAT, ODIN_EXE, pkg_path, dst_dir, pkg_name,
		initial_mem_pages * WASM_PAGE_SIZE,
		max_mem_pages * WASM_PAGE_SIZE,
	))
}

link_emcc :: proc(dst_dir: string, pkg_name: string, initial_mem_pages: int, max_mem_pages: int) -> bool {
	obj_file := ufmt.tprintf("%s/%s.wasm.o", dst_dir, pkg_name)

	FLAGS :: "-sWASM_BIGINT -sASSERTIONS=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 " +
		"-sALLOW_MEMORY_GROWTH=1 " +
  "-sEXPORTED_FUNCTIONS=[_web_start,_step,_malloc,_free] " +
  "-sEXPORTED_RUNTIME_METHODS=[ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,lengthBytesUTF8,addFunction,removeFunction] " +
  "--shell-file %s/index_template.html "

	cmd := ufmt.tprintf("emcc -o %s/index.html %s %s",
		dst_dir,
		obj_file,
		ufmt.tprintf(FLAGS, dst_dir),
	)

	return exec(cmd)
}

generate_html :: proc(
	title:              string,
	pkg_name:           string,
	initial_mem_pages:  int,
	max_mem_pages:      int,
) -> string {
	html := HTML_TEMPLATE

	buf: [256]u8

	html, _ = strings.replace_all(html, "@pkg", pkg_name)
	html, _ = strings.replace_all(html, "@title", title)
	html, _ = strings.replace_all(html, "@initial_mem_pages", strconv.write_int(buf[:], i64(initial_mem_pages), 10))
	html, _ = strings.replace_all(html, "@max_mem_pages", strconv.write_int(buf[:], i64(max_mem_pages), 10))

	return html
}

HTML_TEMPLATE :: `
<!doctype html>
<html lang="en-us">
<head>
	<meta charset="utf-8">
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">

	<title>@title</title>
	<meta name="title" content="@title">
	<meta name="description" content="Ravn engine game compiled with Emscripten + WebGL">
	<meta name="viewport" content="width=device-width">

	<style>
		body {
			margin: 0px;
			overflow: hidden;
			background-color: black;
		}
		canvas.game_canvas {
			border: 0px none;
			background-color: black;
			padding-left: 0;
			padding-right: 0;
			margin-left: auto;
			margin-right: auto;
			display: block;
		}
	</style>
</head>
<body>
	<canvas class="game_canvas" id="canvas" oncontextmenu="event.preventDefault()" tabindex="-1" onmousedown="event.target.focus()" onkeydown="event.preventDefault()"></canvas>
	<script type="text/javascript" src="odin.js"></script>
	<script>
		var odinMemoryInterface = new odin.WasmMemoryInterface();
		odinMemoryInterface.setIntSize(4);
		var odinImports = odin.setupDefaultImports(odinMemoryInterface);

		// Stubs for missing foreign imports (stb_image, ravn_platform, ravn_audio).
		// These prevent the Emscripten-generated fallback stubs from calling abort().
		// TODO: replace with real implementations or compile the C libraries with emcc.
		var customImports = {
			// stb_image stubs
			stbi_load_from_memory: () => 0,
			stbi_image_free: () => {},
			stbi_failure_reason: () => 0,
			stbi_set_flip_vertically_on_load: () => {},

			// ravn_platform stubs (if ravn_platform.js is not loaded)
			init: () => {},
			set_pointer_lock: () => {},
			get_pointer_lock: () => 0,
			add_window_event_listener: () => 1,
			window_get_rect: (w, h) => { if(w) odinMemoryInterface.storeInt(w, 1280); if(h) odinMemoryInterface.storeInt(h, 720); },
			get_gamepad_state: () => 0,
			init_event_raw: () => {},

			// ravn_audio stubs (if ravn_webaudio.js is not loaded)
			push_buffer: () => {},
			get_num_queued_buffers: () => 0,
		};

		var Module = {
			instantiateWasm: (imports, successCallback) => {
				const newImports = {
					...odinImports,
					...customImports,
					...imports
				}

				return WebAssembly.instantiateStreaming(fetch("index.wasm"), newImports).then(function(output) {
					var e = output.instance.exports;
					odinMemoryInterface.setExports(e);
					odinMemoryInterface.setMemory(e.memory);
					return successCallback(output.instance);
				});
			},
			onRuntimeInitialized: () => {
				var e = wasmExports;

				// _web_start() calls rv.run_main_loop(), which on JS target does
				// init_state() and stores the module desc, then returns.
				e._web_start();

				function do_step() {
					if (e._step(0.016)) {
						window.requestAnimationFrame(do_step);
					} else {
						e._end();
					}
				}

				window.requestAnimationFrame(do_step);
			},
			print: (function() {
				var element = document.getElementById("output");
				if (element) element.value = '';
				return function(text) {
					if (arguments.length > 1) text = Array.prototype.slice.call(arguments).join(' ');
					console.log(text);
					if (element) {
					  element.value += text + "\n";
					  element.scrollTop = element.scrollHeight;
					}
				};
			})(),
			canvas: (function() {
				return document.getElementById("canvas");
			})()
		};
	</script>

	<!-- Emscripten injects its javascript here -->
	{{{ SCRIPT }}}
</body>
</html>
`
