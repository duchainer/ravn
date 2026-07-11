package raph_minigolf

import "core:math"
import "core:math/linalg"
// import "core:math/rand"

import rv "../../."
// import audio "../../audio"
import platform "../../platform"
import coll "../../collision"

// import ufmt "../../base/ufmt"
import base "../../base/"
_ :: base

State :: struct {
	cam:                  struct {
		pos: [3]f32,
		rot: [3]f32,
		fov: f32,
        target: [3]f32,
        distance: f32,
	},

    ball : struct {
        pos : [3]f32,
        vel : [3]f32,
        radius: f32,
    },
    planets: [10]struct{
        pos: [3]f32,
        radius: f32,
    },

    // coll: struct {
    //     arena:      coll.Arena_Handle,
    //     mesh:       coll.Mesh_Handle,
    // },
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
    state.ball.radius = 0.10

    coll.init(new(coll.State))

    // state.arena = coll.create_arena(1024 * 1024)
    // state.mesh = coll.create_mesh(state.arena, _verts, _triangles)

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

    state.planets[0] = {
        pos = {0, 0, 0},
        radius = 1,
    }
    {
        coll.add_sphere_shape(pos=state.planets[0].pos, rad=state.planets[0].radius, layer=0, id=0)

        delta := rv.get_delta_time()
        {
            rv.perf_scope("_update_game")

            ball := &state.ball

            vec_ball_planet := state.planets[0].pos - ball.pos
            distance2_ball_planet := linalg.vector_length2(vec_ball_planet)
            dir_ball_planet := linalg.normalize0(vec_ball_planet)
            ball.vel =  dir_ball_planet * 9.98 / distance2_ball_planet
            ball.pos += ball.vel

            contacts: []coll.Contact
            ball_rad : f32= 1
            ball.pos, ball.vel, contacts = coll.collide_sphere(pos=ball.pos, vel=ball.vel, rad=ball_rad)
        }
    }

    {
        rv.perf_scope("_update_camera")

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
        rv.draw_mesh(sphere, pos = state.planets[0].pos, scale = state.planets[0].radius, col= [4]f32{0.0, 0.6, 0.2, 1})

        rv.draw_mesh(sphere, pos = state.ball.pos, scale = state.ball.radius, col = 1)
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
