#version 430

layout(std430, binding = 0) readonly buffer vert_pull_faces_buf {
	uint packed_face_data[];
};

out vec2 uv;
out vec3 normal;
out vec3 pos_in_brick;
flat out uint brick_sparse;
flat out uint brick_ptr;

uniform mat4 view;
uniform mat4 proj;
uniform vec3 chunk_ofs;

const vec3 face_verts_pos[] = vec3[] (
	vec3(0.0f, 0.0f, 0.0f),
	vec3(2.0f, 0.0f, 0.0f),
	vec3(0.0f, 0.0f, 2.0f)
);
const vec3 face_verts_pos_ccw[] = vec3[] (
	vec3(0.0f, 0.0f, 2.0f),
	vec3(2.0f, 0.0f, 0.0f),
	vec3(0.0f, 0.0f, 0.0f)
);

const uint FACE_XP = 0u;
const uint FACE_XN = 1u;
const uint FACE_YP = 2u;
const uint FACE_YN = 3u;
const uint FACE_ZP = 4u;
const uint FACE_ZN = 5u;

void main() {
	const uint face_data = packed_face_data[gl_VertexID / 3];
	const uint x = bitfieldExtract(face_data, 0, 4);
	const uint y = bitfieldExtract(face_data, 4, 4);
	const uint z = bitfieldExtract(face_data, 8, 4);
	const uint f = bitfieldExtract(face_data, 12, 4);

	// brick_loaded = bitfieldExtract(face_data, 16, 1);
	// brick_requested = bitfieldExtract(face_data, 17, 1);
	brick_sparse = bitfieldExtract(face_data, 18, 1);
	brick_ptr = bitfieldExtract(face_data, 19, 12);

	vec3 chunk_local_pos = vec3(x, y, z);
	vec3 brick_local_pos;
	
	switch (f) {
		case FACE_XP:
		case FACE_YN:
		case FACE_ZP:
	 		brick_local_pos = face_verts_pos[gl_VertexID % 3];
			break;
		case FACE_XN:
		case FACE_YP:
		case FACE_ZN:
			brick_local_pos = face_verts_pos_ccw[gl_VertexID % 3];
			break;
	}
	
	uv = brick_local_pos.xz;

	switch (f) {
		case FACE_XP:
			brick_local_pos.yz = brick_local_pos.xz;
			brick_local_pos.x = 1.0;
			normal = vec3(1.0, 0.0, 0.0);
			break;
		case FACE_XN:
			brick_local_pos.yz = brick_local_pos.xz;
			brick_local_pos.x = 0.0;
			normal = vec3(-1.0, 0.0, 0.0);
			break;
		case FACE_YP:
			brick_local_pos.y++;
			normal = vec3(0.0, 1.0, 0.0);
			break;
		case FACE_YN:
			normal = vec3(0.0, -1.0, 0.0);
			break;
		case FACE_ZP:
			brick_local_pos.xy = brick_local_pos.xz;
			brick_local_pos.z = 1.0;
			normal = vec3(0.0, 0.0, 1.0);
			break;
		case FACE_ZN:
			brick_local_pos.xy = brick_local_pos.xz;
			brick_local_pos.z = 0.0;
			normal = vec3(0.0, 0.0, -1.0);
			break;
	}

	pos_in_brick = brick_local_pos * 8.0;

	gl_Position = proj * view * vec4(brick_local_pos + chunk_local_pos + chunk_ofs, 1.0);
}
