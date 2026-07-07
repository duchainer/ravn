package ravn_orbit_camera_example

import "core:math"
import "core:math/linalg"
import rv "../../."
import "../../platform"

state: ^State

State :: struct {
	target:   [3]f32,
	distance: f32,
	cam_ang:  [3]f32,
	fov:      f32,
}

@export
_module_desc := rv.Module_Desc {
	state_size = size_of(State),
	init       = _init,
	shutdown   = _shutdown,
	update     = _update,
}

main :: proc() {
	rv.run_main_loop(_module_desc)
}

_init :: proc() {
	state = new(State)
	platform.set_window_title(rv.get_window(), "Orbit Camera")

	state.target = {0, 0, 0}
	state.distance = 10
	state.cam_ang = {0.3, 0, 0}
	state.fov = rv.deg(60)
}

_shutdown :: proc() {
	free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr {
	if hot_state != nil {
		state = cast(^State)hot_state
	}

	if rv.get_key_pressed(.Escape) {
		rv.request_shutdown()
	}

	// Orbit on left mouse drag
	if rv.get_mouse_down(.Left) {
		mouse_delta := rv.get_mouse_delta()
		state.cam_ang.yx += mouse_delta.xy * 0.005
		state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)
	}

	// Zoom with scroll wheel
	scroll := rv.get_scroll_delta().y
	if scroll != 0 {
		state.distance *= math.pow(0.9, scroll)
		state.distance = clamp(state.distance, 1.0, 100.0)
	}

	// Pan target on right mouse drag
	cam_rot := rv.euler_rot(state.cam_ang)
	mat := linalg.matrix3_from_quaternion_f32(cam_rot)

	if rv.get_mouse_down(.Right) {
		mouse_delta := rv.get_mouse_delta()
		pan_speed := state.distance * 0.002
		state.target -= mat[0] * mouse_delta.x * pan_speed
		state.target += mat[1] * mouse_delta.y * pan_speed
	}

	// Camera looks at target from a distance
	forward := mat[2]
	cam_pos := state.target - forward * state.distance

	// Update camera for 3D layer
	rv.update_draw_layer(0, rv.make_perspective_3d_camera(rv.get_screen_size(), cam_pos, cam_rot, state.fov))
	rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

	// Draw 3D scene
	rv.set_draw_depth(.Depth)
	rv.set_draw_texture(rv.get_builtin_texture(.Default))

	// Central sphere
	rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), state.target, scale = 0.5, col = rv.ORANGE)

	// Ring of cubes
	for i in 0 ..< 8 {
		angle := f32(i) * math.PI * 2.0 / 8.0
		pos := [3]f32{math.cos(angle) * 3, 0, math.sin(angle) * 3}
		col := i % 2 == 0 ? rv.CYAN : rv.PINK
		rv.draw_mesh(rv.get_builtin_mesh(.Cube), pos, scale = 0.4, col = col)
	}

	// Floor grid of small cubes
	for x in -3 ..= 3 {
		for z in -3 ..= 3 {
			pos := [3]f32{f32(x) * 2, -1, f32(z) * 2}
			col := (abs(x) + abs(z)) % 2 == 0 ? rv.DARK_GRAY : rv.GRAY
			rv.draw_mesh(rv.get_builtin_mesh(.Cube), pos, scale = 0.2, col = col)
		}
	}

	// UI layer
	rv.set_draw_layer(1)
	rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))

	rv.draw_text("Orbit Camera Example", {14, 14, 0.1}, scale = 3)
	rv.draw_text("Left drag: orbit  |  Right drag: pan  |  Scroll: zoom  |  Esc: quit", {14, 50, 0.1}, scale = 2)

	rv.submit_layers()
	rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, [3]f32{0.05, 0.05, 0.1}, true)
	rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

	return state
}
