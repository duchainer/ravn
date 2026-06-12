#+private=file
package ravn_build

import "../platform"
import "../base"
import "../base/ufmt"

import "core:path/filepath"
import "core:strings"
import "core:strconv"
import "base:runtime"

when ODIN_OS == .Windows {
    DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
    DLL_EXT :: ".dylib"
} else {
    DLL_EXT :: ".so"
}

Hotreload_Module :: struct {
    mod:        platform.Module,
    desc:       base.Module_Desc,
    callback:   proc "contextless" (rawptr, base.Module_Desc) -> rawptr,
}

Hotreload_File :: struct {
    path:       string,
    index:      int,
}

exec :: proc(str: string) -> bool {
    res := platform.run_shell_command(str)
    if 0 != res {
        base.log_err("Error: Command '%s' failed with exit code %i", str, res)
        return false
    }
    return true
}

compile_hot :: proc(pkg: string, pkg_name: string, index: int) {
    path := ufmt.tprintf("%s%i" + DLL_EXT, pkg_name, index)
    assert(!platform.file_exists(path), ufmt.tprintf("!platform.file_exists(\"%s\")", path))
    exec(ufmt.tprintf("%s build %s -out:%s -debug -build-mode:dll", ODIN_EXE, pkg, path))
}

clean_hot :: proc(pkg: string) {
    when ODIN_OS == .Windows {
        remove_all(ufmt.tprintf("%s*.dll", pkg))
        remove_all(ufmt.tprintf("%s*.pdb", pkg))
        remove_all(ufmt.tprintf("%s*.exp", pkg))
        remove_all(ufmt.tprintf("%s*.lib", pkg))
        remove_all(ufmt.tprintf("%s*.rdi", pkg))
    } else when ODIN_OS == .Linux {
        remove_all(ufmt.tprintf("./%s*.so", pkg)) // linux dll
    }
}

hotreload_find_latest_dll :: proc(pkg_name: string) -> (result: Hotreload_File, ok: bool) {
    when ODIN_OS == .Windows {
        pattern := ufmt.tprintf("%s*" + DLL_EXT, pkg_name)
    } else when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        pattern := ufmt.tprintf("./%s*" + DLL_EXT, pkg_name)
    }
    max_index: int = -1

    iter: platform.Directory_Iter
    for path in platform.iter_directory(&iter, pattern, context.temp_allocator) {
        base_filename := filepath.base(path)
        if !strings.starts_with(base_filename, pkg_name) {
            continue
        }

        if !strings.has_suffix(path, DLL_EXT) {
            continue
        }

        index_str := base_filename[len(pkg_name) : len(base_filename) - len(DLL_EXT)]

        digits: int
        index, _ := strconv.parse_int(index_str, 10, &digits)

        if digits == 0 {
            continue
        }

        if index > max_index {
            max_index = index
            result = {
                path    = path,
                index   = index,
            }
            ok = true
        }
    }

    return result, ok
}

hotreload_run :: proc(pkg: string, pkg_path: string) -> bool {
    initial, initial_ok := hotreload_find_latest_dll(pkg)

    if !initial_ok {
        base.log_err("Hotreload Error: Couldn't find inital DLL for package:", pkg)
        return false
    }

    base.log_info("Hotreload: Loading initial module %s ...", initial.path)

    module, module_ok := load_hotreload_module(initial.path)

    if !module_ok {
        base.log_err("Hotreload Error: Failed to load initial DLL")
        return false
    }

    modules_to_unload: [dynamic]platform.Module
    append(&modules_to_unload, module.mod)

    curr_index := initial.index

    prev_data: rawptr

    watcher: platform.File_Watcher
    platform.init_file_watcher(&watcher, pkg_path)

    any_changes := false

    for {
        assert(module.callback != nil)

        prev_data = module.callback(prev_data, module.desc)

        if prev_data == nil {
            break
        }

        prev_any_changes := any_changes

        changes := platform.poll_file_watcher(&watcher)
        for change in changes {
            // base.log_info("Hotreload: file changed:", change)
            if strings.ends_with(change, ".odin") {
                any_changes = true
            }
        }

        if prev_any_changes && any_changes {
            any_changes = false

            when ODIN_OS == .Linux {
                base.log_info("HOTRELOADAUTO RECOMPILING")
                compile_hot(pkg_path, pkg, curr_index + 1)
            }
        }

        new_file, new_ok := hotreload_find_latest_dll(pkg)
        if !new_ok {
            continue
        }

        if new_file.index > curr_index {
            // NOTE: this is expected to fail a few times while the module is compiling.
            new_module, new_module_ok := load_hotreload_module(new_file.path)
            if !new_module_ok {
                platform.sleep_ms(50)
                continue
            }

            base.log_info("Hotreload: Loaded %s", new_file.path)

            if new_module.desc.state_size != module.desc.state_size {
                base.log_err(
                    "Hotreload: State size mismatch (new %i vs old %i). You cannot change the State struct layout during hotreload.",
                    new_module.desc.state_size, module.desc.state_size)
                return false
            }

            append(&modules_to_unload, new_module.mod)

            module = new_module
            curr_index = new_file.index
        }

        free_all(context.temp_allocator)
    }

    for lib, i in modules_to_unload {
        platform.unload_module(lib)
    }

    base.log_info("Hotreload: finished OK")

    return true
}

load_hotreload_module :: proc(path: string) -> (result: Hotreload_Module, ok: bool) {
    module, module_ok := platform.load_module(path)
    if !module_ok {
        base.log_err("Hotreload: Failed to load library:", path)
        return {}, false
    }

    module_desc_ptr := cast(^base.Module_Desc)platform.get_module_symbol_address(module, "_module_desc")

    if module_desc_ptr == nil {
        base.log_err("Hotreload: Failed to find _module_desc data")
        return {}, false
    }

    result.desc = module_desc_ptr^

    result.callback = auto_cast(platform.get_module_symbol_address(module, "_module_hot_step"))

    if result.callback == nil {
        base.log_err("Hotreload: Failed to find the _module_hot_step proc")
        return {}, false
    }

    return result, true
}
