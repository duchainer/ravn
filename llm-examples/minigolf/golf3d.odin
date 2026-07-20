#+feature using-stmt
package golf3d

import "core:fmt"
import "core:math"
import "core:math/linalg"

import rv "../.."
import platform "../../platform"
import collision "../../collision"

// ---- constants -------------------------------------------------------

DELTA :: f32(1.0 / 60.0)

BALL_RADIUS :: f32(0.06)
HOLE_RADIUS :: f32(0.09)
CAPTURE_SPEED :: f32(1.2)

ROLLING_FRICTION_DECEL :: f32(0.9)
STOP_EPSILON :: f32(0.02)
GRAVITY :: f32(9.8)

// Course footprint, in meters. y is up.
COURSE_HALF_X :: f32(4.0)
COURSE_HALF_Z :: f32(2.5)
WALL_HEIGHT :: f32(0.30)
WALL_THICK :: f32(0.05)
GROUND_THICK :: f32(0.20)

// ---- types -------------------------------------------------------

Ball :: struct {
	pos:  [3]f32,
	vel:  [3]f32,
    radius: f32,
	sunk: bool,
	name: string,
}

Hole :: struct {
	pos: [3]f32, // ground-level position, y = 0
}

Box :: struct {
    pos:   [3]f32,
    scale: [3]f32,
    color: [4]f32,
}

// ---- course geometry (registered fresh into the collision step every tick) --

