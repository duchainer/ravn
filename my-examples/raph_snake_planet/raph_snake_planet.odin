package ravn_raph_snake_planet_example

import "core:math/linalg"

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

main :: proc() {

}
