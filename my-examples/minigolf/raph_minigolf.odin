package raph_minigolf

import "core:math"
import "core:math/linalg"
// import "core:math/rand"

import rv "../../."
// import audio "../../audio"
import platform "../../platform"

// import ufmt "../../base/ufmt"
import base "../../base/"
_ :: base

Ball :: struct {
    pos : [3]f32,
    vel : [3]f32,
}

State :: struct {
	cam:                  struct {
		pos: [3]f32,
		rot: [3]f32,
		fov: f32,
        target: [3]f32,
        distance: f32,
	},

    ball : Ball,
}

state : ^State

_init :: proc(){
    state = new(State)
	platform.set_window_title(rv.get_window(), "Raph Minigolf")
	// platform.set_mouse_relative(rv.get_window(), true)

	state.cam.pos = {0, 0, -10}
	state.cam.rot = {0.3, 0, 0}
	state.cam.fov = rv.deg(degrees = 90)
	state.cam.target = {0, 0, 0}
	state.cam.distance = 10

    state.ball.pos = {10,10,10}
    state.ball.vel = {0,0,0}
}

_shutdown :: proc(){
    free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr{
    rv.perf_scope()

    // Only called on hot-reload
    if hot_state != nil{
        state = cast(^State)hot_state
    }

    if rv.get_key_pressed(.Escape){
        rv.request_shutdown()
        return &state
    }

    cam_rot_quat: quaternion128
    delta := rv.get_delta_time()
    {
        rv.perf_scope("_update_game")

        {
            rv.perf_scope("_update_camera")
            move: [3]f32
            if rv.get_key_down(.D) do move.x += 1
            if rv.get_key_down(.A) do move.x -= 1
            if rv.get_key_down(.W) do move.z += 1
            if rv.get_key_down(.S) do move.z -= 1
            if rv.get_key_down(.E) do move.y += 1
            if rv.get_key_down(.Q) do move.y -= 1

            // Camera Orbit on left mouse drag
            if rv.get_mouse_down(.Left){
                state.cam.rot.xy += rv.get_mouse_delta().yx * 0.005
                state.cam.rot.x = clamp(state.cam.rot.x, -math.PI * 0.49, math.PI * 0.49)
            }

            cam_rot_quat = rv.euler_rot(state.cam.rot)
            mat := linalg.matrix3_from_quaternion_f32(cam_rot_quat)

            forward := mat[2]
            state.cam.pos = state.cam.target - forward * state.cam.distance
        }
    }

    rv.update_draw_layer(
        0,
        rv.make_perspective_3d_camera(
            rv.get_screen_size(),
            state.cam.pos,
            cam_rot_quat,
            state.cam.fov
        )
    )
    rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

    rv.set_draw_depth(.Depth)

    // 3d Draw
    {
        rv.set_draw_texture(rv.get_builtin_texture(.Default))

        sphere := rv.get_builtin_mesh(.Icosphere_1)
        rv.draw_mesh(sphere, 0, scale = 1, col= [4]f32{0.0, 0.6, 0.2, 1})
    }

    // Ui Draw
    {
        rv.set_draw_layer(1)
        rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))


        rv.draw_perf_scopes()
    }

	rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, nil, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return &state
}

@export _module_desc := rv.Module_Desc{
    state_size = size_of(State),
    init = _init,
    update = _update,
    shutdown = _shutdown,
}
main :: proc(){
    rv.run_main_loop(_module_desc)
}
