// WebGL backend for ravn-engine, intended to be used with Emscripten.
// Emscripten translates OpenGL ES 3.0 / WebGL 2.0 calls automatically.
//
// This is a skeleton implementation. The actual rendering pipeline must be
// filled in with either:
//   (a) raw WebGL calls via Emscripten's EM_JS / EM_ASM bindings, or
//   (b) an OpenGL ES 3.0 mapping using Odin's vendor:OpenGL package.
//
// The dummy backend (gpu_dummy.odin) was used as the structural template.
package ravn_gpu

import "../base"

when BACKEND == BACKEND_WEBGL {

	_State :: struct {
		// TODO: WebGL context / canvas handle
		ctx: rawptr,
		// TODO: surface dimensions
		width: i32,
		height: i32,
		// TODO: command queue / state cache
	}

	_Pipeline :: struct {
		// TODO: WebGL shader program, VAO, FBO state
		program: rawptr,
	}

	_Compute_Pipeline :: struct {
		// WebGL 2.0 does not support compute shaders. This backend
		// will panic if compute is used.
	}

	_Shader :: struct {
		// TODO: compiled shader object (vertex or fragment)
		shader: rawptr,
	}

	_Resource :: struct #raw_union {
		// TODO: buffer, texture, or framebuffer
		buf:    rawptr,
		using _: struct {
			tex:        rawptr,
			tex_view:   rawptr,
		},
	}

	_Sampler :: struct {
		// TODO: WebGL sampler state
		smp: rawptr,
	}



	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: General
	//

	@(require_results)
	_init :: proc(native_window: rawptr) -> bool {
		base.log_info("GPU: Initializing WebGL backend (skeleton)")
		// TODO: create WebGL 2.0 context on the canvas
		// TODO: set up initial state (viewport, default FBO, etc.)
		_state.init_done = true
		return true
	}

	_shutdown :: proc() {
		// TODO: release WebGL context, delete remaining resources
	}

	@(require_results)
	_begin_frame :: proc() -> bool {
		// TODO: bind default framebuffer, clear if needed
		return true
	}

	_end_frame :: proc(sync: bool) {
		// TODO: flush command queue, swap buffers (Emscripten handles the swap)
	}



	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Create
	//

	@(require_results)
	_update_swapchain :: proc(swapchain: ^_Resource, window: rawptr, size: [2]i32) -> (ok: bool) {
		_state.width = size.x
		_state.height = size.y
		// TODO: resize canvas / WebGL viewport
		return true
	}

	@(require_results)
	_create_pipeline :: proc(name: string, desc: Pipeline_Desc) -> (result: _Pipeline, ok: bool) {
		// TODO: compile & link shader program, configure VAO / blend state
		base.log_info("GPU: Creating pipeline '%s' (WebGL skeleton)", name)
		return {}, true
	}

	@(require_results)
	_create_compute_pipeline :: proc(name: string, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline, ok: bool) {
		// WebGL 2.0 does not support compute. Return empty.
		base.log_err("GPU: Compute pipelines are not supported by the WebGL backend")
		return {}, false
	}

	@(require_results)
	_create_constants :: proc(name: string, item_size: i32, item_num: i32) -> (result: _Resource, ok: bool) {
		// TODO: create uniform buffer object (UBO) or use uniform arrays
		return {}, true
	}

	@(require_results)
	_create_shader :: proc(name: string, data: []u8, kind: Shader_Kind) -> (result: _Shader, ok: bool) {
		// TODO: compile shader source (GLSL ES) with glCompileShader
		base.log_info("GPU: Creating shader '%s' (WebGL skeleton)", name)
		return {}, true
	}

	@(require_results)
	_create_texture_2d :: proc(
		name: string,
		format: Texture_Format,
		size: [2]i32,
		usage: Usage,
		mips: i32,
		array_depth: i32,
		render_texture: bool,
		rw_resource: bool,
		data: []byte,
	) -> (result: _Resource, ok: bool) {
		// TODO: glTexImage2D / glTexStorage2D
		return {}, true
	}

	@(require_results)
	_create_buffer :: proc(
		name: string,
		stride: i32,
		size: i32,
		usage: Usage,
		data: []u8,
	) -> (result: _Resource, ok: bool) {
		// TODO: glGenBuffers + glBufferData
		return {}, true
	}

	@(require_results)
	_create_index_buffer :: proc(
		name: string,
		size: i32,
		data: []u8,
		usage: Usage,
	) -> (result: _Resource, ok: bool) {
		// TODO: glGenBuffers + glBufferData with GL_ELEMENT_ARRAY_BUFFER
		return {}, true
	}



	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Destroy
	//

	_destroy_shader :: proc(shader: Shader_State) {
		// TODO: glDeleteShader
	}

	_destroy_resource :: proc(resource: Resource_State) {
		// TODO: glDeleteBuffers / glDeleteTextures / glDeleteFramebuffers
	}


	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Actions
	//

	_begin_pass :: proc(name: string, desc: Pass_Desc) {
		// TODO: bind framebuffer (FBO), set clear values, clear
	}

	_end_pass :: proc() {
		// TODO: unbind FBO if rendering to texture
	}

	_begin_compute_pass :: proc(name: string) {
		// Not supported in WebGL 2.0
		panic("GPU: Compute passes are not supported by the WebGL backend")
	}

	_end_compute_pass :: proc() {
		// Not supported in WebGL 2.0
	}

	_set_pipeline :: proc(curr_pip: Pipeline_State, curr: Pipeline_Desc, prev: Pipeline_Desc) {
		// TODO: glUseProgram, set vertex attrib pointers, bind index buffer
	}

	_set_compute_pipeline :: proc(curr_pip: Compute_Pipeline_State, curr: Compute_Pipeline_Desc, prev: Compute_Pipeline_Desc) {
		// Not supported in WebGL 2.0
		panic("GPU: Compute pipelines are not supported by the WebGL backend")
	}

	_update_constants :: proc(consts: ^Resource_State, data: []u8) {
		// TODO: glBufferSubData for UBO, or glUniform* for legacy uniforms
	}

	_update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]u8) {
		// TODO: glBufferSubData
	}

	_update_texture_2d :: proc(res: Resource_State, data: []byte, slice: i32) {
		// TODO: glTexSubImage2D
	}

	_draw_non_indexed :: proc(vertex_num: u32, instance_num: u32, const_offsets: []u32) {
		// TODO: glDrawArrays (instancing via ANGLE_instanced_arrays or WebGL 2 glDrawArraysInstanced)
	}

	_draw_indexed :: proc(index_num: u32, instance_num: u32, index_offset: u32, const_offsets: []u32) {
		// TODO: glDrawElements (instancing via glDrawElementsInstanced in WebGL 2)
	}

	_dispatch_compute :: proc(size: [3]i32) {
		// Not supported in WebGL 2.0
		panic("GPU: Compute dispatch is not supported by the WebGL backend")
	}

}
