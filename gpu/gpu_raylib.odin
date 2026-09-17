// ravn GPU backend: raylib (OpenGL / WebGL via Emscripten) for the builtin
// pull-model renderer. Select with -define:GPU_BACKEND=Raylib.
//
// This backend expects raylib to have initialized the window + GL context
// (platform_raylib.odin calls InitWindow). It uses rlgl (raylib's internal GL
// abstraction) directly for shader/buffer/texture management.
//
// Mapping (verified against ravn_graphics.odin / gpu_wgpu.odin / ravn.hlsli):
//   resources[0] -> sampler2D rv_instances (RGBA32F pull texture, 4 texels/item)
//   resources[1] -> sampler2D rv_verts     (RGBA32F pull texture, 2 texels/item)
//   resources[2] -> sampler2DArray rv_tex  (all sampled textures are GL arrays)
//   constants 0/1/2 -> loose uniforms rv_global_* / rv_view_proj... / rv_instance_offset
//   const_offsets[i] = ITEM INDEX * align16(item_size), skipped when item count == 1.
package ravn_gpu

import "core:fmt"
import "core:log"
import "core:strings"
import "base:runtime"

when BACKEND == BACKEND_RAYLIB {

RAYLIB_VERT_BUFFER_SLOT :: #config(GPU_RAYLIB_VERT_BUFFER_SLOT, 1) // renderer: inst buf @0, vbuf @1
RAYLIB_MAX_UNIFORMS_PER_SLOT :: #config(GPU_RAYLIB_MAX_UNIFORMS_PER_SLOT, 8)

RV_INSTANCES_UNIFORM :: "rv_instances"
RV_VERTS_UNIFORM     :: "rv_verts"
RV_TEX_UNIFORM       :: "rv_tex"

when ODIN_OS == .Windows {
    foreign import raylib_lib "raylib.lib"
    foreign import gl_lib "opengl32.lib"
} else when ODIN_OS == .Darwin {
    foreign import raylib_lib "system:raylib"
    foreign import gl_lib "system:OpenGL"
} else {
    foreign import raylib_lib "system:raylib" // web: libraylib.a via emcc -lraylib
    foreign import gl_lib "system:GL"         // web: emscripten's libGL (WebGL2)
}

Color :: struct { r, g, b, a: u8 }
Image :: struct { data: rawptr, width, height, mipmaps, format: i32 }
Texture :: struct { id: u32, width, height, mipmaps, format: i32 }
RenderTexture :: struct { id: u32, texture: Texture, depth: Texture }
Shader :: struct { id: u32, locs: [^]i32 }
Matrix :: struct { m: [16]f32 }

@(default_calling_convention="c")
foreign raylib_lib {
    BeginDrawing :: proc() ---
    EndDrawing :: proc() ---
    SetWindowSize :: proc(width, height: i32) ---
    LoadShaderFromMemory :: proc(vsCode, fsCode: cstring) -> Shader ---
    BeginTextureMode :: proc(target: RenderTexture) ---
    EndTextureMode :: proc() ---
    LoadRenderTexture :: proc(width, height: i32) -> RenderTexture ---
    UnloadRenderTexture :: proc(target: RenderTexture) ---
    GenImageColor :: proc(width, height: i32, color: Color) -> Image ---
    UnloadImage :: proc(image: Image) ---

    rlClearColor :: proc(r, g, b, a: u8) ---
    rlClearScreenBuffers :: proc() ---
    rlEnableShader :: proc(id: u32) ---
    rlDisableShader :: proc() ---
    rlGetLocationUniform :: proc(shaderId: u32, uniformName: cstring) -> i32 ---
    rlSetUniform :: proc(locIndex: i32, value: rawptr, uniformType: i32, count: i32) ---
    rlSetUniformMatrix :: proc(locIndex: i32, mat: Matrix) ---
    rlEnableDepthTest :: proc() ---
    rlDisableDepthTest :: proc() ---
    rlEnableDepthMask :: proc() ---
    rlDisableDepthMask :: proc() ---
    rlEnableBackfaceCulling :: proc() ---
    rlDisableBackfaceCulling :: proc() ---
    rlEnableWireMode :: proc() ---
    rlDisableWireMode :: proc() ---
    rlEnableColorBlend :: proc() ---
    rlDisableColorBlend :: proc() ---
    rlSetBlendFactorsSeparate :: proc(glSrcRGB, glDstRGB, glSrcAlpha, glDstAlpha, glEqRGB, glEqAlpha: i32) ---
    rlLoadVertexArray :: proc() -> u32 ---
    rlEnableVertexArray :: proc(vaoId: u32) -> bool ---
    rlDisableVertexArray :: proc() ---
    rlLoadVertexBuffer :: proc(data: rawptr, size: i32, dyn: bool) -> u32 ---
    rlLoadVertexBufferElement :: proc(data: rawptr, size: i32, dyn: bool) -> u32 ---
    rlUnloadVertexBuffer :: proc(id: u32) ---
    rlUpdateVertexBuffer :: proc(id: u32, data: rawptr, offset: i32, size: i32) ---
    rlSetVertexAttribute :: proc(index: u32, compSize: i32, type: i32, normalized: bool, stride: i32, offset: i32) ---
    rlEnableVertexAttribute :: proc(index: u32) ---
    rlDrawVertexArray :: proc(offset, count: i32) ---
    rlDrawVertexArrayElements :: proc(offset, count: i32, buffer: rawptr) ---
    rlDrawVertexArrayInstanced :: proc(offset, count, instances: i32) ---
    rlDrawVertexArrayElementsInstanced :: proc(offset, count: i32, buffer: rawptr, instances: i32) ---
    rlUpdateTexture :: proc(id: u32, offsetX, offsetY, width, height, format: i32, data: rawptr) ---
    rlUnloadTexture :: proc(id: u32) ---
    rlLoadTexture :: proc(data: rawptr, width, height, format, mipmaps: i32) -> u32 ---
    rlActiveTextureSlot :: proc(slot: i32) ---
    rlEnableTexture :: proc(id: u32) ---
}

@(default_calling_convention="c")
foreign gl_lib {
    glGenTextures :: proc(n: i32, textures: ^u32) ---
    glDeleteTextures :: proc(n: i32, textures: ^u32) ---
    glBindTexture :: proc(target: u32, texture: u32) ---
    glActiveTexture :: proc(tex_unit: u32) ---
    glTexParameteri :: proc(target, pname, param: i32) ---
    glTexImage3D :: proc(target, level, internalformat, width, height, depth, border, format, type_: i32, data: rawptr) ---
    glTexSubImage3D :: proc(target, level, xoffset, yoffset, zoffset, width, height, depth, format, type_: i32, data: rawptr) ---
    glPixelStorei :: proc(pname, param: i32) ---
    glDepthFunc :: proc(func: u32) ---
    glGetIntegerv :: proc(pname: u32, data: ^i32) ---
}

GL_TEXTURE_2D_ARRAY :: 0x8C1A
GL_TEXTURE_MIN_FILTER :: 0x2801
GL_TEXTURE_MAG_FILTER :: 0x2800
GL_TEXTURE_WRAP_S :: 0x2802
GL_TEXTURE_WRAP_T :: 0x2803
GL_TEXTURE_WRAP_R :: 0x8072
GL_NEAREST :: 0x2600
GL_LINEAR :: 0x2601
GL_REPEAT :: 0x2901
GL_CLAMP_TO_EDGE :: 0x812F
GL_UNPACK_ALIGNMENT :: 0x0CF5
GL_MAX_TEXTURE_SIZE :: 0x0D33
GL_RGBA8 :: 0x8058
GL_RGBA :: 0x1908
GL_TEXTURE0 :: 0x84C0
GL_UNSIGNED_BYTE :: 0x1401
GL_FLOAT :: 0x1406
GL_UNSIGNED_SHORT :: 0x1403
GL_NEVER :: 0x0200
GL_LESS :: 0x0201
GL_EQUAL :: 0x0202
GL_LEQUAL :: 0x0203
GL_GREATER :: 0x0204
GL_NOTEQUAL :: 0x0205
GL_GEQUAL :: 0x0206
GL_ALWAYS :: 0x0207
GL_FUNC_ADD :: 0x8006
GL_MIN :: 0x8007
GL_MAX :: 0x8008
GL_FUNC_SUBTRACT :: 0x800A
GL_FUNC_REVERSE_SUBTRACT :: 0x800B
GL_ZERO :: 0
GL_ONE :: 1
GL_SRC_COLOR :: 0x0300
GL_ONE_MINUS_SRC_COLOR :: 0x0301
GL_SRC_ALPHA :: 0x0302
GL_ONE_MINUS_SRC_ALPHA :: 0x0303
GL_DST_ALPHA :: 0x0304
GL_ONE_MINUS_DST_ALPHA :: 0x0305
GL_DST_COLOR :: 0x0306
GL_ONE_MINUS_DST_COLOR :: 0x0307
GL_SRC_ALPHA_SATURATE :: 0x0308

RL_SHADER_UNIFORM_FLOAT :: 0
RL_SHADER_UNIFORM_VEC2 :: 1
RL_SHADER_UNIFORM_VEC3 :: 2
RL_SHADER_UNIFORM_VEC4 :: 3
RL_SHADER_UNIFORM_INT :: 4
RL_SHADER_UNIFORM_IVEC2 :: 5
RL_SHADER_UNIFORM_UINT :: 8
RL_SHADER_UNIFORM_SAMPLER2D :: 12
RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 :: 4
RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 :: 7

Warn :: enum { front_cull, compute, multi_target, wire_mode, bad_format, u32_oob, lines }

_State :: struct {
    in_render_texture: bool,
    warned:            bit_set[Warn],
    pull_tex_w:        i32,
}

_Pipeline :: struct {
    shader_id: u32,
    vao:       u32,
    vbo:       u32,
    ebo:       u32,
    vb_h:      Resource_Handle,
    ib_h:      Resource_Handle,
    vb_ver:    u64,
    ib_ver:    u64,
    idx16:     []u16,
    pull:      [2]struct {
        loc:     i32,
        res_ver: u64,
    },
    tex_loc: i32,
    u_locs:  [CONSTANTS_BIND_SLOTS][RAYLIB_MAX_UNIFORMS_PER_SLOT]i32,
    u_lens:  [CONSTANTS_BIND_SLOTS]int,
}

_Compute_Pipeline :: struct { _: u8 }
_Shader :: struct { src: string }

_Resource :: struct {
    data:     []byte,
    stride:   i32,
    ver:      u64,
    gl_tex:   u32,
    pull_tex: u32,
    rt:       RenderTexture,
    as_u16:   bool,
}

_uniform_regs: [CONSTANTS_BIND_SLOTS][RAYLIB_MAX_UNIFORMS_PER_SLOT]Uniform_Entry
_uniform_lens: [CONSTANTS_BIND_SLOTS]int

Uniform_Type :: enum u8 { Float, Vec2, Vec3, Vec4, Int, IVec2, IVec3, IVec4, UInt, UVec2, Mat4 }

Uniform_Entry :: struct {
    name:   cstring,
    type:   Uniform_Type,
    offset: int,
    count:  int,
}

raylib_set_constant_layout :: proc(slot: int, entries: []Uniform_Entry) {
    assert(slot >= 0 && slot < CONSTANTS_BIND_SLOTS)
    n := min(len(entries), RAYLIB_MAX_UNIFORMS_PER_SLOT)
    copy(_uniform_regs[slot][:n], entries[:n])
    _uniform_lens[slot] = n
}

_alloc :: proc() -> runtime.Allocator { return _state != nil ? _state.allocator : context.allocator }

_warn_once :: proc(w: Warn, msg: string) {
    if w not_in _state.warned {
        _state.warned |= {w}
        log.warnf("gpu/raylib: %s", msg)
    }
}

_handle_valid :: proc "contextless" (h: Resource_Handle) -> bool { return h != Resource_Handle{} }

@(require_results)
_init :: proc(native_window: rawptr) -> bool {
    max_tex: i32 = 2048
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_tex)
    _state.pull_tex_w = max(max_tex, 1024)

    // Verified against data/ravn.hlsli (std140 layout).
    _uniform_regs[0] = {
        { name = "rv_global_time",       type = .Float, offset = 0,  count = 1 },
        { name = "rv_global_delta_time", type = .Float, offset = 4,  count = 1 },
        { name = "rv_global_frame",      type = .UInt,  offset = 8,  count = 1 },
        { name = "rv_global_resolution", type = .Int,   offset = 12, count = 2 },
        { name = "rv_global_rand_seed",  type = .UInt,  offset = 20, count = 1 },
        { name = "rv_global_param",      type = .UInt,  offset = 24, count = 4 },
        {},
        {},
    }
    _uniform_lens[0] = 6
    _uniform_regs[1] = {
        { name = "rv_view_proj",   type = .Mat4, offset = 0,  count = 1 },
        { name = "rv_cam_pos",     type = .Vec3, offset = 64, count = 1 },
        { name = "rv_layer_index", type = .Int,  offset = 76, count = 1 },
        {},
        {},
        {},
        {},
        {},
    }
    _uniform_lens[1] = 3
    _uniform_regs[2] = {
        { name = "rv_instance_offset", type = .UInt, offset = 0, count = 1 },
        {},
        {},
        {},
        {},
        {},
        {},
        {},
    }
    _uniform_lens[2] = 1

    _state.init_done = true
    return true
}

