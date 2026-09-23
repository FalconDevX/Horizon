// Shared by the planet shaders: hashing, gradient noise with derivatives and
// footprint-faded fBm. Include after any uniforms it does not declare itself.

// Orthonormal twist between octaves, so their lattices never line up.
const mat3 ROT = mat3(
	vec3(0.00, 0.80, 0.60),
	vec3(-0.80, 0.36, -0.48),
	vec3(-0.60, -0.48, 0.64)
);

uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

vec3 hash3(vec3 cell) {
	return vec3(pcg3d(uvec3(ivec3(cell)))) * (1.0 / 4294967295.0);
}

// Gradient noise with its analytic derivative: (value, d/dx, d/dy, d/dz).
vec4 noised(vec3 x) {
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec3 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

	vec3 ga = hash3(i + vec3(0.0, 0.0, 0.0)) * 2.0 - 1.0;
	vec3 gb = hash3(i + vec3(1.0, 0.0, 0.0)) * 2.0 - 1.0;
	vec3 gc = hash3(i + vec3(0.0, 1.0, 0.0)) * 2.0 - 1.0;
	vec3 gd = hash3(i + vec3(1.0, 1.0, 0.0)) * 2.0 - 1.0;
	vec3 ge = hash3(i + vec3(0.0, 0.0, 1.0)) * 2.0 - 1.0;
	vec3 gf = hash3(i + vec3(1.0, 0.0, 1.0)) * 2.0 - 1.0;
	vec3 gg = hash3(i + vec3(0.0, 1.0, 1.0)) * 2.0 - 1.0;
	vec3 gh = hash3(i + vec3(1.0, 1.0, 1.0)) * 2.0 - 1.0;

	float va = dot(ga, f - vec3(0.0, 0.0, 0.0));
	float vb = dot(gb, f - vec3(1.0, 0.0, 0.0));
	float vc = dot(gc, f - vec3(0.0, 1.0, 0.0));
	float vd = dot(gd, f - vec3(1.0, 1.0, 0.0));
	float ve = dot(ge, f - vec3(0.0, 0.0, 1.0));
	float vf = dot(gf, f - vec3(1.0, 0.0, 1.0));
	float vg = dot(gg, f - vec3(0.0, 1.0, 1.0));
	float vh = dot(gh, f - vec3(1.0, 1.0, 1.0));

	float value = va + u.x * (vb - va) + u.y * (vc - va) + u.z * (ve - va)
		+ u.x * u.y * (va - vb - vc + vd) + u.y * u.z * (va - vc - ve + vg)
		+ u.z * u.x * (va - vb - ve + vf) + (-va + vb + vc - vd + ve - vf - vg + vh) * u.x * u.y * u.z;

	vec3 derivative = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.z * (ge - ga)
		+ u.x * u.y * (ga - gb - gc + gd) + u.y * u.z * (ga - gc - ge + gg)
		+ u.z * u.x * (ga - gb - ge + gf) + (-ga + gb + gc - gd + ge - gf - gg + gh) * u.x * u.y * u.z
		+ du * (vec3(vb, vc, ve) - va
			+ u.yzx * vec3(va - vb - vc + vd, va - vc - ve + vg, va - vb - ve + vf)
			+ u.zxy * vec3(va - vb - ve + vf, va - vb - vc + vd, va - vc - ve + vg)
			+ u.yzx * u.zxy * (-va + vb + vc - vd + ve - vf - vg + vh));

	return vec4(value, derivative);
}

// 1 while an octave of this frequency spans several pixels, 0 once it would
// alias. `footprint` is one pixel's width in the same units as 1 / frequency.
float octave_fade(float frequency, float footprint) {
	return 1.0 - smoothstep(0.25, 0.6, frequency * footprint);
}

// Plain fBm value, footprint-faded.
float fbm(vec3 p, int octaves, float frequency, float footprint) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amplitude * noised(p * frequency).x * octave_fade(frequency, footprint);
		p = ROT * p;
		frequency *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

vec3 rotate_about(vec3 v, vec3 axis, float angle) {
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}
