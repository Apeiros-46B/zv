#version 410

in vec3 color;
out vec4 frag_color;

uniform vec2 scr_size;
uniform mat4 inv_proj;
uniform mat4 inv_view;

// to fix the fract on whole numbers bug
const float EPSILON = 0.000002;

struct Ray {
	vec3 origin;
	vec3 dir;
};

// takes position as vec3 in brick-local space
Ray getPrimaryRay(vec3 pos) {
	vec2 uv = (gl_FragCoord.xy / scr_size) * 2.0 - 1.0;
	vec4 targ = inv_proj * vec4(uv, 1.0, 1.0);
	vec4 dir = inv_view * vec4(normalize(targ.xyz / targ.w), 0.0);
	return Ray(pos, dir.xyz);
}

void main() {
	// TODO: need to add brick-local coordinates as a vertex attribute instead of using this broken fract setup
	// float x = brick_coord.x >= 0.999 ? 1.0 : fract(brick_coord.x + EPSILON);
	// float y = brick_coord.y >= 0.999 ? 1.0 : fract(brick_coord.y + EPSILON);
	// float z = brick_coord.z >= 0.999 ? 1.0 : fract(brick_coord.z + EPSILON);
	// vec3 f = (brick_coord_i) * 8.0;
	// // vec3 f = vec3(x, y, z) * 8.0;
	// // vec3 g = floor(f+EPSILON) / 8.0;
	// frag_color = vec4(f / 8.0, 1.0);
	frag_color = vec4(color, 1.0);
}