_shutdown :: proc() {}

@(require_results)
_begin_frame :: proc() -> bool { BeginDrawing(); return true }

_end_frame :: proc(sync: bool) { EndDrawing() }

@(require_results)
_update_swapchain :: proc(swapchain: ^_Resource, window: rawptr, size: [2]i32) -> (ok: bool) {
    if size.x > 0 && size.y > 0 { SetWindowSize(size.x, size.y) }
    return true
}

@(require_results)
_create_pipeline :: proc(name: string, desc: Pipeline_Desc) -> (result: _Pipeline, ok: bool) {
    vs, vs_ok := _get_shader(desc.vs)
    ps, ps_ok := _get_shader(desc.ps)
    if !vs_ok || !ps_ok || vs.kind != .Vertex || ps.kind != .Pixel {
        log.errorf("gpu/raylib: pipeline '%s' requires a vertex and a pixel shader", name)
        return
    }
    vs_cs := strings.clone_to_cstring(vs.src, _alloc())
    ps_cs := strings.clone_to_cstring(ps.src, _alloc())
    sh := LoadShaderFromMemory(vs_cs, ps_cs)
    if sh.id == 0 {
        log.errorf("gpu/raylib: shader compile/link failed for '%s' (see console)", name)
        return
    }
    result.shader_id = sh.id

    inst_cs := strings.clone_to_cstring(RV_INSTANCES_UNIFORM, _alloc())
    vert_cs := strings.clone_to_cstring(RV_VERTS_UNIFORM, _alloc())
    tex_cs := strings.clone_to_cstring(RV_TEX_UNIFORM, _alloc())
    result.pull[0].loc = rlGetLocationUniform(sh.id, inst_cs)
    result.pull[1].loc = rlGetLocationUniform(sh.id, vert_cs)
    result.tex_loc = rlGetLocationUniform(sh.id, tex_cs)

    for slot in 0..<CONSTANTS_BIND_SLOTS {
        n := min(_uniform_lens[slot], RAYLIB_MAX_UNIFORMS_PER_SLOT)
        result.u_lens[slot] = n
        for i in 0..<n {
            result.u_locs[slot][i] = rlGetLocationUniform(sh.id, _uniform_regs[slot][i].name)
        }
    }

    // VAO + VBO from the vertex buffer (attributes are unused by pull shaders but
    // keep the VAO valid; custom attribute shaders get the ravn Vertex layout).
    result.vb_h = _pick_vertex_buffer(desc)
    if _handle_valid(result.vb_h) {
        if vb, ok := _get_resource(result.vb_h); ok {
            result.vao = rlLoadVertexArray()
            if result.vao != 0 {
                rlEnableVertexArray(result.vao)
                result.vbo = rlLoadVertexBuffer(
                    len(vb.data) > 0 ? raw_data(vb.data) : nil,
                    i32(len(vb.data)),
                    vb.usage != .Immutable,
                )
                result.vb_ver = vb.ver
                s := i32(32) // ravn Vertex stride
                rlSetVertexAttribute(0, 3, GL_FLOAT, false, s, 0)
                rlEnableVertexAttribute(0)
                rlSetVertexAttribute(1, 2, GL_UNSIGNED_SHORT, true, s, 12)
                rlEnableVertexAttribute(1)
                rlSetVertexAttribute(2, 2, GL_UNSIGNED_BYTE, true, s, 16)
                rlEnableVertexAttribute(2)
                rlSetVertexAttribute(3, 4, GL_UNSIGNED_BYTE, true, s, 20)
                rlEnableVertexAttribute(3)
                rlDisableVertexArray()
            }
        }
    }

    if desc.index.format != .Invalid && _handle_valid(desc.index.resource) {
        result.ib_h = desc.index.resource
        if ib, ok := _get_resource(result.ib_h); ok {
            if desc.index.format == .U32 {
                ib.as_u16 = true
                if !_convert_indices(&result, ib) { return }
                result.ebo = rlLoadVertexBufferElement(
                    len(result.idx16) > 0 ? raw_data(result.idx16) : nil,
                    i32(len(result.idx16) * 2),
                    ib.usage != .Immutable,
                )
            } else {
                result.ebo = rlLoadVertexBufferElement(
                    len(ib.data) > 0 ? raw_data(ib.data) : nil,
                    i32(len(ib.data)),
                    ib.usage != .Immutable,
                )
            }
            result.ib_ver = ib.ver
        }
    }
    return result, true
}

