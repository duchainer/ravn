package raph_putt_putt

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"

import rv "../.."
import platform "../../platform"
import collision "../../collision"
import raph_physics "../../my-packages/raph_physics/"

// ---- physics / course constants -------------------------------------------------------

DELTA :: f32(1.0 / 60.0)

BALL_RADIUS :: f32(0.06)
HOLE_RADIUS :: f32(0.09)
CAPTURE_SPEED :: f32(1.2)

ROLLING_FRICTION_DECEL :: f32(0.9)
STOP_EPSILON :: f32(0.02)
GRAVITY :: f32(9.8)

COURSE_HALF_X :: f32(4.0)
COURSE_HALF_Z :: f32(2.5)
WALL_HEIGHT :: f32(0.30)
WALL_THICK :: f32(0.05)
GROUND_THICK :: f32(0.20)

// ---- gameplay constants -------------------------------------------------------

MAX_PLAYERS :: 16
MIN_DRAG_DIST :: f32(0.15)
MAX_DRAG_DIST :: f32(5.0)
MAX_SHOT_SPEED :: f32(20.0)
SHOT_POWER_SCALE :: f32(4.0)
OSCILLATION_FREQ :: f32(4.0)
OSCILLATION_FACTOR :: f32(0.25)
BALL_PICK_RADIUS :: f32(0.5)

// ---- types -------------------------------------------------------

Ball :: struct {
	pos:    [3]f32,
	vel:    [3]f32,
	radius: f32,
    sunk: bool,
    ready: bool,
    name: string,
}

Hole :: struct {
	pos: [3]f32,
    radius: f32,
}

Box :: struct {
	pos:         [3]f32,
	scale:       [3]f32,
	color:       [4]f32,
	restitution: f32,
	collider_id: u64,
}

// ---- main state -------------------------------------------------------

Game_State :: struct {
	cam: struct {
		pos:      [3]f32,
		rot:      [3]f32,
		fov:      f32,
		target:   [3]f32,
		distance: f32,
	},

	balls:         [MAX_PLAYERS]Ball,
	num_players:   int,
	active_hole:   int,
	holes:         [3]Hole,
	boxes:         [8]Box,

	collision: struct {
		state: collision.State
	},

	// Time
	t:             i64,
	game_time:     f32,

	// Labels toggle
	show_labels:   bool,

	// Drag state
	drag: struct {
		active:      bool,
		ball_idx:    int,
		start_ground: [3]f32,
	},
}

g: ^Game_State


// ---- course geometry -------------------------------------------------------

