package ravn_raph_snake_planet_example

import "core:math/linalg"
import "core:math/rand"
import "core:math"

import rv "../../."
import platform "../../platform"
import audio "../../audio"

import ufmt "../../base/ufmt"
// import base "../../base/"


SNAKE_RED :: [4]f32{1, 0.3, 0, 1}
SNAKE_ORANGE :: rv.ORANGE

PLANET_SIZE :: 0.75

state: ^State

State :: struct {
    cam : struct {
        pos: [3]f32,
        rot: quaternion128,
        fov: f32,
    },

    obsts : [64]Obstacle,
    num_obsts: i32,

    berry: Berry,
    berry_timer: f32,

    max_score: i32,
    screen: Screen_ID,

    snake: Snake,
    animation_clock_time: f32,

    berry_sound: rv.Sound_Resource_Handle,
    death_sound: rv.Sound_Resource_Handle,
    music_res: rv.Sound_Resource_Handle,
    music: rv.Sound_Handle,
}

Screen_ID :: enum u8 {
    Menu,
    Game,
    Death,
}

Obstacle :: struct {
    pos: [3]f32,
    radius: f32,
}

Berry :: struct {
    pos: [3]f32,
}

MAX_SEGMENTS :: 512

Snake :: struct {
    dir: [2]f32,
    pos: [3]f32,
    segments: [MAX_SEGMENTS]Segment,
    num_segments: i32,
    segment_timer: f32,
}

Segment :: struct {
    pos: [3]f32,
}


repel_from_obstacles :: proc(pos:[3] f32, radius: f32) -> [3]f32{
    pos := pos
    for obst in state.obsts[:state.num_obsts] {
        dist := linalg.length(pos - obst.pos)

        r := obst.radius + radius

        if dist > r {
            continue
        }

        // repel from obstacle
        dir := linalg.normalize0(pos - obst.pos)

        // stay on the surface of the planet
        pos = (linalg.normalize0(pos + dir * (r-dist)) * PLANET_SIZE)
    }
    return pos
}

spawn_berry :: proc() {
    state.berry = {
        pos = rand_dir() * PLANET_SIZE
    }

    for i in 0..<5 {
        state.berry.pos = repel_from_obstacles(state.berry.pos, radius=0.5)
    }

    rv.create_sound(state.berry_sound, pitch = rand.float32_range(0.9, 1.2))
}

rand_dir :: proc() -> [3]f32 {
    return linalg.normalize0([3]f32{
        rand.float32() * 2.0 - 1.0,
        rand.float32() * 2.0 - 1.0,
        rand.float32() * 2.0 - 1.0,
    })
}

new_game :: proc() {
    state.screen = .Game
    state.cam.pos = {0, 0, -10}
    state.cam.rot = 1
    state.cam.fov = rv.deg(degrees=90)
    state.berry_timer = 100
    state.snake = {
        pos = {0, 0, -1},
        dir = {0, 1},
        num_segments = 1,
        segments = {
            0 = {
                pos = {0, 0, -1}
            }
        }
    }

    state.num_obsts = 10
    for i in 0..<state.num_obsts {
        state.obsts[i] = {
            pos = rand_dir() * PLANET_SIZE,
            radius = rand.float32_range(0.1, 0.2)
        }
    }

    state.snake.pos = repel_from_obstacles(pos=state.snake.pos, radius=0.3)

    rv.destroy_sound(state.music)
    state.music = rv.create_sound(source = state.music_res, flags = {.Loop})

    spawn_berry()
}

add_snake_segment :: proc() {
    snake := &state.snake
    assert(snake.num_segments > 0)
    pos := snake.num_segments == 0 ? snake.pos : (
        snake.segments[snake.num_segments - 1].pos
    )
    offsets: [3]f32
    if snake.num_segments > 1 {
        offsets = pos - snake.segments[snake.num_segments - 2].pos
    } else {
        offsets = snake.segments[snake.num_segments - 1].pos - snake.pos
    }

    // stay on the surface of the planet
    offsets = (linalg.normalize0(offsets) * PLANET_SIZE)
    snake.segments[snake.num_segments] = {
        pos = pos + offsets,
    }
    snake.num_segments += 1
}