@(require_results)
_create_compute_pipeline :: proc(name: string, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline, ok: bool) {
    _warn_once(.compute, "compute pipelines are not supported by the raylib backend")
    return
}

@(require_results)
_create_constants :: proc(name: string, item_size: i32, item_num: i32) -> (result: _Resource, ok: bool) {
    result.data = make([]byte, max(int(item_size) * int(item_num), 0), _alloc())
    result.ver = 1
    return result, true
}

@(require_results)
_create_shader :: proc(name: string, data: []u8, kind: Shader_Kind) -> (result: _Shader, ok: bool) {
    if kind == .Compute {
        _warn_once(.compute, "compute shaders are not supported by the raylib backend")
        return
    }
    // Inject the pull-texture width (shaders contain: const int RV_PULL_TEX_W = RV_PULL_TEX_W;)
    src, _ := strings.replace_all(string(data), "RV_PULL_TEX_W", fmt.aprintf("%d", _state.pull_tex_w, allocator = _alloc()))
    result.src = strings.clone(src, _alloc())
    return result, true
}

@(require_results)
_create_texture_2d :: proc(
    name: string, format: Texture_Format, size: [2]i32, usage: Usage,
    mips: i32, array_depth: i32, render_texture: bool, rw_resource: bool, data: []u8,
) -> (result: _Resource, ok: bool) {
    if rw_resource {
        _warn_once(.bad_format, "UAV textures are not supported")
        return
    }
    if mips > 1 { _warn_once(.bad_format, "mipmaps are not supported; only mip 0 is used") }

    if render_texture {
        // NOTE: GL_TEXTURE_2D — sampling an RT through the builtin sampler2DArray ps
        // is unsupported (snake_planet renders straight to the swapchain, so N/A there).
        result.rt = LoadRenderTexture(size.x, size.y)
        if result.rt.id == 0 { return }
        result.gl_tex = result.rt.texture.id
        return result, true
    }
    if format != .RGBA_U8_Norm {
        _warn_once(.bad_format, "only RGBA_U8_Norm textures are supported")
        return
    }
    // Everything sampled is a 2D array texture (depth >= 1) so the builtin
    // sampler2DArray pixel shader works for pooled and plain textures alike.
    glGenTextures(1, &result.gl_tex)
    glBindTexture(GL_TEXTURE_2D_ARRAY, result.gl_tex)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA8, size.x, size.y, max(array_depth, 1), 0, GL_RGBA, GL_UNSIGNED_BYTE,
        len(data) > 0 ? raw_data(data) : nil)
    _set_gl_sampler_params(nil)
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0)
    result.ver = 1
    return result, true
}