register_course :: proc() {
	// Ground: top surface sits exactly at y = 0.
	g.boxes[0] = {
		pos         = {0, -GROUND_THICK * 0.5, 0},
		scale       = {COURSE_HALF_X, GROUND_THICK * 0.5, COURSE_HALF_Z},
		color       = [4]f32{0, 0.8, 0, 1},
		restitution = 0.3,
		collider_id = 0,
	}
	collision.add_box_shape(g.boxes[0].pos, g.boxes[0].scale, restitution = g.boxes[0].restitution, id = g.boxes[0].collider_id)

	// Four perimeter walls with different restitutions.
	g.boxes[1] = {
		pos         = {-COURSE_HALF_X - WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale       = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
		color       = [4]f32{0.8, 0.8, 0, 1},
		restitution = 0.95,
		collider_id = 1,
	}
	collision.add_box_shape(g.boxes[1].pos, g.boxes[1].scale, restitution = g.boxes[1].restitution, id = g.boxes[1].collider_id)

	g.boxes[2] = {
		pos         = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale       = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
		color       = [4]f32{0.8, 0.8, 0, 1},
		restitution = 0.7,
		collider_id = 2,
	}
	collision.add_box_shape(g.boxes[2].pos, g.boxes[2].scale, restitution = g.boxes[2].restitution, id = g.boxes[2].collider_id)

	g.boxes[3] = {
		pos         = {0, WALL_HEIGHT * 0.5, -COURSE_HALF_Z - WALL_THICK},
		scale       = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
		color       = [4]f32{0.8, 0.8, 0, 1},
		restitution = 0.5,
		collider_id = 3,
	}
	collision.add_box_shape(g.boxes[3].pos, g.boxes[3].scale, restitution = g.boxes[3].restitution, id = g.boxes[3].collider_id)

	g.boxes[4] = {
		pos         = {0, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
		scale       = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
		color       = [4]f32{0.8, 0.8, 0, 1},
		restitution = 0.85,
		collider_id = 4,
	}
	collision.add_box_shape(g.boxes[4].pos, g.boxes[4].scale, restitution = g.boxes[4].restitution, id = g.boxes[4].collider_id)
}

// ---- helpers -------------------------------------------------------

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

tick_ball :: proc(ball: ^Ball, hole: Hole, dt: f32) {
	if ball == {} do return
	if ball.sunk {
		return
	}

	ball.vel.y -= GRAVITY * dt
	ball.vel = apply_rolling_friction_xz(ball.vel, dt)

	new_pos, new_vel := raph_physics.raph_collide_sphere_swept(ball.pos, ball.vel, BALL_RADIUS, restitution = 0.6)
	ball.pos = new_pos
	ball.vel = new_vel

	horiz_dist := linalg.length([2]f32{ball.pos.x - hole.pos.x, ball.pos.z - hole.pos.z})
	speed := linalg.length(ball.vel)
	if horiz_dist < HOLE_RADIUS && speed < CAPTURE_SPEED {
		ball.sunk = true
		ball.pos = hole.pos + {0, BALL_RADIUS, 0}
		ball.vel = {0, 0, 0}
	}

	// Mark as ready to shoot when nearly stationary on the ground.
	// We only check horizontal speed; Y velocity never hits exactly zero
	// because the position-based contact solver adds micro-jitter.
	if !ball.sunk && linalg.length2([2]f32{ball.vel.x, ball.vel.z}) < STOP_EPSILON * STOP_EPSILON {
		ball.ready = true
	} else {
		ball.ready = false
	}
}

tick :: proc(balls: []Ball, hole: Hole, dt: f32) {
	register_course()
	for &ball in balls {
		tick_ball(&ball, hole, dt)
	}
}


_init :: proc() {
	platform.set_window_title(rv.get_window(), "Raph Mini Golf 3D")

	g = new(Game_State)

	g.cam.pos = {0, 0, -10}
	g.cam.rot = {0.3, 0, 0}
	g.cam.fov = rv.deg(degrees = 90)
	g.cam.target = {0, 0, 0}
	g.cam.distance = 10

	g.num_players = 5
	g.active_hole = 0
	g.show_labels = true
	g.t = 0
	g.game_time = 0

	collision.init(&g.collision.state)

	// Initialize hole positions
	g.holes[0] = Hole{pos = {3.4, 0, 0}}
	g.holes[1] = Hole{pos = {-2.0, 0, 1.5}}
	g.holes[2] = Hole{pos = {0, 0, -1.8}}

	start_hole(0)
}


reset_balls :: proc (){
    // // Place balls in a line to the left of the hole
    for i in 0..<g.num_players {
        z_off := f32(i - g.num_players/2) * 0.6
        g.balls[i] = Ball{
            pos    = {-3.2, BALL_RADIUS, z_off},
            vel    = {10, 1, 10},
            radius = BALL_RADIUS,
            sunk   = false,
            name   = fmt.tprintf("P%d", i+1),
            ready  = true,
        }
    }
}
start_hole :: proc(hole_idx: int) {
	g.active_hole = hole_idx
	g.t = 0
	g.game_time = 0

	hole := g.holes[hole_idx]
    reset_balls()
	for i in g.num_players..<MAX_PLAYERS {
		g.balls[i] = {}
	}
}

_shutdown :: proc() {
	collision.shutdown()
	free(g)
}


_update :: proc(hot_state: rawptr) -> rawptr {
	rv.perf_scope()

	if hot_state != nil {
		g = cast(^Game_State)hot_state
	}

	if rv.get_key_pressed(.Escape) {
		rv.request_shutdown()
		return &g
	}

	// Toggle labels
	if rv.get_key_pressed(.L) {
		g.show_labels = !g.show_labels
	}
	if rv.get_key_pressed(.T) {
        reset_balls()
    }

	delta := rv.get_delta_time()
	g.game_time += delta

    // Camera

    cam_rot_quat := rv.euler_rot(g.cam.rot)
    camera := rv.make_perspective_3d_camera(
        rv.get_screen_size(),
        g.cam.pos,
        cam_rot_quat,
        g.cam.fov,
    )

    // Right mouse = camera orbit (changed from left)
    if rv.get_mouse_down(.Right) {
        g.cam.rot.xy += rv.get_mouse_delta().yx * 0.005
        g.cam.rot.x = clamp(g.cam.rot.x, -math.PI * 0.49, math.PI * 0.49)
    }

    // Scroll = zoom
    scroll := rv.get_scroll_delta().y
    if scroll != 0 {
        g.cam.distance *= math.pow(0.9, scroll)
        g.cam.distance = clamp(g.cam.distance, 1.0, 100.0)
    }

    // Update camera position from orbit
    mat := linalg.matrix3_from_quaternion_f32(cam_rot_quat)
    g.cam.pos = g.cam.target - mat[2] * g.cam.distance

    // Rebuild camera after position update
    camera = rv.make_perspective_3d_camera(
        rv.get_screen_size(),
        g.cam.pos,
        cam_rot_quat,
        g.cam.fov,
    )

    // ---- mouse ground position ------------------------------------
    mouse_ground: [3]f32
    mouse_ground_ok := false
    {
        mouse_ray := rv.screen_to_world_ray(rv.get_mouse_pos(), camera)
        if abs(mouse_ray.y) > 0.001 {
            t := -camera.pos.y / mouse_ray.y
            if t > 0 {
                mouse_ground = camera.pos + mouse_ray * t
                mouse_ground_ok = true
            }
        }
    }

    // ---- click-and-drag shooting ----------------------------------
    if rv.get_mouse_pressed(.Left) && mouse_ground_ok {
        // Find nearest ready ball
        best_idx := -1
        best_dist := BALL_PICK_RADIUS
        for i in 0..<g.num_players {
            ball := g.balls[i]
            if ball.sunk || !ball.ready { continue }
            d := linalg.length([2]f32{mouse_ground.x - ball.pos.x, mouse_ground.z - ball.pos.z})
            if d < best_dist {
                best_dist = d
                best_idx = i
            }
        }
        if best_idx >= 0 {
            g.drag.active = true
            g.drag.ball_idx = best_idx
            g.drag.start_ground = mouse_ground
        }
    }

    if rv.get_mouse_released(.Left) && g.drag.active {
        ball := &g.balls[g.drag.ball_idx]
        pull := ball.pos - mouse_ground
        pull.y = 0
        stretch := linalg.length([2]f32{pull.x, pull.z})

        if stretch > MIN_DRAG_DIST {
            dir := linalg.normalize0([3]f32{pull.x, 0, pull.z})
            power := clamp(stretch * SHOT_POWER_SCALE, 0, MAX_SHOT_SPEED)
            ball.vel = dir * power
            ball.vel.y = 0
            ball.ready = false
        }
        g.drag.active = false
    }

	// ---- physics tick ---------------------------------------------
	{
		rv.perf_scope("_update_game")

		g.t += 1

        tick(g.balls[:g.num_players], g.holes[g.active_hole], DELTA)
		free_all(context.temp_allocator)
	}

	// ---- submit draw layers ---------------------------------------
	rv.update_draw_layer(0, camera)
	rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

	rv.set_draw_depth(.Depth)

	// ---- 3D Draw --------------------------------------------------
	{
		rv.set_draw_texture(rv.get_builtin_texture(.Default))

		cube := rv.get_builtin_mesh(.Cube)
		for box in g.boxes {
			if box.color.w <= 0 { continue }
			rv.draw_mesh(cube, box.pos, box.scale, col = box.color)
		}

		sphere := rv.get_builtin_mesh(.UV_Sphere_1)
		for ball in g.balls {
			if ball == {} { continue }
			col := ball.sunk ? [4]f32{0.5, 0.5, 0.5, 1} : [4]f32{1, 1, 1, 1}
			rv.draw_mesh(sphere, pos = ball.pos, scale = ball.radius, col = col)
		}

		// Draw selection ring on the ground around ready balls
			for ball in g.balls {
				if ball == {} || ball.sunk || !ball.ready { continue }
				ring_rad := ball.radius * 2.5
				rv.draw_line_circle(ball.pos + {0, 0.01, 0}, rad = {ring_rad, ring_rad}, col = [4]f32{0, 1, 0, 0.6}, segments = 16)
			}

		// Draw hole as a dark circle on the ground
		hole := g.holes[g.active_hole]
		rv.draw_mesh(sphere, pos = hole.pos, scale = HOLE_RADIUS, col = [4]f32{0.1, 0.1, 0.1, 1})

		// Draw labels above colliders
		if g.show_labels {
			rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
			for box, i in g.boxes {
				if box.color.w <= 0 { continue }
				label_pos := box.pos + [3]f32{0, box.scale.y + 0.15, 0}
				text := fmt.tprintf("id=%d r=%.2f", box.collider_id, box.restitution)
				rv.draw_text(text, label_pos, scale = 0.015, anchor = 0, col = [4]f32{1, 1, 0, 1})
			}
		}
		// Draw drag line
		if g.drag.active {
			ball := g.balls[g.drag.ball_idx]
			if mouse_ground_ok {
				// Line from ball to mouse ground position
				rv.draw_line(ball.pos, mouse_ground, col = [4]f32{1, 0, 0, 0.8})
				// Small sphere at mouse ground position
				rv.draw_mesh(sphere, pos = mouse_ground, scale = 0.05, col = [4]f32{1, 0, 0, 0.8})
			}
		}
	}

	// ---- UI Draw --------------------------------------------------
	{
		rv.set_draw_layer(1)
		rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))

		y: f32 = 14
		line_h :: f32(18)
		scale :: f32(2)

		rv.draw_text("Mini Golf 3D - Putt Party Clone", {14, y, 0.1}, scale = scale)
		y += line_h
		rv.draw_text("LMB drag on ball to shoot  |  RMB orbit  |  Scroll zoom", {14, y, 0.1}, scale = scale - 0.5)
		y += line_h
		rv.draw_text(fmt.tprintf("Hole %d  |  Tick %d", g.active_hole + 1, g.t), {14, y, 0.1}, scale = scale - 0.5)
		y += line_h



		// Per-ball status
		for i in 0..<g.num_players {
			ball := g.balls[i]
			if ball == {} { continue }
			status_str := fmt.tprintf("%s: %s pos=%.2f,%.2f vel=%.2f",
				ball.name,
				ball.sunk ? "SUNK" : (ball.ready ? "READY" : "MOVING"),
				ball.pos.x, ball.pos.z,
				linalg.length(ball.vel),
			)
			rv.draw_text(status_str, {14, y, 0.1}, scale = scale - 1, col = ball.sunk ? [4]f32{0.5, 1, 0.5, 1} : [4]f32{1, 1, 1, 1})
			y += line_h * 0.7
		}

		rv.draw_perf_scopes(pos={810, 40, 0.1})
	}

	rv.submit_layers()
	rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, nil, true)
	rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

	return &g
}

@export _module_desc := rv.Module_Desc{
	state_size = size_of(Game_State),
	init       = _init,
	update     = _update,
	shutdown   = _shutdown,
}

main :: proc() {
	fmt.println("=== Mini Golf 3D prototype (ravn + per-shape restitution) ===")
	fmt.println()

	rv.run_main_loop(_module_desc)
}
