#version 410

layout (location = 0) in vec3 in_pos;
layout (location = 1) in vec3 instance_pos;
layout (location = 2) in int instance_face;

const int FACE_XP = 0;
const int FACE_XN = 1;
const int FACE_YP = 2;
const int FACE_YN = 3;
const int FACE_ZP = 4;
const int FACE_ZN = 5;

out vec3 color;

uniform mat4 model;
uniform mat4 view;
uniform mat4 proj;

void main() {
	vec3 local_pos = in_pos;

	switch (instance_face) {
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

	gl_Position = proj * view * model * vec4(local_pos + instance_pos, 1.0);
}