@(require_results)
_create_buffer :: proc(name: string, stride: i32, size: i32, usage: Usage, data: []u8) -> (result: _Resource, ok: bool) {
    result.data = make([]byte, max(int(size), 0), _alloc())
    copy(result.data, data)
    result.stride = stride
    result.ver = 1
    return result, true
}

@(require_results)
_create_index_buffer :: proc(name: string, size: i32, data: []u8, usage: Usage) -> (result: _Resource, ok: bool) {
    result.data = make([]byte, max(int(size), 0), _alloc())
    copy(result.data, data)
    result.ver = 1
    return result, true
}

_destroy_shader :: proc(shader: Shader_State) {
    delete(shader.src, _alloc())
}

_destroy_constants :: proc(constants: Resource_State) {
    if constants.data != nil { delete(constants.data, _alloc()) }
}

_destroy_resource :: proc(resource: Resource_State) {
    if resource.gl_tex != 0 && resource.rt.id == 0 {
        id := resource.gl_tex
        glDeleteTextures(1, &id)
    }
    if resource.pull_tex != 0 { rlUnloadTexture(resource.pull_tex) }
    if resource.rt.id != 0 { UnloadRenderTexture(resource.rt) }
    if resource.data != nil { delete(resource.data, _alloc()) }
}

_begin_pass :: proc(name: string, desc: Pass_Desc) {
    _state.in_render_texture = false
    c := desc.colors[0]
    if _handle_valid(c.resource) {
        if res, ok := _get_resource(c.resource); ok && res.kind == .Texture2D && res.rt.id != 0 {
            BeginTextureMode(res.rt)
            _state.in_render_texture = true
        }
    }
    for i in 1..<RENDER_TEXTURE_BIND_SLOTS {
        if _handle_valid(desc.colors[i].resource) {
            _warn_once(.multi_target, "multiple render targets are not supported; only colors[0] is used")
            break
        }
    }
    if c.clear_mode == .Clear {
        col := _to_color(c.clear_val)
        rlClearColor(col.r, col.g, col.b, col.a)
        rlClearScreenBuffers()
    }
}

