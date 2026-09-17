#version 300 es
precision highp float;
precision highp int;

uniform sampler2D rv_instances;
uniform uint rv_instance_offset;
uniform mat4 rv_view_proj;

out vec3 v_world_pos;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_col;
out vec4 v_add_col;
flat out int v_tex_slice;

const int RV_PULL_TEX_W = RV_PULL_TEX_W;

vec4 pull(sampler2D t, int i) { return texelFetch(t, ivec2(i % RV_PULL_TEX_W, i / RV_PULL_TEX_W), 0); }

void main() {
    int iid = gl_InstanceID + int(rv_instance_offset);
    vec4 t0 = pull(rv_instances, iid*4+0);
    vec4 t1 = pull(rv_instances, iid*4+1);
    vec4 t2 = pull(rv_instances, iid*4+2);
    vec4 t3 = pull(rv_instances, iid*4+3);

    vec3 inst_pos = t0.xyz;
    vec4 icol    = unpackUnorm4x8(floatBitsToUint(t0.w)) * 4.0 - 2.0;
    vec3 mx = t1.xyz, my = t2.xyz;
    vec2 uv_min  = unpackUnorm2x16(floatBitsToUint(t1.w)) * 32.0 - 16.0;
    vec2 uv_size = unpackUnorm2x16(floatBitsToUint(t2.w)) * 32.0 - 16.0;
    vec4 add_col = unpackUnorm4x8(floatBitsToUint(t3.x)) * 4.0 - 2.0;
    int tex_slice = int(floatBitsToUint(t3.z)); // plain uint, not unorm

    vec2 local_uv  = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1));
    vec2 local_pos = local_uv * 2.0 - 1.0;
    vec3 wp = inst_pos + mx * local_pos.x + my * local_pos.y;

    v_world_pos = wp;
    v_normal    = cross(mx, my);
    v_uv        = uv_min + uv_size * local_uv;
    v_col       = icol;
    v_add_col   = add_col;
    v_tex_slice = tex_slice;
    gl_Position = rv_view_proj * vec4(wp, 1.0);
}
