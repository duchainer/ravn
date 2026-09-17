// ravn Platform backend: raylib.
// Replaces SDL/Windows/JS backends for window, input, and time.
// Use with -define:PLATFORM_BACKEND=Raylib.
//
// On desktop (Linux/Windows/Mac), links against libraylib + OpenGL.
// On web (js_wasm32), links against libraylib.a built for web + Emscripten GLFW/WebGL.
//
// NOTE: raylib's EndDrawing (called by gpu_raylib.odin) polls input events internally.
// This backend queries raylib's key state in _poll_window_events, which works because
// raylib's IsKeyPressed/IsKeyReleased reflect the transition since the last PollInputEvents.
#+vet explicit-allocators shadowing unused
package ravn_platform

import "core:time"
import "base:runtime"
import "../base"

_ :: runtime
_ :: base

when BACKEND == BACKEND_RAYLIB {

when ODIN_OS == .Windows {
    foreign import raylib_lib "raylib.lib"
} else {
    foreign import raylib_lib "system:raylib"
}

// Minimal raylib types and foreign declarations needed for the platform layer.
// (The GPU backend declares its own rlgl subset.)
@(default_calling_convention="c")
foreign raylib_lib {
    InitWindow              :: proc(width, height: i32, title: cstring) ---
    CloseWindow             :: proc() ---
    WindowShouldClose       :: proc() -> bool ---
    SetWindowTitle          :: proc(title: cstring) ---
    SetWindowSize           :: proc(width, height: i32) ---
    SetWindowPosition       :: proc(x, y: i32) ---
    HideWindow              :: proc() ---
    ShowWindow              :: proc() ---
    IsWindowMinimized       :: proc() -> bool ---
    IsWindowFocused         :: proc() -> bool ---
    GetScreenWidth          :: proc() -> i32 ---
    GetScreenHeight         :: proc() -> i32 ---
    GetMonitorWidth         :: proc(monitor: i32) -> i32 ---
    GetMonitorHeight        :: proc(monitor: i32) -> i32 ---
    GetMousePosition        :: proc() -> Vector2 ---
    GetMouseDelta           :: proc() -> Vector2 ---
    GetMouseWheelMoveV      :: proc() -> Vector2 ---
    SetMousePosition        :: proc(x, y: i32) ---
    HideCursor              :: proc() ---
    ShowCursor              :: proc() ---
    DisableCursor           :: proc() ---
    EnableCursor            :: proc() ---
    IsKeyPressed            :: proc(key: i32) -> bool ---
    IsKeyReleased           :: proc(key: i32) -> bool ---
    IsKeyDown               :: proc(key: i32) -> bool ---
    IsMouseButtonPressed    :: proc(button: i32) -> bool ---
    IsMouseButtonReleased   :: proc(button: i32) -> bool ---
    IsMouseButtonDown       :: proc(button: i32) -> bool ---
    GetTime                 :: proc() -> f64 ---
    SetTargetFPS            :: proc(fps: i32) ---
    SetExitKey              :: proc(key: i32) ---
    IsGamepadAvailable      :: proc(gamepad: i32) -> bool ---
    GetGamepadAxisMovement  :: proc(gamepad, axis: i32) -> f32 ---
    IsGamepadButtonDown     :: proc(gamepad, button: i32) -> bool ---
    WaitTime                :: proc(ms: f64) ---
}

Vector2 :: struct { x, y: f32 }

_State :: struct {
    window_created:  bool,
    keys_down:       [512]bool,   // track previous frame key state
    mouse_buttons:   bit_set[Mouse_Button],
    poll_ns:         u64,         // time of last input scan (to detect new frame)
}

_File_Handle :: struct {
    path: string,
}

_File_Watcher :: struct { _: u8 }
_Directory_Iter :: struct { _: u8 }

_Thread :: struct {
    _: rawptr,
}

_Window :: struct {
    _: u8,
}

_Module :: struct {
    lib: rawptr,
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: General
//

_init :: proc() {
    SetTargetFPS(0) // ravn manages frame timing.
    // Window is NOT created here; _create_window does it lazily.
}

_shutdown :: proc() {
    if _state.window_created {
        CloseWindow()
        _state.window_created = false
    }
}



_exit_process :: proc(code: int) -> ! {
    runtime.trap()
}

_register_default_exception_handler :: proc() {}

@(require_results)
_memory_protect :: proc(ptr: rawptr, num_bytes: int, protect: Memory_Protection) -> bool {
    return false
}

@(require_results)
_clipboard_set :: proc(data: string) -> bool {
    return false
}

@(require_results)
_clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) {
    return "", false
}

@(require_results)
_get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) {
    if !IsGamepadAvailable(i32(index)) {
        return {}, false
    }
    g := i32(index)

    result.axes = {
        .Left_Trigger   = clamp(GetGamepadAxisMovement(g, 4), 0, 1),
        .Right_Trigger  = clamp(GetGamepadAxisMovement(g, 5), 0, 1),
        .Left_Thumb_X   = GetGamepadAxisMovement(g, 0),
        .Left_Thumb_Y   = GetGamepadAxisMovement(g, 1),
        .Right_Thumb_X  = GetGamepadAxisMovement(g, 2),
        .Right_Thumb_Y  = GetGamepadAxisMovement(g, 3),
    }

    if IsGamepadButtonDown(g, 1)  do result.buttons += {.DPad_Up}
    if IsGamepadButtonDown(g, 3)  do result.buttons += {.DPad_Down}
    if IsGamepadButtonDown(g, 0)  do result.buttons += {.DPad_Left}
    if IsGamepadButtonDown(g, 2)  do result.buttons += {.DPad_Right}
    if IsGamepadButtonDown(g, 15) do result.buttons += {.Start}
    if IsGamepadButtonDown(g, 14) do result.buttons += {.Back}
    if IsGamepadButtonDown(g, 10) do result.buttons += {.Left_Thumb}
    if IsGamepadButtonDown(g, 11) do result.buttons += {.Right_Thumb}
    if IsGamepadButtonDown(g, 8)  do result.buttons += {.Left_Shoulder}
    if IsGamepadButtonDown(g, 9)  do result.buttons += {.Right_Shoulder}
    if IsGamepadButtonDown(g, 7)  do result.buttons += {.A}
    if IsGamepadButtonDown(g, 5)  do result.buttons += {.B}
    if IsGamepadButtonDown(g, 6)  do result.buttons += {.X}
    if IsGamepadButtonDown(g, 4)  do result.buttons += {.Y}

    return result, true
}