_end_pass :: proc() {
    if _state.in_render_texture { EndTextureMode() }
    _state.in_render_texture = false
}

_begin_compute_pass :: proc(name: string) {}
_end_compute_pass :: proc() {}
_set_compute_pipeline :: proc(curr_pip: Compute_Pipeline_State, curr: Compute_Pipeline_Desc, prev: Compute_Pipeline_Desc) {}
_set_pipeline :: proc(curr_pip: Pipeline_State, curr: Pipeline_Desc, prev: Pipeline_Desc) {}

_update_constants :: proc(consts: ^Resource_State, data: []u8) {
    copy(consts.data, data)
    consts.ver += 1
}

_update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]u8) {
    pos := offset
    for b in buffers {
        if res.as_u16 {
            n := len(b) / 4
            for i in 0..<n {
                v := u32(b[i*4]) | u32(b[i*4+1]) << 8 | u32(b[i*4+2]) << 16 | u32(b[i*4+3]) << 24
                dst := pos + i * 2
                if dst + 2 <= len(res.data) {
                    res.data[dst + 0] = u8(v & 0xff)
                    res.data[dst + 1] = u8(v >> 8)
                }
            }
            pos += n * 2
        } else {
            if pos + len(b) <= len(res.data) { copy(res.data[pos:], b) }
            pos += len(b)
        }
    }
    res.ver += 1
}