register_course :: proc() {
    g.boxes[0] = {
		pos   = {0, -GROUND_THICK * 0.5, 0},
		scale = {COURSE_HALF_X, GROUND_THICK * 0.5, COURSE_HALF_Z},
        color = [4]f32{0, 0.8, 0, 1},
    }

	// Ground: top surface sits exactly at y = 0.
	collision.add_box_shape(g.boxes[0].pos, g.boxes[0].scale)

    g.boxes[1] = {
		pos   = {-COURSE_HALF_X - WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
        color = [4]f32{0.8, 0.8, 0, 1},
    }
	// Four perimeter walls (bumpers).
	collision.add_box_shape(g.boxes[1].pos, g.boxes[1].scale)


	g.boxes[2] = {
		pos   = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
        color = [4]f32{0.8, 0.8, 0, 1},
	}
    collision.add_box_shape(g.boxes[2].pos, g.boxes[2].scale)

	g.boxes[3] = {
		pos   = {0, WALL_HEIGHT * 0.5, -COURSE_HALF_Z - WALL_THICK},
		scale = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
        color = [4]f32{0.8, 0.8, 0, 1},
    }
	collision.add_box_shape(g.boxes[3].pos, g.boxes[3].scale)

	g.boxes[4] = {
		pos   = {0, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
		scale = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
        color = [4]f32{0.8, 0.8, 0, 1},
    }
	collision.add_box_shape(g.boxes[4].pos, g.boxes[4].scale)
}

// ---- physics -------------------------------------------------------

apply_rolling_friction_xz :: proc(vel: [3]f32, dt: f32) -> [3]f32 {
	horiz := [2]f32{vel.x, vel.z}
	speed := linalg.length(horiz)
	if speed <= STOP_EPSILON {
		return {0, vel.y, 0}
	}
	new_speed := max(f32(0.0), speed - ROLLING_FRICTION_DECEL * dt)
	if new_speed <= STOP_EPSILON {
		return {0, vel.y, 0}
	}
	dir := horiz / speed
	return {dir.x * new_speed, vel.y, dir.y * new_speed}
}

// Explicitly NO ball-vs-ball collision: each ball is simulated fully
// independently against the course geometry only.
tick_ball :: proc(ball: ^Ball, hole: Hole, dt: f32) {
    if ball == {} do return
	if ball.sunk {
		return
	}

	ball.vel.y -= GRAVITY * dt
	ball.vel = apply_rolling_friction_xz(ball.vel, dt)
    old_vel := ball.vel

	new_pos, new_vel, contacts := collision.raph_collide_sphere_swept(ball.pos, ball.vel, BALL_RADIUS, restitution = 0.9)
    ball.pos = new_pos
    ball.vel = new_vel

	horiz_dist := linalg.length([2]f32{ball.pos.x - hole.pos.x, ball.pos.z - hole.pos.z})
	speed := linalg.length(ball.vel)
	if horiz_dist < HOLE_RADIUS && speed < CAPTURE_SPEED {
		ball.sunk = true
		ball.pos = hole.pos + {0, BALL_RADIUS, 0}
		ball.vel = {0, 0, 0}
	}
}

tick :: proc(balls: []Ball, hole: Hole, dt: f32) {
	// Course is static, but ravn's collision step wants its shape list
	// rebuilt every step (see collision.odin: shape_data is per-step,
	// reset in begin_step and BVH-built in end_step).

	register_course()

	for &ball in balls {
		tick_ball(&ball, hole, dt)
	}
}

all_settled :: proc(balls: []Ball) -> bool {
	for ball in balls {
		if ball.sunk {
			continue
		}
		if linalg.length2([2]f32{ball.vel.x, ball.vel.z}) > 0 {
			return false
		}
	}
	return true
}

// ---- main -------------------------------------------------------

Game_State :: struct {
	cam: struct {
		pos: [3]f32,
		rot: [3]f32,
		fov: f32,
        target: [3]f32,
        distance: f32,
	},

	balls : [2]Ball,
	collision: struct{
        state: collision.State
    },
    boxes: [8]Box,
    holes : [3]Hole,
    t: i64,
}

g: ^Game_State

_init :: proc(){
	platform.set_window_title(rv.get_window(), "Raph Mini golf test 1")

    g = new(Game_State)

	g.cam.pos = {0, 0, -10}
	g.cam.rot = {0.3, 0, 0}
	g.cam.fov = rv.deg(degrees = 90)
	g.cam.target = {0, 0, 0}
	g.cam.distance = 10


    g.t = 0


	collision.init(&g.collision.state)
}

_shutdown :: proc(){
	collision.shutdown()

    free(g)
}

MAX_TICKS :: 60 * 200

tests :: proc (){
    g.t += 1
	if g.t > MAX_TICKS do return // done

    start_tick: i64

    start_tick = 0
	if start_tick < g.t && g.t < start_tick + 1000{
        if g.t == start_tick + 1 {
            g.holes[0] = Hole{pos = {3.4, 0, 0}}

            g.balls = [2]Ball{
                Ball{pos = {-3.5, BALL_RADIUS, 1.2}, vel = {12.6, 0, -0.9}, name = "P1", radius = BALL_RADIUS},
                Ball{pos = {-3.5, BALL_RADIUS, -1.2}, vel = {6.1, 0, 0.5}, name = "P2", radius = BALL_RADIUS},
            }
        }

        using g
	    if g.t == MAX_TICKS{
            fmt.println()
            fmt.printfln("Final: P1 sunk=%v pos=%v   P2 sunk=%v pos=%v", balls[0].sunk, balls[0].pos, balls[1].sunk, balls[1].pos)
        }
		tick(g.balls[:], g.holes[0], DELTA)
		free_all(context.temp_allocator) // collision package uses temp_allocator internally each step

		if g.t % 30 == 0 || g.t <= 3 {
			fmt.printfln(
				"g.t=%3d (%.2fs)  P1 pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) sunk=%v  |  P2 pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) sunk=%v",
				g.t, f32(g.t) * DELTA,
				balls[0].pos.x, balls[0].pos.y, balls[0].pos.z, balls[0].vel.x, balls[0].vel.y, balls[0].vel.z, balls[0].sunk,
				balls[1].pos.x, balls[1].pos.y, balls[1].pos.z, balls[1].vel.x, balls[1].vel.y, balls[1].vel.z, balls[1].sunk,
			)
		}

		if all_settled(balls[:]) {
			fmt.println()
			fmt.printfln("All balls settled at g.t=%d (%.2fs)", g.t, f32(g.t) * DELTA)
			return // done
		}

    }
    start_tick = 1000
	if start_tick < g.t && g.t < start_tick + 1000{
        // TODO Convert to ravn _update proc
        // --- scenario 3: straight shot into a wall, checking bounce behavior ---
        if g.t == start_tick + 1 {
            fmt.println()
            fmt.println("=== Scenario 3: wall-hit behavior ===")
            g.holes[2] = Hole{pos = {999, 0, 999}} // far away, irrelevant to this test
            g.balls = [2]Ball{Ball{pos = {0, BALL_RADIUS, 0}, vel = {5.0, 0, 0}, name = "into_wall"}, Ball{}}
            fmt.printfln("g.t=  0  pos=%v vel=%v", g.balls[0].pos, g.balls[0].vel)
        }
        tick(g.balls[0:0], g.holes[2], DELTA)
        free_all(context.temp_allocator)
        if g.t % 10 == 0 || g.t < start_tick + 5 {
            fmt.printfln("g.t=%3d  pos=%v vel=%v", g.t, g.balls[0].pos, g.balls[0].vel)
        }

    }
}

_update :: proc(hot_state: rawptr) -> rawptr{
    rv.perf_scope()

    // Only called on hot-reload
    if hot_state != nil{
        g = cast(^Game_State)hot_state
    }


    if rv.get_key_pressed(.Escape){
        rv.request_shutdown()
        return &g
    }

    cam_rot_quat: quaternion128

    {

        delta := rv.get_delta_time()
        {
            rv.perf_scope("_update_game")

            tests()
        }
    }

    {
        rv.perf_scope("_update_camera")

        // Camera Orbit on left mouse drag
        if rv.get_mouse_down(.Left){
            g.cam.rot.xy += rv.get_mouse_delta().yx * 0.005
            g.cam.rot.x = clamp(g.cam.rot.x, -math.PI * 0.49, math.PI * 0.49)
        }

        // Zoom with scroll wheel
        scroll := rv.get_scroll_delta().y
        if scroll != 0 {
            g.cam.distance *= math.pow(0.9, scroll)
            g.cam.distance = clamp(g.cam.distance, 1.0, 100.0)
        }

        cam_rot_quat = rv.euler_rot(g.cam.rot)
        mat := linalg.matrix3_from_quaternion_f32(cam_rot_quat)

        forward := mat[2]
        g.cam.pos = g.cam.target - forward * g.cam.distance
    }

    rv.update_draw_layer(
        0,
        rv.make_perspective_3d_camera(
            rv.get_screen_size(),
            g.cam.pos,
            cam_rot_quat,
            g.cam.fov
        )
    )
    rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

    rv.set_draw_depth(.Depth)

    // 3d Draw
    {
        rv.set_draw_texture(rv.get_builtin_texture(.Default))

        cube := rv.get_builtin_mesh(.Cube)
        for box in g.boxes{
            rv.draw_mesh(cube, box.pos, box.scale, col = box.color)
        }

        sphere := rv.get_builtin_mesh(.UV_Sphere_1)
        for ball in g.balls{
            rv.draw_mesh(sphere, pos = ball.pos, scale = ball.radius, col = 1)
        }
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

    return &g
}

@export _module_desc := rv.Module_Desc{
    state_size = size_of(Game_State),
    init = _init,
    update = _update,
    shutdown = _shutdown,
}

main :: proc() {

	fmt.println("=== Mini Golf 3D prototype (ravn collision.collide_sphere_swept) ===")
	// fmt.printfln("Course: x=[-%.1f,%.1f] z=[-%.1f,%.1f], hole at %v", COURSE_HALF_X, COURSE_HALF_X, COURSE_HALF_Z, COURSE_HALF_Z, g.holes[0].pos)
	fmt.println()


    rv.run_main_loop(_module_desc)
}