@(require_results)
_set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool {
    return false
}

@(require_results)
_get_user_data_dir :: proc(allocator := context.allocator) -> string {
    return "."
}

_set_mouse_relative :: proc(window: Window, relative: bool) {
    if relative {
        DisableCursor()
    } else {
        EnableCursor()
    }
}

_set_mouse_visible :: proc(visible: bool) {
    // NOTE: DisableCursor already hides the cursor; don't fight it.
    if _state.mouse_relative {
        return
    }
    if visible {
        ShowCursor()
    } else {
        HideCursor()
    }
}



@(require_results)
_load_module :: proc(path: string) -> (result: Module, ok: bool) {
    return {}, false
}

_unload_module :: proc(module: Module) {}

@(require_results)
_get_module_symbol_address :: proc(module: Module, cstr: cstring) -> (result: rawptr) {
    return nil
}

_sleep_ms :: proc(#any_int ms: int) {
    time.sleep(time.Millisecond * time.Duration(ms))
}

@(require_results)
_get_time_ns :: proc() -> u64 {
    return u64(GetTime() * 1e9)
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Thread
//

@(require_results)
_create_thread :: proc(procedure: Thread_Proc, name: string) -> (result: Thread) {
    // TODO: implement with core:thread when API is confirmed
    return {}
}

_join_thread :: proc(t: Thread) {
    // TODO
}

@(require_results)
_get_current_thread_id :: proc() -> u64 {
    return 0
}

_refresh_cpu_core_info :: proc() {}

_pin_thread_to_cpu_core :: proc(t: Thread, core_index: int) -> bool {
    return false
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Window
//

@(require_results)
_create_window :: proc(name: string, style: Window_Style, rect: Rect, high_dpi: bool) -> Window {
    if !_state.window_created {
        w := rect.size.x if rect.size.x > 0 else 1280
        h := rect.size.y if rect.size.y > 0 else 720
        title := clone_to_cstring(name, context.temp_allocator)
        InitWindow(w, h, title)
        SetExitKey(0) // Disable ESC auto-close; ravn handles shutdown.
        _state.window_created = true
    } else {
        _set_window_title({}, name)
        if rect.size.x > 0 && rect.size.y > 0 {
            SetWindowSize(rect.size.x, rect.size.y)
        }
    }
    if style == .Borderless {
        HideWindow()
        ShowWindow() // raylib borderless is tricky; best-effort
    }
    return Window{}
}

_destroy_window :: proc(window: Window) {
    // CloseWindow is called in _shutdown.
}

@(require_results)
_get_window_dpi_scale :: proc(window: Window) -> f32 {
    return 1.0
}

_set_window_title :: proc(window: Window, name: string) {
    SetWindowTitle(clone_to_cstring(name, context.temp_allocator))
}

_set_window_style :: proc(window: Window, style: Window_Style) {
    switch style {
    case .Regular:
        // nothing
    case .Borderless:
        // raylib does not support dynamic borderless toggle well.
    }
}

_set_window_pos :: proc(window: Window, pos: [2]i32) {
    SetWindowPosition(pos.x, pos.y)
}

_set_window_size :: proc(window: Window, size: [2]i32) {
    SetWindowSize(size.x, size.y)
}

@(require_results)
_get_window_rect :: proc(window: Window) -> (result: Rect) {
    result.size.x = GetScreenWidth()
    result.size.y = GetScreenHeight()
    return result
}

_set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
    SetMousePosition(pos.x, pos.y)
}

@(require_results)
_is_window_minimized :: proc(window: Window) -> bool {
    return IsWindowMinimized()
}

@(require_results)
_is_window_focused :: proc(window: Window) -> bool {
    return IsWindowFocused()
}

@(require_results)
_get_native_window_ptr :: proc(window: Window) -> rawptr {
    return nil // raylib does not expose the native window handle easily.
}

@(require_results)
_poll_window_events :: proc(window: Window) -> (ok: bool) {
    // Raylib input state is updated at the end of the previous frame (inside EndDrawing).
    // We must only scan once per ravn frame, otherwise we generate duplicate events.
    now := _get_time_ns()
    if _state.poll_ns > 0 && now - _state.poll_ns < 100_000 {
        return false
    }
    _state.poll_ns = now

    if WindowShouldClose() {
        _event_queue_push(Event_Exit{})
        ok = true
    }

    // Keys: transition tracking (pressed / released)
    for keycode in 32..=348 {
        down := IsKeyDown(i32(keycode))
        idx := keycode
        if down && !_state.keys_down[idx] {
            if k := _raylib_keycode_to_ravn(i32(keycode)); k != .Invalid {
                _event_queue_push(Event_Key{key = k, pressed = true})
                ok = true
            }
        } else if !down && _state.keys_down[idx] {
            if k := _raylib_keycode_to_ravn(i32(keycode)); k != .Invalid {
                _event_queue_push(Event_Key{key = k, pressed = false})
                ok = true
            }
        }
        _state.keys_down[idx] = down
    }

    // Mouse buttons
    for btn in 0..<5 {
        b := _raylib_mouse_button(i32(btn))
        down := IsMouseButtonDown(i32(btn))
        was_down := b in _state.mouse_buttons
        if down && !was_down {
            _event_queue_push(Event_Mouse_Button{button = b, pressed = true})
            ok = true
            _state.mouse_buttons += {b}
        } else if !down && was_down {
            _event_queue_push(Event_Mouse_Button{button = b, pressed = false})
            ok = true
            _state.mouse_buttons -= {b}
        }
    }

    // Mouse movement
    pos := GetMousePosition()
    delta := GetMouseDelta()
    if delta.x != 0 || delta.y != 0 || _state.mouse_pos.x != i32(pos.x) || _state.mouse_pos.y != i32(pos.y) {
        _event_queue_push(Event_Mouse{
            move = {i32(delta.x), i32(delta.y)},
            pos  = {i32(pos.x), i32(pos.y)},
        })
        ok = true
    }
    _state.mouse_pos = {i32(pos.x), i32(pos.y)}

    // Scroll
    scroll := GetMouseWheelMoveV()
    if scroll.x != 0 || scroll.y != 0 {
        _event_queue_push(Event_Scroll{delta = {scroll.x, scroll.y}})
        ok = true
    }

    return ok
}

@(require_results)
_get_main_monitor_rect :: proc() -> Rect {
    return {
        min = {0, 0},
        size = {GetMonitorWidth(0), GetMonitorHeight(0)},
    }
}

_raylib_mouse_button :: proc(b: i32) -> Mouse_Button {
    switch b {
    case 0: return .Left
    case 1: return .Right
    case 2: return .Middle
    case 3: return .Extra_1
    case 4: return .Extra_2
    }
    return .Left
}

_raylib_keycode_to_ravn :: proc(keycode: i32) -> Key {
    switch keycode {
    case 32: return .Space
    case 39: return .Apostrophe
    case 44: return .Comma
    case 45: return .Minus
    case 46: return .Period
    case 47: return .Slash
    case 48: return .Num0
    case 49: return .Num1
    case 50: return .Num2
    case 51: return .Num3
    case 52: return .Num4
    case 53: return .Num5
    case 54: return .Num6
    case 55: return .Num7
    case 56: return .Num8
    case 57: return .Num9
    case 59: return .Semicolon
    case 61: return .Equal
    case 65: return .A
    case 66: return .B
    case 67: return .C
    case 68: return .D
    case 69: return .E
    case 70: return .F
    case 71: return .G
    case 72: return .H
    case 73: return .I
    case 74: return .J
    case 75: return .K
    case 76: return .L
    case 77: return .M
    case 78: return .N
    case 79: return .O
    case 80: return .P
    case 81: return .Q
    case 82: return .R
    case 83: return .S
    case 84: return .T
    case 85: return .U
    case 86: return .V
    case 87: return .W
    case 88: return .X
    case 89: return .Y
    case 90: return .Z
    case 91: return .Left_Bracket
    case 92: return .Backslash
    case 93: return .Right_Bracket
    case 96: return .Backtick
    case 256: return .Escape
    case 257: return .Enter
    case 258: return .Tab
    case 259: return .Backspace
    case 260: return .Insert
    case 261: return .Delete
    case 262: return .Right
    case 263: return .Left
    case 264: return .Down
    case 265: return .Up
    case 266: return .Page_Up
    case 267: return .Page_Down
    case 268: return .Home
    case 269: return .End
    case 280: return .Capslock
    case 281: return .Scroll_Lock
    case 282: return .Num_Lock
    case 283: return .Print_Screen
    case 284: return .Pause
    case 290: return .F1
    case 291: return .F2
    case 292: return .F3
    case 293: return .F4
    case 294: return .F5
    case 295: return .F6
    case 296: return .F7
    case 297: return .F8
    case 298: return .F9
    case 299: return .F10
    case 300: return .F11
    case 301: return .F12
    case 302: return .F13
    case 303: return .F14
    case 304: return .F15
    case 305: return .F16
    case 306: return .F17
    case 307: return .F18
    case 308: return .F19
    case 309: return .F20
    case 310: return .F21
    case 311: return .F22
    case 312: return .F23
    case 313: return .F24
    case 314: return .F25
    case 320: return .Keypad_0
    case 321: return .Keypad_1
    case 322: return .Keypad_2
    case 323: return .Keypad_3
    case 324: return .Keypad_4
    case 325: return .Keypad_5
    case 326: return .Keypad_6
    case 327: return .Keypad_7
    case 328: return .Keypad_8
    case 329: return .Keypad_9
    case 330: return .Keypad_Decimal
    case 331: return .Keypad_Divide
    case 332: return .Keypad_Multiply
    case 333: return .Keypad_Subtract
    case 334: return .Keypad_Add
    case 335: return .Keypad_Enter
    case 336: return .Keypad_Equal
    case 340: return .Left_Shift
    case 341: return .Left_Control
    case 342: return .Left_Alt
    case 343: return .Left_Super
    case 344: return .Right_Shift
    case 345: return .Right_Control
    case 346: return .Right_Alt
    case 347: return .Right_Super
    case 348: return .Menu
    }
    return .Invalid
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: File IO
//

@(require_results)
_open_file :: proc(path: string) -> (File_Handle, bool) {
    return {}, false
}

_close_file :: proc(handle: File_Handle) {}

@(require_results)
_get_last_write_time :: proc(handle: File_Handle) -> (u64, bool) {
    return 0, false
}



@(require_results)
_clone_file :: proc(path: string, new_path: string, fail_if_exists := true) -> bool {
    return false
}

@(require_results)
_iter_directory :: proc(iter: ^Directory_Iter, pattern: string, allocator := context.temp_allocator) -> (result: string, ok: bool) {
    return {}, false
}

@(require_results)
_init_file_watcher :: proc(watcher: ^File_Watcher, path: string, recursive := false) -> bool {
    return false
}

@(require_results)
_poll_file_watcher :: proc(watcher: ^File_Watcher) -> []string {
    return nil
}

_destroy_file_watcher :: proc(watcher: ^File_Watcher) {}

@(require_results)
_file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) {
    return "", false
}

} // when BACKEND == BACKEND_RAYLIB
