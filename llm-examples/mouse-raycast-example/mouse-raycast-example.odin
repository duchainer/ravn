package mouse_raycast_example

import "core:fmt"
import "core:math"
import "core:math/linalg"

import rv "../.."
import "../../platform"
import coll "../../collision"

state: ^State

State :: struct {
	cam_pos: [3]f32,
	cam_ang: [3]f32,
	cam_vel: [3]f32,
}

@export _module_desc := rv.Module_Desc {
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
	state.cam_pos = {0, 2, -8}
	state.cam_ang = {0.3, 0, 0}

	platform.set_mouse_relative(rv.get_window(), true)
	platform.set_mouse_visible(false)

	coll.init(new(coll.State))
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

	delta := rv.get_delta_time()

	// ---- flycam --------------------------------------------------
	move: [3]f32
	if rv.get_key_down(.D) do move.x += 1
	if rv.get_key_down(.A) do move.x -= 1
	if rv.get_key_down(.W) do move.z += 1
	if rv.get_key_down(.S) do move.z -= 1
	if rv.get_key_down(.E) do move.y += 1
	if rv.get_key_down(.Q) do move.y -= 1

	state.cam_ang.xy += rv.get_mouse_delta().yx * 0.005
	state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)

	cam_rot := rv.euler_rot(state.cam_ang)
	mat := linalg.matrix3_from_quaternion_f32(cam_rot)

	speed: f32 = 4.0
	if rv.get_key_down(.Left_Shift) do speed *= 4

	state.cam_pos += mat[0] * move.x * delta * speed
	state.cam_pos += mat[2] * move.z * delta * speed
	state.cam_pos.y += move.y * delta * speed

	// ---- camera --------------------------------------------------
	camera := rv.make_perspective_3d_camera(
		rv.get_screen_size(),
		state.cam_pos,
		cam_rot,
		rv.deg(degrees = 90),
	)

	// ---- register demo shapes ------------------------------------
	coll.add_sphere_shape({ 0, 1,  0}, 1.0)
	coll.add_box_shape  ({-3, 0.5, 2}, {1, 0.5, 1})
	coll.add_box_shape  ({ 3, 0.5, 2}, {1, 0.5, 1})

	// ---- mouse raycast -------------------------------------------
	mouse_ray := rv.screen_to_world_ray(rv.get_mouse_pos(), camera)

	// 1. Intersect with ground plane (y = 0)
	ground_hit: [3]f32
	ground_ok := false
	if abs(mouse_ray.y) > 0.001 {
		t := -camera.pos.y / mouse_ray.y
		if t > 0 {
			ground_hit = camera.pos + mouse_ray * t
			ground_ok = true
		}
	}

	// 2. Sweep ray against collision shapes
	shape_sweep, shape_hit := coll.sweep_point(camera.pos, mouse_ray, range = 100)
	shape_hit_pos := camera.pos + mouse_ray * shape_sweep.t

	// ---- draw 3D -------------------------------------------------
	rv.update_draw_layer(0, camera)
	rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

	rv.set_draw_depth(.Depth)
	rv.set_draw_texture(rv.get_builtin_texture(.Default))

	// Draw demo shapes
	cube := rv.get_builtin_mesh(.Cube)
	sphere := rv.get_builtin_mesh(.UV_Sphere_1)
	rv.draw_mesh(sphere, pos = {0, 1, 0}, scale = 1.0, col = {0.8, 0.3, 0.3, 1})
	rv.draw_mesh(cube,   pos = {-3, 0.5, 2}, scale = {1, 0.5, 1}, col = {0.3, 0.3, 0.8, 1})
	rv.draw_mesh(cube,   pos = { 3, 0.5, 2}, scale = {1, 0.5, 1}, col = {0.3, 0.3, 0.8, 1})

	// Draw mouse ray
	rv.draw_line(camera.pos, camera.pos + mouse_ray * 50, col = [4]f32{0, 1, 0, 0.5})

	// Draw ground hit marker
	if ground_ok {
		rv.draw_line_circle(ground_hit + {0, 0.01, 0}, rad = {0.2, 0.2}, col = {1, 0, 0, 0.8}, segments = 16)
	}

	// Draw shape hit marker
	if shape_hit {
		rv.draw_mesh(sphere, pos = shape_hit_pos, scale = 0.15, col = {0, 1, 1, 1})
		rv.draw_line(shape_hit_pos, shape_hit_pos + shape_sweep.normal * 0.5, col = [4]f32{0, 1, 1, 1})
	}

	// ---- draw UI -------------------------------------------------
	rv.set_draw_layer(1)
	rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))

	y: f32 = 14
	line_h :: f32(18)
	scale :: f32(2)

	rv.draw_text("Mouse Raycast Example", {14, y, 0.1}, scale = scale)
	y += line_h
	rv.draw_text("WASD + mouse look  |  ESC to quit", {14, y, 0.1}, scale = scale - 0.5)
	y += line_h * 1.5

	if ground_ok {
		rv.draw_text(fmt.tprintf("Ground hit: %.2f, %.2f, %.2f", ground_hit.x, ground_hit.y, ground_hit.z),
			{14, y, 0.1}, scale = scale - 0.5, col = {1, 0.5, 0.5, 1})
	} else {
		rv.draw_text("Ground hit: none", {14, y, 0.1}, scale = scale - 0.5, col = {0.5, 0.5, 0.5, 1})
	}
	y += line_h

	if shape_hit {
		rv.draw_text(fmt.tprintf("Shape hit:  %.2f, %.2f, %.2f  (shape=%d)",
			shape_hit_pos.x, shape_hit_pos.y, shape_hit_pos.z, shape_sweep.shape),
			{14, y, 0.1}, scale = scale - 0.5, col = {0.5, 1, 1, 1})
	} else {
		rv.draw_text("Shape hit: none", {14, y, 0.1}, scale = scale - 0.5, col = {0.5, 0.5, 0.5, 1})
	}

	rv.submit_layers()
	rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, nil, true)
	rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

	return state
}
