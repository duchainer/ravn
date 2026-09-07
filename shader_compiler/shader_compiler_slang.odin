#+vet explicit-allocators shadowing style
#+build !js
package ravn_shader_compiler

import "../base"
import "../platform"
import "slang"
import "base:runtime"

when ODIN_OS == .Windows {
    SLANG_DYNLIB_PATH :: "slang.dll"
} else when ODIN_OS == .Linux || ODIN_OS == .Darwin {
    SLANG_DYNLIB_PATH :: "./libslang.so"
} else {
    SLANG_DYNLIB_PATH :: ""
}

_Slang_State :: struct {
    using vtable:   slang.Global_VTable,
    module:         platform.Module,
    global_session: ^slang.IGlobalSession,
}

_slang_init :: proc(state: ^_Slang_State) -> bool {
    if SLANG_DYNLIB_PATH == "" {
        return false
    }

    module_ok: bool
    state.module, module_ok = platform.load_module(SLANG_DYNLIB_PATH)
    if !module_ok {
        base.log_err("Failed to load " + SLANG_DYNLIB_PATH + ". Ensure it's in your working directory to compile shaders.")
        return false
    }

    state.vtable = {
        createBlob                           = auto_cast _load_sym(state, "slang_createBlob") or_return,
        loadModuleFromSource                 = auto_cast _load_sym(state, "slang_loadModuleFromSource") or_return,
        loadModuleFromIRBlob                 = auto_cast _load_sym(state, "slang_loadModuleFromIRBlob") or_return,
        loadModuleInfoFromIRBlob             = auto_cast _load_sym(state, "slang_loadModuleInfoFromIRBlob") or_return,
        createGlobalSession                  = auto_cast _load_sym(state, "slang_createGlobalSession") or_return,
        createGlobalSession2                 = auto_cast _load_sym(state, "slang_createGlobalSession2") or_return,
        createGlobalSessionWithoutCoreModule = auto_cast _load_sym(state, "slang_createGlobalSessionWithoutCoreModule") or_return,
        shutdown                             = auto_cast _load_sym(state, "slang_shutdown") or_return,
    }

    if !_slang_check(state.createGlobalSession(slang.API_VERSION, &state.global_session)) {
        return false
    }

    base.log_info("Successfully loaded slang compiler")

    return true

    _load_sym :: proc(state: ^_Slang_State, name: cstring) -> (rawptr, bool) {
        result := platform.get_module_symbol_address(state.module, name)
        if result == nil {
            base.log_err("Failed to find symbol '%s' in slang.dll", name)
            return nil, false
        }
        return result, true
    }
}

