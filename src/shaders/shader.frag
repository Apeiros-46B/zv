#version 430
#define FVTA_BRANCHLESS 0

layout(std430, binding = 1) readonly buffer voxels_buf {
	uint voxels[];
};

in vec2 uv;
in vec3 normal;
in vec3 pos_in_brick;
flat in uint brick_sparse;
flat in uint brick_ptr;

out vec4 frag_color;

const int FACE_XP = 0;
const int FACE_XN = 1;
const int FACE_YP = 2;
const int FACE_YN = 3;
const int FACE_ZP = 4;
const int FACE_ZN = 5;

const float EPSILON = 0.00002;

uniform vec2 scr_size;
uniform mat4 inv_proj;
uniform mat4 inv_view;

struct Ray {
	vec3 pos;
	vec3 dir;
};

// pos's value is undefined when hit is false.
struct Hit {
	bool hit;
	ivec3 pos;
	uint steps;
};

// takes position as vec3 in brick-local space
Ray getPrimaryRay(vec3 pos) {
	vec2 uv = (gl_FragCoord.xy / scr_size) * 2.0 - 1.0;
	vec4 targ = inv_proj * vec4(uv, 1.0, 1.0);
	vec4 dir = inv_view * vec4(normalize(targ.xyz / targ.w), 0.0);
	return Ray(pos, dir.xyz);
}

// TODO: half the brick is missing, and there are thin planes on the edges of the brick
uint getVoxel(ivec3 pos) {
	// index of the voxel within the brick
	uint idx = pos.x + 8 * pos.y + 64 * pos.z;
	if (idx > 511) {
		return 0;
	}
	// get the voxel pair that it resides in
	uint two_voxels = voxels[brick_ptr * 256 + (idx >> 1)];
	// extract the correct voxel from the pair
	return bitfieldExtract(two_voxels, int((idx & 1) * 16), 16);
}

bool outOfBrick(ivec3 pos, int ofs) {
	int lo = -1 + ofs;
	int hi = 8 - ofs;
	return pos.x < lo
	    || pos.x > hi
	    || pos.y < lo
	    || pos.y > hi
	    || pos.z < lo
	    || pos.z > hi;
}

Hit fvta(Ray primary) {
	vec3 sgn = sign(primary.dir);
	vec3 posf = trunc(primary.pos + EPSILON);

	ivec3 step = ivec3(sgn);
	ivec3 pos = ivec3(posf);

	vec3 dt = abs(length(primary.dir) / primary.dir);
	vec3 t_side = ((sgn * (posf - primary.pos)) + (sgn * 0.5) + 0.5) * dt;

	bvec3 mask;
	uint i;

	// 3 dimensions in an 8x8, worst case is that the ray traverses 8 in each dimension
	for (i = 0; i < 24; i++) {
		if (outOfBrick(pos + step, 0)) {
			break;
		}
		// 1 ofs is a jank fix to prevent ghost faces from appearing on top of empty voxels
		if (getVoxel(pos) != 0 && !outOfBrick(pos, 1)) {
			return Hit(true, pos, i);
		}

#if FVTA_BRANCHLESS
		mask = lessThanEqual(t_side.xyz, min(t_side.yzx, t_side.zxy));
		t_side += vec3(mask) * dt;
		pos += ivec3(mask) * step;
#else
		if (t_side.x < t_side.y) {
			if (t_side.x < t_side.z) {
				t_side.x += dt.x;
				pos.x += step.x;
				mask = bvec3(true, false, false);
			} else {
				t_side.z += dt.z;
				pos.z += step.z;
				mask = bvec3(false, false, true);
			}
		} else {
			if (t_side.y < t_side.z) {
				t_side.y += dt.y;
				pos.y += step.y;
				mask = bvec3(false, true, false);
			} else {
				t_side.z += dt.z;
				pos.z += step.z;
				mask = bvec3(false, false, true);
			}
		}
#endif
	}

	return Hit(false, pos, i);
}

void main() {
	if (uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	if (brick_sparse == 1) {
		Hit result = fvta(getPrimaryRay(pos_in_brick));
		if (!result.hit) {
			discard;
		}
		frag_color = vec4(result.pos / 8.0, 1.0);
		// frag_color = vec4(vec3(float(result.steps) / 24.0), 1.0);
	} else {
		frag_color = vec4(pos_in_brick / 8.0, 1.0);
	}
}