_map_buffer :: proc(res: _Resource) -> []byte { return res.data }
_unmap_buffer :: proc(res: _Resource) {}

_update_texture_2d :: proc(res: Resource_State, data: []byte, slice: i32) {
    if len(data) == 0 { return }
    if res.rt.id != 0 {
        rlUpdateTexture(res.gl_tex, 0, 0, res.size.x, res.size.y, RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, raw_data(data))
        return
    }
    if res.gl_tex == 0 { return }
    glBindTexture(GL_TEXTURE_2D_ARRAY, res.gl_tex)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, slice, res.size.x, res.size.y, 1, GL_RGBA, GL_UNSIGNED_BYTE, raw_data(data))
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0)
}

_draw_non_indexed :: proc(vertex_num: u32, instance_num: u32, const_offsets: []u32) {
    pip, ok := _get_pipeline(_state.curr_pipeline)
    if !ok || pip.shader_id == 0 { return }
    if _state.curr_pipeline_desc.topo == .Lines {
        _warn_once(.lines, "line draws through pull shaders are not supported; skipped")
        return
    }
    if !_sync_pipeline(pip) { return }
    _apply_draw_state(&_state.curr_pipeline_desc)
    rlEnableShader(pip.shader_id)
    _push_constants(pip, const_offsets)
    _push_pull_and_textures(pip)
    if pip.vao != 0 && rlEnableVertexArray(pip.vao) {
        rlDrawVertexArrayInstanced(0, i32(vertex_num), i32(instance_num))
        rlDisableVertexArray()
    }
    rlDisableShader()
}

_draw_indexed :: proc(index_num: u32, instance_num: u32, index_offset: u32, const_offsets: []u32) {
    pip, ok := _get_pipeline(_state.curr_pipeline)
    if !ok || pip.shader_id == 0 { return }
    if _state.curr_pipeline_desc.topo == .Lines {
        _warn_once(.lines, "line draws through pull shaders are not supported; skipped")
        return
    }
    if !_sync_pipeline(pip) { return }
    _apply_draw_state(&_state.curr_pipeline_desc)
    rlEnableShader(pip.shader_id)
    _push_constants(pip, const_offsets)
    _push_pull_and_textures(pip)
    if pip.vao != 0 && rlEnableVertexArray(pip.vao) {
        off := i32(index_offset) + i32(_state.curr_pipeline_desc.index.offset) // elements (u16)
        if pip.ebo != 0 {
            rlDrawVertexArrayElementsInstanced(off, i32(index_num), nil, i32(instance_num))
        } else {
            rlDrawVertexArrayInstanced(off, i32(index_num), i32(instance_num))
        }
        rlDisableVertexArray()
    }
    rlDisableShader()
}

_dispatch_compute :: proc(size: [3]i32) {
    _warn_once(.compute, "compute dispatch is not supported by the raylib backend")
}

_pick_vertex_buffer :: proc(desc: Pipeline_Desc) -> Resource_Handle {
    when RAYLIB_VERT_BUFFER_SLOT >= 0 {
        h := desc.resources[RAYLIB_VERT_BUFFER_SLOT]
        if _handle_valid(h) { return h }
    }
    for h in desc.resources {
        if _handle_valid(h) {
            if res, ok := _get_resource(h); ok && res.kind == .Buffer { return h }
        }
    }
    return {}
}

