#version 410

layout(location = 0) in vec3 attr_pos;
layout(location = 1) in vec3 attr_color;
out vec3 vert_color;

void main() {
	gl_Position = vec4(attr_pos.x, attr_pos.y, attr_pos.z, 1.0);
	vert_color = attr_color;
}
