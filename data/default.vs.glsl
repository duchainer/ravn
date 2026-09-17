#version 300 es
precision highp float;
precision highp int;

uniform sampler2D rv_instances;
uniform sampler2D rv_verts;
uniform uint rv_instance_offset;
uniform mat4 rv_view_proj;

out vec3 v_world_pos;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_col;
out vec4 v_add_col;
flat out int v_tex_slice;

const int RV_PULL_TEX_W = RV_PULL_TEX_W; // backend substitutes the real value

vec4 pull(sampler2D t, int i) { return texelFetch(t, ivec2(i % RV_PULL_TEX_W, i / RV_PULL_TEX_W), 0); }

vec3 oct_decode(vec2 b01) { // matches rv_unpack_normal_unorm8's octahedral decode
    vec2 n = b01 * 2.0 - 1.0;
    vec3 nn = vec3(n.x, n.y, 1.0 - abs(n.x) - abs(n.y));
    float t = max(-nn.z, 0.0);
    nn.x += nn.x >= 0.0 ? -t : t;
    nn.y += nn.y >= 0.0 ? -t : t;
    return normalize(nn);
}

void main() {
    int iid = gl_InstanceID + int(rv_instance_offset);
    vec4 t0 = pull(rv_instances, iid*4+0);
    vec4 t1 = pull(rv_instances, iid*4+1);
    vec4 t2 = pull(rv_instances, iid*4+2);
    vec4 t3 = pull(rv_instances, iid*4+3);

    uint misc = floatBitsToUint(t2.w);
    int tex_slice = int(misc & 0xffu);
    int vert_offs = int((misc >> 8) & 0xffffffu);

    vec3 inst_pos = t0.xyz;
    vec4 icol     = unpackUnorm4x8(floatBitsToUint(t0.w)) * 4.0 - 2.0; // rv_unpack_signed_color_unorm8
    vec4 add_col  = unpackUnorm4x8(floatBitsToUint(t1.w)) * 4.0 - 2.0;
    vec3 mx = t1.xyz, my = t2.xyz, mz = t3.xyz;

    int vid = gl_VertexID + vert_offs;
    vec4 v0 = pull(rv_verts, vid*2+0);
    vec4 v1 = pull(rv_verts, vid*2+1);
    vec3 pos = v0.xyz;
    vec2 uv  = unpackUnorm2x16(floatBitsToUint(v0.w)) * 32.0 - 16.0; // rv_unpack_uv_unorm16
    uint nrm_b = floatBitsToUint(v1.x);
    vec3 nrm = oct_decode(vec2(float(nrm_b & 0xffu), float((nrm_b >> 8) & 0xffu)) / 255.0);
    vec4 vcol = unpackUnorm4x8(floatBitsToUint(v1.y));

    // world_pos = inst.pos + mul(pos, inst.mat)  (HLSL row-vector mul)
    mat3 m = mat3(mx.x, my.x, mz.x,
                  mx.y, my.y, mz.y,
                  mx.z, my.z, mz.z);
    vec3 wp = inst_pos + m * pos;

    v_world_pos = wp;
    v_normal    = nrm; // default.vs.hlsl overrides the adjugate-transformed normal with the raw one
    v_uv        = uv;
    v_col       = icol * vcol;
    v_add_col   = add_col;
    v_tex_slice = tex_slice;
    gl_Position = rv_view_proj * vec4(wp, 1.0);
}
