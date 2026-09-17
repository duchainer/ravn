#+build js
#+vet explicit-allocators shadowing unused
package ravn_platform

import "base:runtime"

when BACKEND == BACKEND_RAYLIB {

@(require_results)
_get_commandline_args :: proc(allocator: runtime.Allocator) -> []string {
    return nil
}

@(require_results)
_run_shell_command :: proc(command: string) -> int {
    return -1
}

@(require_results)
_set_current_directory :: proc(path: string) -> bool {
    return false
}

@(require_results)
_get_executable_path :: proc(allocator := context.temp_allocator) -> string {
    return ""
}

@(require_results)
_delete_file :: proc(path: string) -> bool {
    return false
}

@(require_results)
_read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    return nil, false
}

@(require_results)
_write_file_by_path :: proc(path: string, data: []u8) -> bool {
    return false
}

@(require_results)
_file_exists :: proc(path: string) -> bool {
    return false
}

@(require_results)
_create_directory :: proc(path: string) -> bool {
    return false
}

@(require_results)
_is_file :: proc(path: string) -> bool {
    return false
}

@(require_results)
_is_directory :: proc(path: string) -> bool {
    return false
}

} // when BACKEND == BACKEND_RAYLIB