_sync_pipeline :: proc(pip: ^Pipeline_State) -> bool {
    if _handle_valid(pip.vb_h) {
        vb, _ := _get_resource(pip.vb_h)
        if pip.vbo != 0 && pip.vb_ver != vb.ver {
            rlUpdateVertexBuffer(pip.vbo, raw_data(vb.data), 0, i32(len(vb.data)))
            pip.vb_ver = vb.ver
        }
    }
    if _handle_valid(pip.ib_h) {
        ib, _ := _get_resource(pip.ib_h)
        if pip.ib_ver != ib.ver {
            if ib.as_u16 {
                if !_convert_indices(&pip.native, ib) { return false }
                rlUpdateVertexBuffer(pip.ebo, raw_data(pip.idx16), 0, i32(len(pip.idx16) * 2))
            } else {
                rlUpdateVertexBuffer(pip.ebo, raw_data(ib.data), 0, i32(len(ib.data)))
            }
            pip.ib_ver = ib.ver
        }
    }
    // Pull textures for resources[0]/[1] (shared per-resource, RGBA32F, row-major).
    for slot in 0..<2 {
        if pip.pull[slot].loc < 0 { continue }
        desc := &_state.curr_pipeline_desc
        h := desc.resources[slot]
        if !_handle_valid(h) { continue }
        res, _ := _get_resource(h)
        if res.pull_tex != 0 && pip.pull[slot].res_ver == res.ver { continue }
        texels := len(res.data) / 16 // 64B item = 4 texels, 32B item = 2 texels
        w := _state.pull_tex_w
        hgt := max((texels + int(w) - 1) / int(w), 1)
        if res.pull_tex != 0 { rlUnloadTexture(res.pull_tex) }
        res.pull_tex = rlLoadTexture(
            len(res.data) > 0 ? raw_data(res.data) : nil,
            w, i32(hgt), RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32, 1,
        )
        pip.pull[slot].res_ver = res.ver
    }
    return true
}

_push_pull_and_textures :: proc(pip: ^Pipeline_State) {
    desc := &_state.curr_pipeline_desc
    for slot in 0..<2 {
        if pip.pull[slot].loc < 0 { continue }
        h := desc.resources[slot]
        if !_handle_valid(h) { continue }
        res, _ := _get_resource(h)
        if res.pull_tex == 0 { continue }
        unit := i32(slot)
        rlActiveTextureSlot(unit)
        rlEnableTexture(res.pull_tex)
        rlSetUniform(pip.pull[slot].loc, &unit, RL_SHADER_UNIFORM_SAMPLER2D, 1)
    }
    if pip.tex_loc >= 0 && _handle_valid(desc.resources[2]) {
        if res, ok := _get_resource(desc.resources[2]); ok && res.gl_tex != 0 {
            unit := i32(2)
            glActiveTexture(GL_TEXTURE0 + u32(unit))
            glBindTexture(GL_TEXTURE_2D_ARRAY, res.gl_tex)
            _set_gl_sampler_params(desc)
            rlSetUniform(pip.tex_loc, &unit, RL_SHADER_UNIFORM_SAMPLER2D, 1)
        }
    }
    rlActiveTextureSlot(0)
}

_push_constants :: proc(pip: ^Pipeline_State, const_offsets: []u32) {
    desc := &_state.curr_pipeline_desc
    for slot in 0..<CONSTANTS_BIND_SLOTS {
        h := desc.constants[slot]
        if !_handle_valid(h) { continue }
        res, ok := _get_resource(h)
        if !ok { continue }
        base := 0
        item_size := (int(res.size.x) + 15) / 16 * 16
        if res.size.y > 1 && slot < len(const_offsets) {
            base = int(const_offsets[slot]) * item_size // item index (see gpu_wgpu._bind_constants_items)
        }
        n := min(pip.u_lens[slot], _uniform_lens[slot])
        for i in 0..<n {
            e := _uniform_regs[slot][i]
            loc := pip.u_locs[slot][i]
            if loc < 0 { continue }
            off := base + e.offset
            if e.type == .Mat4 {
                if off + 64 <= len(res.data) {
                    m: Matrix
                    copy(([^]u8)(&m.m[0])[:64], res.data[off:off+64])
                    rlSetUniformMatrix(loc, m)
                }
            } else if off < len(res.data) {
                rlSetUniform(loc, raw_data(res.data[off:]), _rl_uniform_type(e.type), i32(max(e.count, 1)))
            }
        }
    }
}

_apply_draw_state :: proc(desc: ^Pipeline_Desc) {
    b := desc.blends[0]
    default_blend := b == Blend_Desc{}
    if default_blend {
        rlDisableColorBlend()
    } else {
        rlEnableColorBlend()
        rlSetBlendFactorsSeparate(
            _gl_blend_factor(b.src_color), _gl_blend_factor(b.dst_color),
            _gl_blend_factor(b.src_alpha), _gl_blend_factor(b.dst_alpha),
            _gl_blend_op(b.op_color), _gl_blend_op(b.op_alpha),
        )
    }
    depth_on := !(desc.depth_comparison == .Always && !desc.depth_write)
    if depth_on {
        rlEnableDepthTest()
        glDepthFunc(_gl_compare(desc.depth_comparison))
    } else {
        rlDisableDepthTest()
    }
    if desc.depth_write { rlEnableDepthMask() } else { rlDisableDepthMask() }

    switch desc.cull {
    case .Back: rlEnableBackfaceCulling()
    case .Front:
        _warn_once(.front_cull, "front-face culling is not supported by rlgl; culling disabled")
        rlDisableBackfaceCulling()
    case .None, .Invalid: rlDisableBackfaceCulling()
    }

    if desc.fill == .Wireframe {
        _warn_once(.wire_mode, "wireframe fill is desktop-GL only; ignored on WebGL")
        rlEnableWireMode()
    } else {
        rlDisableWireMode()
    }
}

