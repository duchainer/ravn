package raph_minigolf

import "core:math"
import "core:math/linalg"
// import "core:math/rand"

import rv "../.."
// import audio "../../audio"
import platform "../../platform"
import coll "../../collision"

// import ufmt "../../base/ufmt"
import base "../../base/"
_ :: base

State :: struct {
	cam: struct {
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

    state.ball.pos = {10, 0, 0}  // Start just above planet surface for testing
    state.ball.vel = {0,0.1,0}
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

            // Gravity toward planet center (inverse-square law)
            vec_ball_planet := state.planets[0].pos - ball.pos
            dist2 := linalg.vector_length2(vec_ball_planet)
            dist := linalg.vector_length(vec_ball_planet)


            base.log_dump(dist > ball.radius + state.planets[0].radius)
            if true && dist > ball.radius + state.planets[0].radius {
                dir_ball_planet := vec_ball_planet / dist
                gravity_accel := dir_ball_planet * 15.0 / dist2
                ball.vel += gravity_accel * delta
            }

            // Air damping (lose 50% velocity per second)
            // TODO Have it happen closer to the atmosphere of the "planets"
            // ball.vel *= math.pow(0.5, delta)

            // Store pre-collision velocity for bounce calculation
            old_vel := ball.vel

            contacts: []coll.Contact
            ball.pos, ball.vel, contacts = coll.collide_sphere(
                pos = ball.pos,
                vel = ball.vel,
                rad = ball.radius,
            )

            if len(contacts) > 0 {
                // Snap ball to exact surface distance. collide_sphere only resolves
                // velocity (no direct position fix), so penetration or floating
                // is common on discrete steps. Force the exact contact distance.
                dir := linalg.normalize(ball.pos - state.planets[0].pos)
                ball.pos = state.planets[0].pos + dir * (state.planets[0].radius + ball.radius)

                // Bounce with restitution (energy absorption)
                // Gate it so gravity on resting contact doesn't create a persistent float.
                restitution := f32(0.4)
                impact_threshold := f32(0.3) // m/s; below this treat as resting contact

                for contact in contacts {
                    v_normal_before := linalg.dot(old_vel, contact.normal)
                    // Only bounce on real impact, not gentle resting gravity
                    if v_normal_before < -impact_threshold {
                        ball.vel += contact.normal * (-restitution * v_normal_before)
                    }
                }

                // TODO have it be different per-planet instead, or something
                // Ground friction when touching surface
                ball.vel *= math.pow(0.5, delta)
            }
        }
    }

    {
        rv.perf_scope("_update_camera")

        // Camera Orbit on left mouse drag
        if rv.get_mouse_down(.Left){
            state.cam.rot.xy += rv.get_mouse_delta().yx * 0.005
            state.cam.rot.x = clamp(state.cam.rot.x, -math.PI * 0.49, math.PI * 0.49)
        }

        // Zoom with scroll wheel
        scroll := rv.get_scroll_delta().y
        if scroll != 0 {
            state.cam.distance *= math.pow(0.9, scroll)
            state.cam.distance = clamp(state.cam.distance, 1.0, 100.0)
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

        sphere := rv.get_builtin_mesh(.UV_Sphere_1)
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
