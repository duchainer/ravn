#+feature using-stmt
package golf3d

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
BALL_PICK_RADIUS :: f32(0.25)

// ---- types -------------------------------------------------------

Ball :: struct {
	pos:    [3]f32,
	vel:    [3]f32,
	radius: f32,
	sunk:   bool,
	name:   string,
	ready:  bool, // true when stationary and able to shoot
}

Hole :: struct {
	pos: [3]f32,
}

Box :: struct {
	pos:         [3]f32,
	scale:       [3]f32,
	color:       [4]f32,
	restitution: f32,
	collider_id: u64,
}

Drag_State :: enum {
	Idle,
	Dragging,
}

Player_Drag :: struct {
	state:       Drag_State,
	ball_idx:    int,
	start_ground: [3]f32, // where on y=0 the drag started
}

Replay_Mode :: enum {
	None,
	Recording,
	Replaying,
}

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

	// Mark as ready to shoot when nearly stationary and not sunk
	if !ball.sunk && linalg.length2([2]f32{ball.vel.x, ball.vel.z}) < STOP_EPSILON * STOP_EPSILON && math.abs(ball.vel.y) < STOP_EPSILON {
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

all_settled :: proc(balls: []Ball) -> bool {
	for ball in balls {
		if ball.sunk { continue }
		if linalg.length2([2]f32{ball.vel.x, ball.vel.z}) > 0 {
			return false
		}
	}
	return true
}

// Project screen mouse position onto the y=0 ground plane.
screen_to_ground :: proc(mouse_screen: [2]f32, cam: rv.Camera) -> ([3]f32, bool) {
	ray_dir := rv.screen_to_world_ray(mouse_screen, cam)
	if math.abs(ray_dir.y) < 0.001 {
		return {}, false
	}
	t := -cam.pos.y / ray_dir.y
	if t < 0 {
		return {}, false
	}
	return cam.pos + ray_dir * t, true
}

// Find the closest ball to a ground point that is within pick radius.
pick_ball_at_ground :: proc(ground: [3]f32, balls: []Ball) -> (int, bool) {
	best_idx := -1
	best_dist := BALL_PICK_RADIUS
	for ball, i in balls {
		if ball.sunk || !ball.ready { continue }
		d := linalg.length([2]f32{ground.x - ball.pos.x, ground.z - ball.pos.z})
		if d < best_dist {
			best_dist = d
			best_idx = i
		}
	}
	return best_idx, best_idx >= 0
}

// Rotate a direction vector around the Y axis by `angle` radians.
rotate_y :: proc(dir: [3]f32, angle: f32) -> [3]f32 {
	ca := math.cos(angle)
	sa := math.sin(angle)
	return [3]f32{
		dir.x * ca - dir.z * sa,
		dir.y,
		dir.x * sa + dir.z * ca,
	}
}

// Build a quaternion that rotates {0,0,1} to `forward`.
quat_look_forward :: proc(forward: [3]f32) -> quaternion128 {
	f := linalg.normalize0(forward)
	if linalg.length(f) < 0.001 { return 1 }
	up := [3]f32{0, 1, 0}
	if abs(linalg.dot(f, up)) > 0.99 {
		up = [3]f32{1, 0, 0}
	}
	r := linalg.normalize(linalg.cross(up, f))
	u := linalg.normalize(linalg.cross(f, r))
	mat := matrix[3, 3]f32{
		r.x, r.y, r.z,
		u.x, u.y, u.z,
		f.x, f.y, f.z,
	}
	return linalg.quaternion_from_matrix3_f32(mat)
}

// ---- replay helpers -------------------------------------------------------

apply_replay_shots_for_tick :: proc(tick: i64, balls: []Ball) {
	for g.replay_idx < len(g.replay_events) {
		ev := g.replay_events[g.replay_idx]
		if ev.tick != tick { break }
		if int(ev.player_idx) < len(balls) {
			balls[ev.player_idx].vel = ev.vel
			balls[ev.player_idx].ready = false
		}
		g.replay_idx += 1
	}
}

fire_shot :: proc(ball_idx: int, vel: [3]f32) {
	if ball_idx >= len(g.balls) { return }
	g.balls[ball_idx].vel = vel
	g.balls[ball_idx].ready = false

	if g.replay_mode == .Recording {
		replay_db_record_shot(Shot_Event{
			tick       = g.t,
			player_idx = cast(u8)ball_idx,
			vel        = vel,
		})
	}
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

	// Click-and-drag
	drag:          Player_Drag,

	// Replay
	replay_mode:   Replay_Mode,
	replay_events: []Shot_Event,
	replay_idx:    int,

	// Time
	t:             i64,
	game_time:     f32,

	// Labels toggle
	show_labels:   bool,

	// Demo/test
	demo_started:  bool,
}

g: ^Game_State

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

start_hole :: proc(hole_idx: int) {
	g.active_hole = hole_idx
	g.t = 0
	g.game_time = 0
	g.drag = {}
	g.replay_idx = 0

	hole := g.holes[hole_idx]
	// Place balls in a line to the left of the hole
	for i in 0..<g.num_players {
		z_off := f32(i - g.num_players/2) * 0.6
		g.balls[i] = Ball{
			pos    = {-3.2, BALL_RADIUS, z_off},
			vel    = {},
			radius = BALL_RADIUS,
			sunk   = false,
			name   = fmt.tprintf("P%d", i+1),
			ready  = true,
		}
	}
	for i in g.num_players..<MAX_PLAYERS {
		g.balls[i] = {}
	}
}

_shutdown :: proc() {
	collision.shutdown()
	replay_db_close()
	free(g)
}

MAX_TICKS :: 60 * 200

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

	// Toggle recording
	if rv.get_key_pressed(.R) {
		switch g.replay_mode {
		case .None:
			if replay_db_init(true) {
				g.replay_mode = .Recording
				fmt.println("Started recording shots to SQLite")
			}
		case .Recording:
			g.replay_mode = .None
			replay_db_close()
			fmt.println("Stopped recording")
		case .Replaying:
			g.replay_mode = .None
			fmt.println("Stopped replay")
		}
	}

	// Start replay
	if rv.get_key_pressed(.P) {
		if g.replay_mode != .Replaying {
			if replay_db_init(false) {
				events := replay_db_load_shots()
				if len(events) > 0 {
					g.replay_events = events
					g.replay_idx = 0
					g.replay_mode = .Replaying
					start_hole(g.active_hole)
					fmt.printfln("Loaded %d shots, starting replay", len(events))
				} else {
					fmt.println("No recorded shots found")
				}
			}
		}
	}

	// Demo key: fire test shots
	if rv.get_key_pressed(.T) && g.replay_mode != .Replaying {
		g.demo_started = true
		// Fire a few demo shots
		if g.balls[0].ready { fire_shot(0, {12.0, 0, -0.5}) }
		if g.balls[1].ready { fire_shot(1, {8.0, 0, 0.3}) }
		if g.balls[2].ready { fire_shot(2, {10.0, 0, -1.0}) }
		if g.balls[3].ready { fire_shot(3, {6.0, 0, 1.5}) }
		if g.balls[4].ready { fire_shot(4, {9.0, 0, 0}) }
	}

	delta := rv.get_delta_time()
	g.game_time += delta

	// Build the current camera for raycasting
	cam_rot_quat := rv.euler_rot(g.cam.rot)
	camera := rv.make_perspective_3d_camera(
		rv.get_screen_size(),
		g.cam.pos,
		cam_rot_quat,
		g.cam.fov,
	)

	// ---- click-and-drag shot input ---------------------------------
	mouse_pos := rv.get_mouse_pos()
	ground_pos, ground_ok := screen_to_ground(mouse_pos, camera)

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

	// Left mouse press: start drag if clicking near a ready ball
	if rv.get_mouse_pressed(.Left) && ground_ok && g.replay_mode != .Replaying {
		idx, ok := pick_ball_at_ground(ground_pos, g.balls[:g.num_players])
		if ok {
			g.drag.state = .Dragging
			g.drag.ball_idx = idx
			g.drag.start_ground = ground_pos
		}
	}

	// Left mouse release: fire shot if dragging
	if rv.get_mouse_released(.Left) && g.drag.state == .Dragging && g.replay_mode != .Replaying {
		ball := &g.balls[g.drag.ball_idx]
		pull := ball.pos - ground_pos
		pull.y = 0
		stretch := linalg.length([2]f32{pull.x, pull.z})

		if stretch > MIN_DRAG_DIST {
			// Base direction (opposite to pull)
			base_dir := linalg.normalize0(pull)

			// Apply oscillation based on stretch
			oscillation := math.sin(g.game_time * OSCILLATION_FREQ * 2.0 * math.PI) * stretch * OSCILLATION_FACTOR
			actual_dir := rotate_y(base_dir, oscillation)

			// Power scales with stretch, clamped to max
			power := clamp(stretch * SHOT_POWER_SCALE, 0, MAX_SHOT_SPEED)
			vel := actual_dir * power
			vel.y = 0

			fire_shot(g.drag.ball_idx, vel)
		}
		g.drag.state = .Idle
	}

	// ---- physics tick ---------------------------------------------
	{
		rv.perf_scope("_update_game")

		g.t += 1

		// Apply replay shots before this tick
		if g.replay_mode == .Replaying {
			apply_replay_shots_for_tick(g.t, g.balls[:])
		}

		if g.t <= MAX_TICKS {
			tick(g.balls[:g.num_players], g.holes[g.active_hole], DELTA)
		}
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

		// Draw hole as a dark circle on the ground
		hole := g.holes[g.active_hole]
		rv.draw_mesh(sphere, pos = hole.pos, scale = HOLE_RADIUS, col = [4]f32{0.1, 0.1, 0.1, 1})

		// Draw click-and-drag arrow if dragging
		if g.drag.state == .Dragging && ground_ok {
			ball := g.balls[g.drag.ball_idx]
			pull := ball.pos - ground_pos
			pull.y = 0
			stretch := linalg.length([2]f32{pull.x, pull.z})

			if stretch > MIN_DRAG_DIST {
				base_dir := linalg.normalize0(pull)

				// Oscillation
				oscillation := math.sin(g.game_time * OSCILLATION_FREQ * 2.0 * math.PI) * stretch * OSCILLATION_FACTOR
				actual_dir := rotate_y(base_dir, oscillation)

				// Arrow visual: longer and wider with stronger pull
				power_ratio := clamp(stretch / MAX_DRAG_DIST, 0, 1)
				arrow_len := clamp(stretch * 1.2, 0.1, 3.0)
				arrow_thick := 0.02 + power_ratio * 0.06

				// Color shifts from green -> yellow -> red with power
				arrow_col := [4]f32{
					power_ratio,
					1.0 - power_ratio * 0.5,
					0.2,
					1.0,
				}

				// Shaft: line from ball outward
				shaft_start := ball.pos + {0, 0.05, 0}
				shaft_end   := shaft_start + actual_dir * arrow_len
				rv.draw_line(shaft_start, shaft_end, col = {arrow_col, arrow_col})

				// Arrow head: small box at the tip
				head_scale := arrow_thick * 2.5
				arrow_rot := quat_look_forward(actual_dir)
				rv.draw_mesh(cube, pos = shaft_end, scale = {head_scale, head_scale, head_scale}, rot = arrow_rot, col = arrow_col)

				// Oscillation preview: small wiggly line at tip showing the uncertainty cone
				preview_len := f32(0.3)
				preview_rot_pos := rotate_y(actual_dir, +0.15 * stretch)
				preview_rot_neg := rotate_y(actual_dir, -0.15 * stretch)
				rv.draw_line(shaft_end, shaft_end + preview_rot_pos * preview_len, col = {arrow_col * 0.6, arrow_col * 0.6})
				rv.draw_line(shaft_end, shaft_end + preview_rot_neg * preview_len, col = {arrow_col * 0.6, arrow_col * 0.6})
			}
		}

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

		status := ""
		switch g.replay_mode {
		case .None:      status = "Mode: Normal  (R=record  P=replay)"
		case .Recording: status = "Mode: RECORDING shots to SQLite"
		case .Replaying: status = fmt.tprintf("Mode: REPLAYING  (%d/%d shots)", g.replay_idx, len(g.replay_events))
		}
		rv.draw_text(status, {14, y, 0.1}, scale = scale - 0.5)
		y += line_h

		if g.drag.state == .Dragging {
			rv.draw_text("DRAGGING... release to shoot", {14, y, 0.1}, scale = scale - 0.5, col = [4]f32{0, 1, 0, 1})
			y += line_h
		}

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
	fmt.println("=== Mini Golf 3D prototype (ravn + per-shape restitution + click-drag + sqlite replay) ===")
	fmt.println()

	rv.run_main_loop(_module_desc)
}