_set_gl_sampler_params :: proc(desc: ^Pipeline_Desc) {
    filter: i32 = GL_NEAREST
    wrap: i32 = GL_REPEAT
    if desc != nil {
        if desc.samplers[0].filter != .Unfiltered { filter = GL_LINEAR }
        if desc.samplers[0].bounds[0] == .Clamp || desc.samplers[0].bounds[1] == .Clamp { wrap = GL_CLAMP_TO_EDGE }
    }
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, filter)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, filter)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, wrap)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, wrap)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_R, wrap)
}

_convert_indices :: proc(p: ^_Pipeline, ib: ^Resource_State) -> bool {
    count := len(ib.data) / 4
    if len(p.idx16) != count {
        if p.idx16 != nil { delete(p.idx16, _alloc()) }
        p.idx16 = make([]u16, count, _alloc())
    }
    for i in 0..<count {
        b := ib.data[i * 4:]
        v := u32(b[0]) | u32(b[1]) << 8 | u32(b[2]) << 16 | u32(b[3]) << 24
        if v > 0xffff {
            _warn_once(.u32_oob, "U32 index buffer has values > 65535; 16-bit indices required")
            return false
        }
        p.idx16[i] = u16(v)
    }
    return true
}

_rl_uniform_type :: proc "contextless" (t: Uniform_Type) -> i32 {
    #partial switch t {
    case .Float: return RL_SHADER_UNIFORM_FLOAT
    case .Vec2:  return RL_SHADER_UNIFORM_VEC2
    case .Vec3:  return RL_SHADER_UNIFORM_VEC3
    case .Vec4:  return RL_SHADER_UNIFORM_VEC4
    case .Int:   return RL_SHADER_UNIFORM_INT
    case .IVec2: return RL_SHADER_UNIFORM_IVEC2
    case .UInt:  return RL_SHADER_UNIFORM_UINT
    case .Mat4:  return -1
    }
    return -1
}

_gl_compare :: proc "contextless" (op: Comparison_Op) -> u32 {
    #partial switch op {
    case .Never:         return GL_NEVER
    case .Less:          return GL_LESS
    case .Equal:         return GL_EQUAL
    case .Less_Equal:    return GL_LEQUAL
    case .Greater:       return GL_GREATER
    case .Not_Equal:     return GL_NOTEQUAL
    case .Greater_Equal: return GL_GEQUAL
    case .Always:        return GL_ALWAYS
    }
    return GL_LESS
}

_gl_blend_factor :: proc "contextless" (f: Blend_Factor) -> i32 {
    #partial switch f {
    case .Zero:                return GL_ZERO
    case .One:                 return GL_ONE
    case .Src_Color:           return GL_SRC_COLOR
    case .One_Minus_Src_Color: return GL_ONE_MINUS_SRC_COLOR
    case .Src_Alpha:           return GL_SRC_ALPHA
    case .One_Minus_Src_Alpha: return GL_ONE_MINUS_SRC_ALPHA
    case .Dst_Color:           return GL_DST_COLOR
    case .One_Minus_Dst_Color: return GL_ONE_MINUS_DST_COLOR
    case .Dst_Alpha:           return GL_DST_ALPHA
    case .One_Minus_Dst_Alpha: return GL_ONE_MINUS_DST_ALPHA
    case .Src_Alpha_Sat:       return GL_SRC_ALPHA_SATURATE
    }
    return GL_ONE
}

_gl_blend_op :: proc "contextless" (op: Blend_Op) -> i32 {
    #partial switch op {
    case .Add:         return GL_FUNC_ADD
    case .Sub:         return GL_FUNC_SUBTRACT
    case .Reverse_Sub: return GL_FUNC_REVERSE_SUBTRACT
    case .Min:         return GL_MIN
    case .Max:         return GL_MAX
    }
    return GL_FUNC_ADD
}

_to_u8 :: proc "contextless" (x: f32) -> u8 {
    v := x * 255.0 + 0.5
    if v < 0 { v = 0 }
    if v > 255 { v = 255 }
    return u8(v)
}
_to_color :: proc "contextless" (v: [4]f32) -> Color {
    return Color{ _to_u8(v.x), _to_u8(v.y), _to_u8(v.z), _to_u8(v.w) }
}

} // when BACKEND == BACKEND_RAYLIB