_compile_slang_wgsl :: proc(
    state:          ^State,
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {
    return _compile_slang_target(state, name, source, opts, .WGSL, "wgsl_1_0")
}

_compile_slang_glsl_es :: proc(
    state:          ^State,
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {
    return _compile_slang_target(state, name, source, opts, .GLSL, "glsl_es_310")
}

_compile_slang_target :: proc(
    state:          ^State,
    name:           string,
    source:         string,
    opts:           Options,
    target_format:  slang.CompileTarget,
    profile_name:   cstring,
) -> (result: []byte, ok: bool) {
    assert(state.slang.global_session != nil)

    target_desc := slang.TargetDesc{
        structureSize = size_of(slang.TargetDesc),
        format = target_format,
        profile = state.slang.global_session->findProfile(profile_name),
    }

    options := [?]slang.CompilerOptionEntry {
        { .Stage, {.Int, i32(slang.Stage.VERTEX), 0, nil, nil}},
        { .Optimization, {.Int, i32(opts.release ? slang.OptimizationLevel.HIGH : slang.OptimizationLevel.NONE), 0, nil, nil}},
    }

    file_system: _Slang_IFileSystem = {
        ifilesystem = {
            vtable = &slang.IFileSystem_VTable{
                icastable_vtable = {
                    iunknown_vtable = {
                        queryinterface = _slang_ifilesystem_queryinterface,
                        addRef = _slang_ifilesystem_addref,
                        release = _slang_ifilesystem_release,
                    },
                    castAs = _slang_ifilesystem_castas,
                },
                loadFile = _slang_ifilesystem_loadfile,
            },
        },
        ctx = context,
        opts = opts,
        state = state,
    }

    session_desc := slang.SessionDesc{
        structureSize = size_of(slang.SessionDesc),
        targetCount = 1,
        targets = &target_desc,
        defaultMatrixLayoutMode = .COLUMN_MAJOR,
        compilerOptionEntries = &options[0],
        compilerOptionEntryCount = len(options),
        fileSystem = &file_system,
    }

    session: ^slang.ISession
    _slang_check(state.slang.global_session->createSession(session_desc, &session))

    cname := clone_to_cstring(name, context.temp_allocator)

    source_blob := state.slang.createBlob(raw_data(source), len(source))
    diag: ^slang.IBlob
    module := session->loadModuleFromSource(cname, cname, source_blob, &diag)

    _slang_diag(diag)
    if module == nil {
        return nil, false
    }

    entry_point_name: cstring
    switch opts.stage {
    case .Invalid:
        assert(false)
        return {}, false
    case .Vertex: entry_point_name = "vs_main"
    case .Pixel:  entry_point_name = "ps_main"
    case .Compute:entry_point_name = "cs_main"
    }

    entry_point: ^slang.IEntryPoint
    _slang_check_diag(module->findAndCheckEntryPoint(entry_point_name, _slang_stage(opts.stage), &entry_point, &diag), diag)

    components := [?]^slang.IComponentType{module, entry_point}
    composite: ^slang.IComponentType
    _slang_check_diag(session->createCompositeComponentType(&components[0], len(components), &composite, &diag), diag)

    if composite == nil {
        return nil, false
    }

    code_blob: ^slang.IBlob
    _slang_check_diag(composite->getEntryPointCode(0, 0, &code_blob, &diag), diag)
    if code_blob == nil {
        return nil, false
    }

    return _slang_blob_buf(code_blob), true
}

_slang_check :: proc(res: slang.Result, expr := #caller_expression(res), loc := #caller_location) -> bool {
    if res != .OK {
        base.log_err("Slang Error: %v (%x)", res, transmute(u32)res, loc = loc)
        assert(false, message = expr, loc = loc)
        return false
    }
    return true
}

_slang_check_diag :: proc(res: slang.Result, diag: ^slang.IBlob, expr := #caller_expression(res), loc := #caller_location) -> bool {
    if res != .OK {
        base.log_err("Slang Error: %v (%x):\n%s", res, transmute(u32)res, _slang_blob_str(diag), loc = loc)
        assert(false, message = expr, loc = loc)
        return false
    }
    return true
}

_slang_diag :: proc(diag: ^slang.IBlob, loc := #caller_location) -> bool {
    if diag != nil {
        base.log_err("Slang Error: %s", _slang_blob_str(diag), loc = loc)
        return false
    }
    return true
}

_slang_blob_buf :: proc(blob: ^slang.IBlob) -> []byte {
    return (cast([^]byte)blob->getBufferPointer())[:blob->getBufferSize()]
}

_slang_blob_str :: proc(blob: ^slang.IBlob) -> string {
    return transmute(string)_slang_blob_buf(blob)
}

_slang_stage :: proc(stage: Stage) -> slang.Stage {
    switch stage {
    case: fallthrough
    case .Invalid: return .NONE
    case .Vertex: return .VERTEX
    case .Pixel: return .PIXEL
    case .Compute: return .COMPUTE
    }
}

_Slang_IFileSystem :: struct #all_or_none {
    #subtype ifilesystem: slang.IFileSystem,
    ctx:    runtime.Context,
    opts:   Options,
    state:  ^State,
}

_slang_ifilesystem_loadfile :: proc "system" (
    _this:      ^slang.IFileSystem,
    path:       cstring,
    outBlob:    ^^slang.IBlob,
) -> slang.Result {
    assert_contextless(_this != nil)

    this := cast(^_Slang_IFileSystem)_this
    context = this.ctx

    assert(path != nil)
    assert(outBlob != nil)

    // base.log_info("INCLUDE %s", path)

    if this.opts.include_proc == nil {
        return .E_NOT_FOUND
    }

    result, ok := this.opts.include_proc(
        path = string(path),
        user = this.opts.user,
    )

    if !ok {
        return .E_NOT_FOUND
    }

    outBlob^ = this.state.slang.createBlob(raw_data(result), len(result))
    return .OK
}

_slang_ifilesystem_castas :: proc "system" (this: ^slang.ICastable, #by_ptr guid: slang.UUID) -> rawptr {
    switch guid {
    case slang.IUnknown_UUID, slang.ICastable_UUID, slang.IFileSystem_UUID:
        return rawptr(this)
    }
    return nil
}

_slang_ifilesystem_queryinterface :: proc "system" (this: ^slang.IUnknown, #by_ptr uuid: slang.UUID, outObject: ^rawptr) -> slang.Result {
    switch uuid {
    case slang.IUnknown_UUID, slang.ICastable_UUID, slang.IFileSystem_UUID:
        outObject^ = this
        return .OK
    }
    return .FAIL
}

_slang_ifilesystem_addref :: proc "system" (this: ^slang.IUnknown) -> u32 {
    return 1
}

_slang_ifilesystem_release :: proc "system" (this: ^slang.IUnknown) -> u32 {
    return 1
}
