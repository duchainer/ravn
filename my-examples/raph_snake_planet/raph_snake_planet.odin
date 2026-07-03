package ravn_raph_snake_planet_example

import "core:math/linalg"

import ufmt "../../base/ufmt"
import rv "../../."

state: ^State

State :: struct {
    obsts : [64]Obstacle,
    num_obsts: i32,
}

Obstacle :: struct {
    pos: [3]f32,
    rad: f32,
}


repel_from_obstacles :: proc(pos:[3] f32, rad: f32) -> [3]f32{
    pos := pos
    for obst in state.obsts[:state.num_obsts] {
        dist := linalg.length(pos - obst.pos)

        r := obst.rad + rad

        if dist > r {
            continue
        }

        // repel from obstacle
        dir := linalg.normalize0(pos - obst.pos)

        // stay on the surface of the planet
        pos = linalg.normalize0(pos + dir * (r-dist))
    }
    return pos
}

_init :: proc() {
    state = new(State)
    state.obsts[0] = Obstacle{0,0}
    state.num_obsts = 1
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> (data_ptr: rawptr) {
    if hot_state != nil {
        state :=  cast(^State)hot_state
        ufmt.eprintf("RAPH_DEBUG %v", (state)^)
    }
    return hot_state
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
