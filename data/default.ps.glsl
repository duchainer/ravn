#version 300 es
precision highp float;

in vec3 v_world_pos;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_col;
in vec4 v_add_col;
flat in int v_tex_slice;

uniform sampler2DArray rv_tex;

out vec4 o;

void main() {
    vec3 normal = normalize(v_normal);
    if (!gl_FrontFacing) normal = -normal; // SV_IsFrontFace (unused downstream, kept for parity)

    vec4 col = v_add_col + v_col * texture(rv_tex, vec3(v_uv, float(v_tex_slice)));
    if (col.a < 0.001) discard;
    o = col;
}
