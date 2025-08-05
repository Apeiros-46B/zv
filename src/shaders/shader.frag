#version 410

in vec2 tex_coords;
out vec4 frag_color;

void main() {
	frag_color = vec4(tex_coords, 0, 1);
}