_init :: proc() {
    state = new(State)
    platform.set_window_title(rv.get_window(), "Raph Snake Planet")
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    state.death_sound = rv.create_sound_resource_encoded("death", #load("../../examples/data/snake_death_sound.wav")) or_else panic("create_sound_resource_encoded")
    state.berry_sound = rv.create_sound_resource_encoded("death", #load("../../examples/data/snake_powerup_sound.wav")) or_else panic("create_sound_resource_encoded")

    state.screen = .Menu
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> (data_ptr: rawptr) {
    rv.perf_scope()

    // Only called on hot-reload
    if hot_state != nil {
        state = cast(^State)hot_state
    }
    // base.log_dump((state)^)

    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    //
    // MARK : TICK
    //

    _update_game :: proc (delta: f32){
        rv.perf_scope()

        snake := &state.snake

        cam_rot_mat := linalg.matrix3_from_quaternion_f32(state.cam.rot)


        //
        // MARK : INPUT
        //



        // TODO: Gamepad
        move_input : [2]f32
        if rv.get_key_down(.D) do move_input.x += 1
        if rv.get_key_down(.A) do move_input.x -= 1
        if rv.get_key_down(.W) do move_input.y += 1
        if rv.get_key_down(.S) do move_input.y -= 1

        if rv.get_key_down(.Right) do move_input.x += 1
        if rv.get_key_down(.Left) do move_input.x -= 1
        if rv.get_key_down(.Up) do move_input.y += 1
        if rv.get_key_down(.Down) do move_input.y -= 1

        // move_dir := move_inp.x * [3]f32{1, 0, 0} + mat[1] * [3]f32{0, 1, 0}


        if linalg.length2(move_input) > 0.1 {
            move_input = linalg.normalize0(move_input)
        }

        snake.dir += move_input * delta * 8
        snake.dir = linalg.normalize0(snake.dir)

        world_dir :=
            cam_rot_mat[0] * snake.dir.x +
            cam_rot_mat[1] * snake.dir.y

        base_speed : f32 = 0.7
        speed: f32 = base_speed + f32(snake.num_segments / 4) * 0.05

        // JUICE on berry collect:  Add short (0.5s) dash
        speed *= rv.remap_clamped(state.berry_timer, 0, 0.5, 1.5, 1)

        snake.pos += world_dir * delta * speed

        // stay on the surface of the planet
        snake.pos = linalg.normalize0(snake.pos) * PLANET_SIZE

        state.berry_timer += delta

        if linalg.distance(state.berry.pos, snake.pos) < 0.2 {
            spawn_berry()

            add_snake_segment()
            add_snake_segment()
            state.berry_timer = 0
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            seg.pos = repel_from_obstacles(seg.pos, 0.1)
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            prev := i == 0 ? snake.pos :(
                snake.segments[i - 1].pos
            )

            // follow previous segment AND stay on the surface of the planet
            seg.pos = prev + (linalg.normalize0(seg.pos - prev) * PLANET_SIZE) * (0.15/PLANET_SIZE)
        }

        die := false

        for obst in state.obsts[:state.num_obsts] {
            if linalg.distance(obst.pos, snake.pos) < obst.radius {
                die = true
            }
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            seg.pos = (linalg.normalize0(seg.pos) * PLANET_SIZE)
            if i>0 && linalg.distance(seg.pos, snake.pos) < 0.15 {
                die = true
            }
        }

        state.cam.pos = rv.lexp(state.cam.pos, snake.pos * 2.5 + world_dir * 0.6, delta * 6)

        target_rot := linalg.quaternion_from_forward_and_up_f32(
            state.cam.pos,
            cam_rot_mat[1]
        )
        state.cam.rot = target_rot
        // JUICE on berry collect:  Widen FOV for 0.5s
        state.cam.fov = rv.lexp(state.cam.fov, rv.deg(65 + rv.remap_clamped(
            state.berry_timer,
            0, 0.5,
            7, 0
        )), rate = delta*15)

        if die {
            rv.create_sound(state.death_sound, pitch = rand.float32_range(0.9, 1.2))
            rv.destroy_sound(state.music)
            state.music = {}
            state.screen = .Death
        }
    }
    if state.screen == .Game do _update_game(delta)

    //
    // MARK : DRAW
    //

    rv.update_draw_layer(0, rv.make_perspective_3d_camera(
        rv.get_screen_size(), state.cam.pos, state.cam.rot, state.cam.fov))
    rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))

    rv.set_draw_depth(.Depth)

    if state.screen == .Game || state.screen == .Death {
        snake_head_color := rv.ORANGE + rv.YELLOW * 0.1
        snake_red := SNAKE_RED
        snake_orange := SNAKE_ORANGE
        if state.screen == .Game {
            state.animation_clock_time = rv.get_time()
        } else if state.screen == .Death {
            snake_head_color = snake_head_color * 0.40
            snake_red = snake_red * 0.75
            snake_orange = snake_orange * 0.75
        }

        snake := state.snake

        rv.set_draw_texture(rv.get_builtin_texture(.Default))

        sphere := rv.get_builtin_mesh(.Icosphere_1)
        rv.draw_mesh(sphere, pos=0, scale=PLANET_SIZE, col = [4]f32{0.0, 0.6, 0.2, 1})
        rv.set_draw_texture(rv.get_builtin_texture(.White))

        rv.draw_mesh(sphere, snake.pos, scale = 0.15, col = snake_head_color)
        for seg, i in snake.segments[:snake.num_segments] {
            rv.draw_mesh(
                handle = sphere,
                pos = seg.pos * (1.0 + 0.025 * rv.nsin(f32(i) * 0.21 - state.animation_clock_time)),
                scale = 0.15,
                col = i%2 == 0 ? snake_red : snake_orange,
            )
        }

        for obst in state.obsts[:state.num_obsts] {
            color := [4]f32{0.0, 0.6, 0.2, 1}
            rv.draw_mesh(
                sphere, obst.pos, scale = obst.radius, col = color
            )
            color = [4]f32{0.2, 0.7, 0.3, 1}
            rv.draw_mesh(
                sphere, obst.pos * 1.1, scale = obst.radius, col = color
            )
        }

        rv.draw_mesh(
            sphere, state.berry.pos * 1.1, scale = 0.2 + 0.05 * rv.nsin(rv.get_time() * 2), col = rv.RED
        )
    }

    rv.set_draw_layer(1)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))

    screen_size := rv.get_screen_size()

    score := state.snake.num_segments / 2
    state.max_score = max(score, state.max_score)

    switch state.screen{
    case .Game:
        {
            rv.draw_text(
                ufmt.tprintf("SCORE %i", score),
                {screen_size.x * 0.5, screen_size.y - 30, 0.1},
                anchor = 0,
                scale = rv.remap_clamped(
                    state.berry_timer,
                    0, 0.4,
                    4, 2
                )
            )
            rv.draw_text(
                "Use WASD to move",
                {screen_size.x * 0.5, 24, 0.1},
                anchor = 0, scale = 2
            )
        }

    case .Death:
        {
            rv.draw_text(
                "GAME OVER!",
                {screen_size.x * 0.5, screen_size.y * 0.5, 0.1},
                anchor = 0, scale = 4, col = rv.RED,
            )
            rv.draw_text(
                ufmt.tprintf("SCORE %i", score),
                {screen_size.x * 0.5, screen_size.y * 0.65, 0.1},
                anchor = 0, scale = 2,
            )
            rv.draw_text(
                "Press SPACE to continue",
                {screen_size.x * 0.5, screen_size.y * 0.75, 0.1},
                anchor = 0, scale = 2, col = rv.LIGHT_GRAY,
            )
        }

        if rv.get_key_pressed(.Space) {
            state.screen = .Menu
        }

    case .Menu:
        {
            char_sprites := rv.draw_text(
                "SNAKE PLANET",
                {screen_size.x * 0.5, screen_size.y * 0.5 + math.sin_f32(rv.get_time() * 2) * 4, 0},
                anchor = 0, scale = 4, col = SNAKE_ORANGE,
            )

            // Animate individual characters
            for &inst, i in char_sprites {
                inst.pos.y += math.sin_f32(f32(i) * 0.7334 + rv.get_time()) * 10
                if i%2 == 0 {
                    inst.col = rv.pack_unorm8(SNAKE_RED)
                }
            }

            rv.draw_text(
                "Press SPACE to play", {screen_size.x * 0.5, screen_size.y * 0.75, 0.1},
                anchor = 0, scale = 2, col = rv.LIGHT_GRAY
            )
            rv.draw_text(
                ufmt.tprintf("HIGHSCORE %i", state.max_score), {screen_size.x * 0.5, screen_size.y * 0.65, 0.1},
                anchor = 0, scale = 2
            )
            rv.draw_text(
                "Music by Nolram. Thank you!", {screen_size.x * 0.5, screen_size.y - 32, 0.1},
                anchor = 0, scale = 2, col = rv.hex_color(0x06e4c2)
            )

            if rv.get_key_pressed(.Space) {
                new_game()
            }
        }
    }

    rv.draw_perf_scopes()

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, [3]f32{0.05, 0.1, 0.2}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    // rv.end_frame(false) // disable VSYNC

    return state
}

@export _module_desc := rv.Module_Desc {
    state_size = size_of(State),
    init = _init,
    update = _update,
    shutdown = _shutdown,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}
