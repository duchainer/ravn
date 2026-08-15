package raph_physics

import "base:intrinsics"
import "core:math/linalg"
import "base:runtime"
import "../../base"
import "../../geometry"
import "../../bvh"

import "../../collision/"

// Adapted from collide_sphere_swept from ravn/collision/collision.odin commit
// Immediate-mode continous shape-swept collision
// NOTE: Per-shape restitution is now looked up from sweep.shape index
raph_collide_sphere_swept :: proc(
    pos:            [3]f32,
    vel:            [3]f32,
    rad:            f32,
    ignore_layers:  bit_set[0..<collision.NUM_LAYERS] = {},
    max_sweeps      := 4,
    restitution     := f32(0.6),
    impact_threshold:= f32(0.3),
) -> (new_pos: [3]f32, new_vel: [3]f32) {
    pos := pos
    vel := vel

    step := collision.get_step_state()
    range := linalg.length(vel * step.delta)

    overlap_pos: [3]f32
    contacts: []collision.Contact

    for i in 0..<max_sweeps {
        // overlap_pos, vel, contacts = collide_sphere(pos, vel, rad, ignore_layers, allocator = context.temp_allocator)
        // if len(contacts) > 0 {
        //     pos = overlap_pos
        // }

        pos, vel = _solve_sphere_contacts_position_based(pos, vel, rad = rad, allocator = context.temp_allocator)

        dir := linalg.normalize0(vel)

        // if dir == 0 || range < rad*0.0 {
        //     pos += dir * range
        //     return pos, vel
        // }

        sweep, sweep_hit := collision.sweep_sphere(pos, move = dir, rad = rad, range = range, ignore_layers = ignore_layers)

        if !sweep_hit {
            pos += dir * range
            return pos, vel
        }

        pos += dir * max(sweep.t - 0.001, 0.0)
        range -= sweep.t

        // Bounce off the collision surface with per-shape restitution, but only
        // on real impacts (not gentle resting contacts which would cause jitter)
        shape_restitution := restitution
        if sweep.shape >= 0 {
            if shape, shape_ok := collision.get_shape(sweep.shape); shape_ok {
                shape_restitution = shape.restitution
            }
        }
        vn := linalg.dot(vel, sweep.normal)
        if vn < -impact_threshold {
            vel -= sweep.normal * vn * (1 + shape_restitution)
        } else if vn < 0 {
            // Resting contact: zero out any velocity pushing into the surface
            vel -= sweep.normal * vn
        }

        if range <= 0.001 {
            break
        }
    }

    return pos, vel

    // Hacky
    _solve_sphere_contacts_position_based :: proc(
        pos:            [3]f32,
        vel:            [3]f32,
        rad:            f32,
        max_contacts    := 8,
        max_triangles   := 32,
        allocator       := context.temp_allocator,
    ) -> (new_pos: [3]f32, new_vel: [3]f32) {
        contacts := collision.find_contacts_sphere(
            pos = pos,
            rad = rad,
            max_contacts = max_contacts,
            max_triangles = max_triangles,
            allocator = allocator,
        )

        new_pos = pos
        for contact in contacts {
            new_pos += contact.normal * max(0.0, -contact.separation * 0.5)
        }

        new_vel = vel

        return new_pos, new_vel
    }
}
