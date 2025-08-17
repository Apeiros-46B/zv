#version 410

layout (location = 0) in vec3 in_pos;

out vec3 brick_coord;
flat out vec3 brick_coord_i;

uniform mat4 model;
uniform mat4 view;
uniform mat4 proj;

void main() {
	gl_Position = proj * view * model * vec4(in_pos, 1.0);
	brick_coord = in_pos;
	brick_coord_i = in_pos;
}
