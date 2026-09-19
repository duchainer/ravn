#+build ignore
// #+build !js
#+vet explicit-allocators shadowing unused
package ravn_platform

import "core:os"
import "base:runtime"

when BACKEND == BACKEND_RAYLIB {

@(require_results)
_get_commandline_args :: proc(allocator: runtime.Allocator) -> []string {
    return os.args
}

@(require_results)
_run_shell_command :: proc(command: string) -> int {
    state, _, _, err := os.process_exec(
        os.Process_Desc{
            command = {"sh", "-c", command},
        },
        allocator = context.temp_allocator,
    )
    if err != nil {
        return -1
    }
    return state.exit_code
}

@(require_results)
_set_current_directory :: proc(path: string) -> bool {
    return os.set_working_directory(path) != nil
}

@(require_results)
_get_executable_path :: proc(allocator := context.temp_allocator) -> string {
    return os.args[0] if len(os.args) > 0 else ""
}

@(require_results)
_delete_file :: proc(path: string) -> bool {
    return (os.remove_all(path) == nil)
}

@(require_results)
_read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    return os.read_entire_file(path, allocator)
}

@(require_results)
_write_file_by_path :: proc(path: string, data: []u8) -> bool {
    return os.write_entire_file(path, data) == nil
}

@(require_results)
_file_exists :: proc(path: string) -> bool {
    return os.exists(path)
}

@(require_results)
_create_directory :: proc(path: string) -> bool {
    return os.make_directory(path) == nil
}

@(require_results)
_is_file :: proc(path: string) -> bool {
    return os.is_file(path)
}

@(require_results)
_is_directory :: proc(path: string) -> bool {
    return os.is_dir(path)
}

} // when BACKEND == BACKEND_RAYLIB
