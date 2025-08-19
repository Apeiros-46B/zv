#version 410

in vec2 uv;
in vec3 normal;
in vec3 pos_in_brick;

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
};

// takes position as vec3 in brick-local space
Ray getPrimaryRay(vec3 pos) {
	vec2 uv = (gl_FragCoord.xy / scr_size) * 2.0 - 1.0;
	vec4 targ = inv_proj * vec4(uv, 1.0, 1.0);
	vec4 dir = inv_view * vec4(normalize(targ.xyz / targ.w), 0.0);
	return Ray(pos, dir.xyz);
}

// TODO: invesigate performance characteristics further. work on culling and reducing overdraw
bool getVoxel(ivec3 pos) {
	const int test = 0;
	// all tests were conducted with a maximized window, all of the pixels covered by bricks, a full chunk of bricks, and backface culling (no adjacent face culling)
	if (test == 0) { // sphere
		// OBSERVATIONS: around 1-2ms, 500fps. would more culling help? maybe investigate the vercidium method of culling instead of standard opengl cw/ccw (visible surface determination) also investigate overdraw
		vec3 posf = vec3(pos) - 3.5;
		return posf.x*posf.x + posf.y*posf.y + posf.z*posf.z < 4*4;
	} else if (test == 1) { // grid
		// OBSERVATIONS: around 2ms, 360fps. same as above
		if (pos.x == 8 || pos.y == 8 || pos.z == 8) {
			return false;
		}
		return pos.x % 2 == 0 && pos.y % 2 == 0 && pos.z % 2 == 0;
	} else if (test == 2) { // half height
		// OBSERVATIONS: around 1ms, 650fps. this is similar to the worst case on a real landscape where the player looks directly down at the ground from high up, only on a smaller scale
		return pos.y > 4;
	} else if (test == 3) { // empty
		// OBSERVATIONS: around 2ms, 336fps. worst case. this should not happen in a real situation because empty bricks will not be meshed.
		return false;
	} else if (test == 4) { // full
		// OBSERVATIONS: around 0.56ms, 1800fps. this is the best case, but can be better by attaching an attrib to "full" bricks and preventing marching entirely and simply rasterizing them
		return true;
	}
}

bool outOfBrick(ivec3 pos, ivec3 step) {
	ivec3 new = pos + step;
	return new.x < -1
		|| new.x > 8
		|| new.y < -1
		|| new.y > 8
		|| new.z < -1
		|| new.z > 8;
}

Hit fvta(Ray primary) {
	vec3 sgn = sign(primary.dir);
	vec3 posf = trunc(primary.pos + EPSILON);

	ivec3 step = ivec3(sgn);
	ivec3 pos = ivec3(posf);

	vec3 dt = abs(length(primary.dir) / primary.dir);
	vec3 t_side = ((sgn * (posf - primary.pos)) + (sgn * 0.5) + 0.5) * dt;

	bvec3 mask;

	// 3 dimensions in an 8x8, worst case is that the ray traverses 8 in each dimension
	for (int i = 0; i < 24; i++) {
		if (getVoxel(pos)) {
			return Hit(true, pos);
		}
		if (outOfBrick(pos, step)) {
			break;
		}
		mask = lessThanEqual(t_side.xyz, min(t_side.yzx, t_side.zxy));
		t_side += vec3(mask) * dt;
		pos += ivec3(mask) * step;
	}

	return Hit(false, pos);
}

void main() {
	if (uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	Hit result = fvta(getPrimaryRay(pos_in_brick));
	if (!result.hit) {
		discard;
	}
	frag_color = vec4(result.pos / 8.0, 1.0);
}
