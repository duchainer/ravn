package golf3d

import "core:fmt"
import "core:math"
import "core:math/linalg"
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
	sunk: bool,
	name: string,
}

Hole :: struct {
	pos: [3]f32, // ground-level position, y = 0
}

// ---- course geometry (registered fresh into the collision step every tick) --

register_course :: proc() {
	// Ground: top surface sits exactly at y = 0.
	collision.add_box_shape(
		pos   = {0, -GROUND_THICK * 0.5, 0},
		scale = {COURSE_HALF_X, GROUND_THICK * 0.5, COURSE_HALF_Z},
	)

	// Four perimeter walls (bumpers).
	collision.add_box_shape(
		pos   = {-COURSE_HALF_X - WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
	)
	collision.add_box_shape(
		pos   = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, 0},
		scale = {WALL_THICK, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
	)
	collision.add_box_shape(
		pos   = {0, WALL_HEIGHT * 0.5, -COURSE_HALF_Z - WALL_THICK},
		scale = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
	)
	collision.add_box_shape(
		pos   = {0, WALL_HEIGHT * 0.5, COURSE_HALF_Z + WALL_THICK},
		scale = {COURSE_HALF_X + WALL_THICK, WALL_HEIGHT * 0.5, WALL_THICK},
	)
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
	if ball.sunk {
		return
	}

	ball.vel.y -= GRAVITY * dt
	ball.vel = apply_rolling_friction_xz(ball.vel, dt)

	new_pos, new_vel := collision.collide_sphere_swept(ball.pos, ball.vel, BALL_RADIUS)
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
	collision.begin_step(dt)
	register_course()
	collision.end_step()

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

main :: proc() {
	state: collision.State
	collision.init(&state)
	defer collision.shutdown()

	hole := Hole{pos = {3.4, 0, 0}}
	balls := [2]Ball{
		Ball{pos = {-3.5, BALL_RADIUS, 1.2}, vel = {2.6, 0, -0.9}, name = "P1"},
		Ball{pos = {-3.5, BALL_RADIUS, -1.2}, vel = {3.1, 0, 0.5}, name = "P2"},
	}

	fmt.println("=== Mini Golf 3D prototype (ravn collision.collide_sphere_swept) ===")
	fmt.printfln("Course: x=[-%.1f,%.1f] z=[-%.1f,%.1f], hole at %v", COURSE_HALF_X, COURSE_HALF_X, COURSE_HALF_Z, COURSE_HALF_Z, hole.pos)
	fmt.println()

	MAX_TICKS :: 60 * 20

	for t in 0 ..< MAX_TICKS {
		tick(balls[:], hole, DELTA)
		free_all(context.temp_allocator) // collision package uses temp_allocator internally each step

		if t % 30 == 0 || t <= 3 {
			fmt.printfln(
				"t=%3d (%.2fs)  P1 pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) sunk=%v  |  P2 pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) sunk=%v",
				t, f32(t) * DELTA,
				balls[0].pos.x, balls[0].pos.y, balls[0].pos.z, balls[0].vel.x, balls[0].vel.y, balls[0].vel.z, balls[0].sunk,
				balls[1].pos.x, balls[1].pos.y, balls[1].pos.z, balls[1].vel.x, balls[1].vel.y, balls[1].vel.z, balls[1].sunk,
			)
		}

		if all_settled(balls[:]) {
			fmt.println()
			fmt.printfln("All balls settled at t=%d (%.2fs)", t, f32(t) * DELTA)
			break
		}
	}

	fmt.println()
	fmt.printfln("Final: P1 sunk=%v pos=%v   P2 sunk=%v pos=%v", balls[0].sunk, balls[0].pos, balls[1].sunk, balls[1].pos)

	// --- scenario 2: aimed shot, should sink ---
	fmt.println()
	fmt.println("=== Scenario 2: aimed capture check ===")
	hole2 := Hole{pos = {2.0, 0, 0}}
	start2 := [3]f32{-3.5, BALL_RADIUS, 0}
	dir2 := linalg.normalize(hole2.pos - start2)
	// v^2 = v_final^2 + 2*a*d, aim to arrive just under capture speed
	dist2 := linalg.length(hole2.pos - start2)
	aimed_speed := math.sqrt((CAPTURE_SPEED*0.7)*(CAPTURE_SPEED*0.7) + 2*ROLLING_FRICTION_DECEL*dist2)
	aimed_arr := [1]Ball{Ball{pos = start2, vel = dir2 * aimed_speed, name = "aimed"}}
	for t in 0 ..< 600 {
		tick(aimed_arr[:], hole2, DELTA)
		free_all(context.temp_allocator)
		if aimed_arr[0].sunk || linalg.length([2]f32{aimed_arr[0].vel.x, aimed_arr[0].vel.z}) == 0 {
			break
		}
	}
	fmt.printfln("aimed: sunk=%v final_pos=%v", aimed_arr[0].sunk, aimed_arr[0].pos)

	// --- scenario 3: straight shot into a wall, checking bounce behavior ---
	fmt.println()
	fmt.println("=== Scenario 3: wall-hit behavior ===")
	wall_hole := Hole{pos = {999, 0, 999}} // far away, irrelevant to this test
	wall_arr := [1]Ball{Ball{pos = {0, BALL_RADIUS, 0}, vel = {5.0, 0, 0}, name = "into_wall"}}
	fmt.printfln("t=  0  pos=%v vel=%v", wall_arr[0].pos, wall_arr[0].vel)
	for t in 1 ..< 90 {
		tick(wall_arr[:], wall_hole, DELTA)
		free_all(context.temp_allocator)
		if t % 10 == 0 || t < 5 {
			fmt.printfln("t=%3d  pos=%v vel=%v", t, wall_arr[0].pos, wall_arr[0].vel)
		}
	}
}
