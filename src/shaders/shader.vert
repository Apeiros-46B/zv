#version 430

layout(std430, binding = 0) readonly buffer vert_pull_buf {
	uint packed_mesh_data[];
};

out vec3 color;
out vec2 uv;

uniform mat4 model;
uniform mat4 view;
uniform mat4 proj;

const vec3 face_verts_pos[] = vec3[] (
	vec3(0.0f, 0.0f, 0.0f),
	vec3(2.0f, 0.0f, 0.0f),
	vec3(0.0f, 0.0f, 2.0f)
);

const int FACE_XP = 0;
const int FACE_XN = 1;
const int FACE_YP = 2;
const int FACE_YN = 3;
const int FACE_ZP = 4;
const int FACE_ZN = 5;

void main() {
	const uint data = packed_mesh_data[gl_VertexID / 3];
	const uint x = bitfieldExtract(data, 0, 8);
	const uint y = bitfieldExtract(data, 8, 8);
	const uint z = bitfieldExtract(data, 16, 8);
	const uint f = bitfieldExtract(data, 24, 8);
	const vec3 global_pos = vec3(x, y, z);

	vec3 local_pos = face_verts_pos[gl_VertexID % 3];
	uv = local_pos.xz;

	switch (f) {
		case FACE_XP:
			local_pos.yz = local_pos.xz;
			local_pos.x = 1.0;
			color = vec3(1.0, 0.0, 0.0);
			break;
		case FACE_XN:
			local_pos.yz = local_pos.xz;
			local_pos.x = 0.0;
			color = vec3(1.0, 1.0, 0.0);
			break;
		case FACE_YP:
			local_pos.y++;
			color = vec3(0.0, 1.0, 0.0);
			break;
		case FACE_YN:
			color = vec3(0.0, 1.0, 1.0);
			break;
		case FACE_ZP:
			local_pos.xy = local_pos.xz;
			local_pos.z = 1.0;
			color = vec3(0.0, 0.0, 1.0);
			break;
		case FACE_ZN:
			local_pos.xy = local_pos.xz;
			local_pos.z = 0.0;
			color = vec3(1.0, 0.0, 1.0);
			break;
	}

	gl_Position = proj * view * model * vec4(local_pos + global_pos, 1.0);
}