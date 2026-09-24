#[compute]
#version 450

// GPU heightmap bake for PlanetTerrain. One invocation per texel of the six
// cube faces (same frames and texel layout as planet_terrain.gd). Two passes
// over the same buffer, picked by the push constant:
//   0 - raw height per texel, and its running min/max (atomics on floats
//       mapped to order-preserving uints);
//   1 - rescale to 0..1 from that min/max, and add each texel's solid angle
//       to a height histogram, from which the CPU places sea level.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Mirror of PlanetTerrain.HISTOGRAM_BINS. A fixed size, not .length(): the
// D3D12 backend cannot translate runtime array lengths.
const uint HISTOGRAM_BINS = 1024u;

layout(set = 0, binding = 0, std430) restrict buffer Heights {
	float heights[];
};

layout(set = 0, binding = 1, std430) restrict buffer Stats {
	uint low;
	uint high;
	uint pad0;
	uint pad1;
	uint histogram[HISTOGRAM_BINS];
};

// Mirrors the settings array built in PlanetTerrain._dispatch().
layout(set = 0, binding = 2, std430) restrict readonly buffer Params {
	vec4 shape;        // x kind, y face size, z frequency, w gas bands
	vec4 pole;         // xyz spin axis
	vec4 storm_center; // xyz centre, w width
	vec4 storm_east;   // xyz, w 1 = bright spot
	vec4 storm_north;  // xyz, w storm strength (0 = no storm)
	vec4 recipe;       // shared: x continent warp, y/z mountain-belt thresholds, w ridge sharpness
	vec4 detail[4];    // the kind's own knobs, rolled per seed - see each branch of raw_height()
	// Placed features (Occult eyes, Swirl spirals, Rings, Fractal massifs,
	// Meridian lines) - see PlanetTerrain.sigil_arrays(). Sizes mirror
	// PlanetTerrain.MAX_SIGILS. What style and extra mean depends on the kind;
	// each branch below says.
	vec4 sigil_info;       // x count
	vec4 sigils[24];       // xyz centre, w angular radius
	vec4 sigil_styles[24];
	vec4 sigil_extra[24];
};

layout(push_constant, std430) uniform Push {
	uint pass;
	uint seed;
	uint pad2;
	uint pad3;
} push;

// Mirror of PlanetTerrain.Kind.
const int TERRAN = 1;
const int DESERT = 2;
const int VOLCANIC = 3;
const int ICE = 4;
const int BARREN = 5;
const int TOXIC = 6;
const int GAS_GIANT = 7;
const int ICE_GIANT = 8;
const int FROZEN = 9;
const int SLIME = 10;
const int OCCULT = 11;
const int GLOOM = 12;
const int BLOOM = 13;
const int OASIS = 14;
const int LOTUS = 15;
const int SWIRL = 16;
const int RINGS = 17;
const int QUAKE = 18;
const int FRACTAL = 19;
const int MERIDIAN = 20;

// Weights are fixed-point in the histogram; 256 keeps a whole 1024 map in a
// uint even if every texel lands in one bin.
const float HISTOGRAM_SCALE = 256.0;

// Orthonormal twist between octaves, so their lattices never line up.
const mat3 ROT = mat3(
	0.00, 0.80, 0.60,
	-0.80, 0.36, -0.48,
	-0.60, -0.48, 0.64
);

const vec3 FACE_FORWARD[6] = vec3[](
	vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0), vec3(0, 0, 1), vec3(0, 0, -1)
);
const vec3 FACE_RIGHT[6] = vec3[](
	vec3(0, 0, -1), vec3(0, 0, 1), vec3(1, 0, 0), vec3(1, 0, 0), vec3(1, 0, 0), vec3(-1, 0, 0)
);
const vec3 FACE_UP[6] = vec3[](
	vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 0, -1), vec3(0, 0, 1), vec3(0, 1, 0), vec3(0, 1, 0)
);

// ---- hashing and noise ----------------------------------------------------

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

// 0..1 per component, for an integer lattice point.
vec3 hash3(vec3 cell) {
	uvec3 h = pcg3d(uvec3(ivec3(cell)) ^ uvec3(push.seed, push.seed * 747796405u, push.seed ^ 0x9E3779B9u));
	return vec3(h) * (1.0 / 4294967295.0);
}

// The planet shader's hash (planet_noise.gdshaderinc): not seeded per
// planet, for patterns the two shaders must place identically (Quake's scars).
vec3 hash3_plain(vec3 cell) {
	return vec3(pcg3d(uvec3(ivec3(cell)))) * (1.0 / 4294967295.0);
}

// Gradient noise with its analytic derivative: (value, d/dx, d/dy, d/dz).
// Value is roughly -0.7..0.7.
vec4 noised(vec3 x) {
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec3 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

	vec3 ga = hash3(i + vec3(0, 0, 0)) * 2.0 - 1.0;
	vec3 gb = hash3(i + vec3(1, 0, 0)) * 2.0 - 1.0;
	vec3 gc = hash3(i + vec3(0, 1, 0)) * 2.0 - 1.0;
	vec3 gd = hash3(i + vec3(1, 1, 0)) * 2.0 - 1.0;
	vec3 ge = hash3(i + vec3(0, 0, 1)) * 2.0 - 1.0;
	vec3 gf = hash3(i + vec3(1, 0, 1)) * 2.0 - 1.0;
	vec3 gg = hash3(i + vec3(0, 1, 1)) * 2.0 - 1.0;
	vec3 gh = hash3(i + vec3(1, 1, 1)) * 2.0 - 1.0;

	float va = dot(ga, f - vec3(0, 0, 0));
	float vb = dot(gb, f - vec3(1, 0, 0));
	float vc = dot(gc, f - vec3(0, 1, 0));
	float vd = dot(gd, f - vec3(1, 1, 0));
	float ve = dot(ge, f - vec3(0, 0, 1));
	float vf = dot(gf, f - vec3(1, 0, 1));
	float vg = dot(gg, f - vec3(0, 1, 1));
	float vh = dot(gh, f - vec3(1, 1, 1));

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

// Octaves that still land above about a texel, for a base frequency.
int octaves_for(float base_frequency, int limit) {
	float texels = shape.y * 0.35;
	return clamp(int(log2(max(texels / base_frequency, 1.0))) + 1, 1, limit);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amplitude * noised(p).x;
		p = ROT * p * 2.02;
		amplitude *= 0.5;
	}
	return sum;
}

// fBm whose octaves fade wherever the ground below them is already steep:
// slopes stay smooth and gullied, flats and crests pick up the detail. It is
// the cheap stand-in for hydraulic erosion (after Inigo Quilez).
float fbm_eroded(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	vec3 slope = vec3(0.0);
	for (int i = 0; i < octaves; i++) {
		vec4 n = noised(p);
		slope += n.yzw;
		sum += amplitude * n.x / (1.0 + dot(slope, slope));
		p = ROT * p * 2.02;
		amplitude *= 0.5;
	}
	return sum;
}

// Ridged multifractal (Musgrave): sharp crests, and each octave weighted by
// the one before so detail gathers on the ridges, not in the valleys. 0..1.
float ridged(vec3 p, int octaves) {
	float sum = 0.0;
	float total = 0.0;
	float amplitude = 0.5;
	float weight = 1.0;
	for (int i = 0; i < octaves; i++) {
		float r = 1.0 - abs(noised(p).x * recipe.w);
		r *= r * weight;
		weight = clamp(r * 1.8, 0.0, 1.0);
		sum += r * amplitude;
		total += amplitude;
		p = ROT * p * 2.03;
		amplitude *= 0.5;
	}
	return sum / total;
}

// Worley cells: (distance to nearest point, to second nearest, nearest's roll).
vec3 worley(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float f1 = 8.0;
	float f2 = 8.0;
	float roll = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(x, y, z);
				vec3 h = hash3(cell + offset);
				vec3 r = offset + 0.5 + (h - 0.5) * 0.9 - local;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					roll = hash3(cell + offset + vec3(0.0, 0.0, 4099.0)).x;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}

	return vec3(sqrt(f1), sqrt(f2), roll);
}

// ---- terrain --------------------------------------------------------------

// Crater profile from the distance to its centre: a bowl inside the radius
// and a raised rim around it, flat further out.
float crater_spiked(float d0, float radius, float rim_height, float spike);
float crater_layer_spiked(vec3 p, float empty_share, float rim_height, float spikes);

float crater(float d0, float radius, float rim_height) {
	return crater_spiked(d0, radius, rim_height, 1.0);
}

// As crater(), the rim scaled by `spike` (1 = smooth; spikier rims pass a
// per-direction factor that jumps up in narrow teeth).
float crater_spiked(float d0, float radius, float rim_height, float spike) {
	float rim = exp(-pow((d0 - radius) / (radius * 0.22), 2.0)) * rim_height * spike;
	if (d0 < radius) {
		float t = d0 / radius;
		return -(1.0 - t * t) * 0.8 + rim;
	}
	return rim;
}

// One crater layer: a crater around every Worley point, each cell rolling
// its own size - or, below `empty_share`, that it has none. Summed over the
// neighbouring cells, not taken from the nearest one alone, so nothing jumps
// along the cell borders.
float crater_layer(vec3 p, float empty_share, float rim_height) {
	return crater_layer_spiked(p, empty_share, rim_height, 0.0);
}

// As crater_layer(), with `spikes` (0 = none) raising the rims into jagged
// teeth: tall, narrow and irregular all the way round.
float crater_layer_spiked(vec3 p, float empty_share, float rim_height, float spikes) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float sum = 0.0;
	float filled = max(1.0 - empty_share, 1e-3);

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(x, y, z);
				float roll = hash3(cell + offset + vec3(0.0, 0.0, 4099.0)).x;
				if (roll < empty_share) {
					continue;
				}
				vec3 r = offset + 0.5 + (hash3(cell + offset) - 0.5) * 0.9 - local;
				float spike = 1.0;
				if (spikes > 0.0) {
					float teeth = noised(normalize(r) * 7.0 + (cell + offset) * 3.1).x * 1.6 + 0.3;
					spike += spikes * pow(clamp(teeth, 0.0, 1.0), 3.0);
				}
				sum += crater_spiked(length(r), mix(0.2, 0.5, (roll - empty_share) / filled), rim_height, spike);
			}
		}
	}

	return sum;
}

// Sinkholes: rimless, flat-floored pits with steep walls, in a `density`
// share of the cells. 0..1 deep.
float pit_layer(vec3 p, float density) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float depth = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(x, y, z);
				float roll = hash3(cell + offset + vec3(0.0, 0.0, 7919.0)).x;
				if (roll > density) {
					continue;
				}
				vec3 r = offset + 0.5 + (hash3(cell + offset + vec3(0.0, 17.0, 0.0)) - 0.5) * 0.9 - local;
				float radius = mix(0.15, 0.4, roll / max(density, 1e-3));
				depth = max(depth, 1.0 - smoothstep(0.55, 1.0, length(r) / radius));
			}
		}
	}

	return depth;
}

// Lone steep peaks in a `density` share of the cells, each its own height;
// `sharpness` is the cone's power (higher = needle-like). 0..1.
float peak_layer(vec3 p, float density, float sharpness) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float height = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(x, y, z);
				vec3 roll = hash3(cell + offset + vec3(0.0, 0.0, 6143.0));
				if (roll.x > density) {
					continue;
				}
				vec3 r = offset + 0.5 + (hash3(cell + offset + vec3(0.0, 31.0, 0.0)) - 0.5) * 0.8 - local;
				float radius = mix(0.35, 0.6, roll.x / max(density, 1e-3));
				float cone = pow(max(1.0 - length(r) / radius, 0.0), sharpness);
				height = max(height, cone * mix(0.6, 1.0, roll.y));
			}
		}
	}

	return height;
}

// Long wandering fractures, like Europa's lineae: the zero lines of warped
// noise at two scales, not the closed cells a Worley pattern gives (those
// read as a football). x = the groove, y = the raised flanks either side.
vec2 fractures(vec3 p, float width, float wander) {
	vec3 w = vec3(fbm(p * 0.5 + 5.0, 3), fbm(p * 0.5 + 9.0, 3), fbm(p * 0.5 + 13.0, 3)) * wander;
	float a = abs(noised(p + w).x);
	float b = abs(noised(p * 2.3 + w * 1.7 + 31.0).x);
	float groove = max(1.0 - smoothstep(0.0, width, a), (1.0 - smoothstep(0.0, width * 0.7, b)) * 0.6);
	float flank = max(
		smoothstep(width * 0.6, width * 1.2, a) * (1.0 - smoothstep(width * 1.2, width * 2.4, a)),
		smoothstep(width * 0.4, width * 0.85, b) * (1.0 - smoothstep(width * 0.85, width * 1.7, b)) * 0.6
	);
	return vec2(groove, flank);
}

// Dry riverbeds: wandering valleys along warped noise zero lines, with a finer
// set of tributaries. 0..1 channel depth.
float channels(vec3 p, float width, float wander) {
	vec3 w = vec3(fbm(p * 0.6 + 21.0, 3), fbm(p * 0.6 + 27.0, 3), fbm(p * 0.6 + 33.0, 3)) * wander;
	float bed = 1.0 - smoothstep(0.0, width, abs(noised(p + w).x));
	float tributary = 1.0 - smoothstep(0.0, width * 0.5, abs(noised(p * 2.7 + w * 1.4 + 57.0).x));
	return max(bed, tributary * 0.45);
}

// ---- occult eyes and tentacles ----------------------------------------------
// eye_lens(), eye_parts() and sigil_frame() are mirrored in
// planet_terrain.gdshader, which stains and lights what is carved here.

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// A sigil's own frame: radius-1 units, upright relative to the pole.
vec2 sigil_frame(vec3 d, vec4 s, float angle) {
	vec3 up = abs(dot(pole.xyz, s.xyz)) < 0.95 ? pole.xyz : vec3(1.0, 0.0, 0.0);
	vec3 east = normalize(cross(up, s.xyz));
	vec3 north = cross(s.xyz, east);
	// Azimuthal equidistant: |q| is the true angle from the centre, so big
	// features keep their shape out to the rim.
	vec2 flat_q = vec2(dot(d, east), dot(d, north));
	float across = length(flat_q);
	float arc = acos(clamp(dot(d, s.xyz), -1.0, 1.0));
	vec2 q = (across > 1e-6 ? flat_q * (arc / across) : flat_q) / s.w;
	return mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * q;
}

// Signed distance to the almond: the overlap of two circles, 1.8 x 0.9.
float eye_lens(vec2 q) {
	return max(length(q - vec2(0.0, -0.675)) - 1.125, length(q - vec2(0.0, 0.675)) - 1.125);
}

// x = how far inside the almond (1 deep in, 0 at the rim), y = pupil,
// z = drips running down out of the eye, w = iris ring.
vec4 eye_parts(vec2 q, vec4 style) {
	float inside = 1.0 - smoothstep(-0.3, 0.0, eye_lens(q));

	float pupil_d;
	if (style.y < 0.5) {
		pupil_d = length(q) - 0.13;
	} else if (style.y < 1.5) {
		pupil_d = max(abs(q.x) - 0.05, abs(q.y) - 0.3);
	} else {
		pupil_d = abs(q.x) + abs(q.y) * 0.6 - 0.16;
	}
	float pupil = 1.0 - smoothstep(-0.03, 0.04, pupil_d);

	float drips_d = 1e3;
	int count = int(style.z);
	for (int i = 0; i < 5; i++) {
		if (i >= count) {
			break;
		}
		float x = (float(i) - float(count - 1) * 0.5) * 0.28;
		float length_i = 0.35 + 0.3 * fract(sin(float(i) * 12.9898 + style.x * 7.0) * 43758.5453);
		vec2 top = vec2(x, -0.3);
		vec2 end = vec2(x, -0.3 - length_i);
		drips_d = min(drips_d, min(sd_segment(q, top, end) - 0.04, length(q - end) - 0.08));
	}
	float drips = 1.0 - smoothstep(-0.02, 0.05, drips_d);

	float iris = exp(-pow((length(q) - 0.3) / 0.05, 2.0));
	return vec4(inside, pupil, drips, iris);
}

// The crater itself: a bowl in the almond with a raised rim, a hood ridge
// arching over it, a low iris ring, a pit for the pupil and grooves for drips.
float eye_relief(vec2 q, vec4 style) {
	vec4 e = eye_parts(q, style);
	float rim = exp(-pow(eye_lens(q) / 0.1, 2.0));
	float hood = exp(-pow((length(q - vec2(0.0, -0.35)) - 0.95) / 0.07, 2.0)) * smoothstep(0.2, 0.4, q.y);
	return rim * 0.5 + hood * 0.35 + e.w * 0.2 - e.x * 0.6 - e.y * 0.45 - e.z * 0.3;
}

// Mirrored in planet_terrain.gdshader, which tints the ridges.
// Tentacles sprawling out of a sigil: ridges from `start` to the reach that
// curl as they go (t.y), wobble, taper to a point and carry a row of sucker
// bumps. q in sigil radii; t = (count, curl, reach, width). 0..1.
float tentacle_ridges(vec2 q, vec4 t, float start, float phase) {
	float r = length(q);
	if (r < start || r > t.z) {
		return 0.0;
	}
	float theta = atan(q.y, q.x);
	float along = (r - start) / max(t.z - start, 1e-3);
	float height = 0.0;

	int count = int(t.x);
	for (int k = 0; k < 8; k++) {
		if (k >= count) {
			break;
		}
		float fk = float(k);
		float base = phase + fk * 6.2831853 / float(count) + 0.35 * sin(fk * 5.1 + phase);
		float path = base + t.y * along * along + 0.25 * sin(along * 7.0 + fk * 2.3);
		float off_path = abs(mod(theta - path + 3.14159265, 6.2831853) - 3.14159265) * r;
		float width = t.w * (1.0 - along) + 0.015;
		// Rounded, like a limb lying on the ground, not a knife-edge crease.
		float across = clamp(off_path / width, 0.0, 1.0);
		float ridge = sqrt(1.0 - across * across);
		float suckers = 0.88 + 0.12 * sin(along * 55.0 + fk);
		height = max(height, ridge * sqrt(1.0 - along) * suckers);
	}
	return height;
}

// Every eye crater and tentacle nest at dir, summed.
float occult_marks(vec3 dir, float tentacle_height) {
	float marks = 0.0;
	for (int i = 0; i < 24; i++) {
		if (float(i) >= sigil_info.x) {
			break;
		}
		vec4 s = sigils[i];
		vec4 style = sigil_styles[i];
		vec4 t = sigil_extra[i];
		if (dot(dir, s.xyz) < cos(min(s.w * (t.z + 0.3), 3.0))) {
			continue;
		}
		vec2 q = sigil_frame(dir, s, style.x);
		bool has_eye = style.y > -0.5;
		if (has_eye) {
			marks += eye_relief(q, style) * style.w;
		} else {
			// A tentacle nest: a knot in the middle for them to grow from.
			marks += exp(-dot(q, q) / 0.09) * 0.6;
		}
		marks += tentacle_ridges(q, t, has_eye ? 0.95 : 0.2, style.x * 3.0 + float(i) * 1.7)
			* tentacle_height;
	}
	return marks;
}

// ---- other placed features -------------------------------------------------
// swirl_parts() and ring_parts() are mirrored in planet_terrain.gdshader,
// which colours them.

// A snail-shell swirl in its own frame (radius 1): an Archimedean spiral with
// `style.z` interleaved arms (even, so raised and sunken arms alternate).
// x = inside (fading at the rim), y = which arm (0 / 1), z = groove between
// arms, w = dome across an arm.
vec4 swirl_parts(vec2 q, vec4 style) {
	float r = length(q);
	float inside = 1.0 - smoothstep(0.85, 1.0, r);
	if (inside <= 0.0) {
		return vec4(0.0);
	}
	float theta = atan(q.y, q.x) * style.w;
	float u = r * style.y + style.z * theta / 6.2831853;
	float f = fract(u);
	float groove = 1.0 - smoothstep(0.0, 0.08, min(f, 1.0 - f));
	return vec4(inside, mod(floor(u), 2.0), groove, sin(f * 3.14159265));
}

// Onion rings in their own frame (radius 1): `style.y` concentric rings of
// width `style.z` (share of their spacing), each broken in `style.w` places
// by gaps `extra.x` of each segment wide, at its own random turn.
// x = on a ring, y = ring index (0, 1, 2...), z = inside the set.
vec3 ring_parts(vec2 q, vec4 style, vec4 extra) {
	float r = length(q);
	if (r > 1.0) {
		return vec3(0.0);
	}
	float x = r * style.y;
	float index = floor(x);
	float band = 1.0 - smoothstep(style.z * 0.5 - 0.06, style.z * 0.5, abs(fract(x) - 0.5));
	float phase = fract(sin((index + 1.0) * 12.9898 + style.x * 7.0) * 43758.5453);
	float along = fract(atan(q.y, q.x) / 6.2831853 * style.w + phase);
	band *= smoothstep(extra.x, extra.x + 0.04, along);
	return vec3(band, index, 1.0 - smoothstep(0.95, 1.0, r));
}

// Height of a Mandelbrot massif in its own frame (radius 1). The set's body
// is domed: each bulb rises from about 0.55 at its rim to a peak at 1 where
// its orbit settles nearest zero. Outside it the smoothed escape time rises
// along the filaments, so they stand as lower ridges.
// style.y = zoom, style.zw = view offset.
float mandel_height(vec2 q, vec4 style) {
	vec2 c = vec2(-0.75 + style.z, style.w) + q * style.y;
	vec2 z = vec2(0.0);
	vec2 last = z;
	float n = 0.0;
	const int ITERATIONS = 64;
	for (int i = 0; i < ITERATIONS; i++) {
		last = z;
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
		if (dot(z, z) > 256.0) {
			break;
		}
		n += 1.0;
	}
	float fade = 1.0 - smoothstep(0.9, 1.3, length(q));
	if (n >= float(ITERATIONS)) {
		float settle = 0.5 * (length(z) + length(last));
		// smoothstep rounds the crown; a plain ramp comes to a cone point.
		return (1.0 - 0.45 * smoothstep(0.0, 1.0, settle * 2.0)) * fade;
	}
	float escape = n - log2(log2(dot(z, z))) + 4.0;
	return 0.5 * pow(clamp(escape / float(ITERATIONS), 0.0, 1.0), 0.6) * fade;
}

// A Rings island, in its own radii: the plateau's edge falls from x to y,
// the moat climbs back out from z to w.
const vec4 ISLAND_MOAT = vec4(1.02, 1.2, 1.5, 1.85);

// Quake scars, carved: a bowl where the planet shader draws each scar, found
// the same way (the planet shader's hash and `shift`), so rings and spokes
// sit on the hole. scale, density, size, shift as quakes_at() there.
float quake_holes(vec3 dir, float scale, float density, float size_share, float shift) {
	vec3 p = dir * scale + vec3(shift);
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float hole = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 h = hash3_plain(cell + o + vec3(0.0, 0.0, 577.0));
				if (h.x > density) {
					continue;
				}
				vec3 off = o + 0.5 + (hash3_plain(cell + o + vec3(0.0, 57.0, 0.0)) - 0.5) * 0.7 - local;
				float t = length(off) / (size_share * mix(0.7, 1.2, h.y));
				if (t < 1.0) {
					hole = max(hole, 1.0 - t * t);
				}
			}
		}
	}
	return hole;
}

// Relief of every placed feature at dir for Swirl, Rings and Fractal.
float feature_relief(vec3 dir, int kind) {
	float relief = 0.0;
	for (int i = 0; i < 24; i++) {
		if (float(i) >= sigil_info.x) {
			break;
		}
		vec4 s = sigils[i];
		vec4 extra = sigil_extra[i];
		// A Rings island reaches out to its moat.
		float reach = kind == RINGS && extra.z > 0.5 ? ISLAND_MOAT.w : 1.4;
		if (dot(dir, s.xyz) < cos(min(s.w * reach, 3.0))) {
			continue;
		}
		vec4 style = sigil_styles[i];
		vec2 q = sigil_frame(dir, s, style.x);
		if (kind == SWIRL) {
			// Arm 0 a raised shell ridge, arm 1 a pit of the same shape.
			vec4 w = swirl_parts(q, style);
			relief += w.x * w.w * mix(0.6, -extra.y, w.y) * extra.x;
		} else if (kind == RINGS) {
			relief += ring_parts(q, style, extra).x * extra.y;
			if (extra.z > 0.5) {
				// An island: the ring set raised on a plateau, ringed by a moat
				// deep enough to be the planet's lowest ground, so the sea
				// fills it and nothing else.
				float r = length(q);
				relief += extra.w * (1.0 - smoothstep(ISLAND_MOAT.x, ISLAND_MOAT.y, r));
				relief -= 2.4 * smoothstep(ISLAND_MOAT.x, ISLAND_MOAT.y, r) * (1.0 - smoothstep(ISLAND_MOAT.z, ISLAND_MOAT.w, r));
			}
		} else {
			relief = max(relief, mandel_height(q, style));
		}
	}
	return relief;
}

// Meridian lines: mountain ridges and carved valleys running pole to pole,
// each on a course of its own, so they wander, lean and cross. Line i:
//   style = (longitude at the equator, swing (radians of longitude), swings
//            from pole to pole, phase)
//   extra = (course: 0 straight, 1 curving, 2 zig-zag; lean (radians of
//            longitude from pole to pole); half-width (radians); height, < 0
//            a valley)
// They taper out toward the poles, where every line meets.
float meridian_relief(vec3 dir) {
	vec3 axis = pole.xyz;
	vec3 helper = abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 e1 = normalize(cross(axis, helper));
	vec3 e2 = cross(axis, e1);
	float s = clamp(dot(dir, axis), -1.0, 1.0);
	float t = asin(s) / 1.5707963;
	float ring = sqrt(max(1.0 - s * s, 0.0));
	float lon = atan(dot(dir, e2), dot(dir, e1));
	float polar = 1.0 - smoothstep(0.72, 0.95, abs(t));
	if (polar <= 0.0) {
		return 0.0;
	}
	// Crests break into peaks and saddles; floors stay smoother.
	float crest = 0.45 + 0.8 * ridged(dir * 7.0 + 11.0, octaves_for(7.0, 5));
	float floor_rough = 0.85 + 0.3 * fbm(dir * 5.0 + 23.0, 3);

	float relief = 0.0;
	for (int i = 0; i < 24; i++) {
		if (float(i) >= sigil_info.x) {
			break;
		}
		vec4 st = sigil_styles[i];
		vec4 ex = sigil_extra[i];
		float x = st.z * 0.5 * t + st.w;
		float wave = 0.0;
		float slope = 0.0;
		if (ex.x > 1.5) {
			float f = fract(x + 0.25);
			wave = 1.0 - 4.0 * abs(f - 0.5);
			slope = f < 0.5 ? 4.0 : -4.0;
		} else if (ex.x > 0.5) {
			wave = sin(6.2831853 * x);
			slope = 6.2831853 * cos(6.2831853 * x);
		}
		float centre = st.x + ex.y * t + st.y * wave;
		float d_lon = mod(lon - centre + 3.14159265, 6.2831853) - 3.14159265;
		// Distance across the line, not along the parallel, so the slanted legs
		// of a zig-zag come out as wide as the rest.
		float lean = (ex.y + st.y * slope * st.z * 0.5) / 1.5707963 * ring;
		float across = abs(d_lon) * ring / sqrt(1.0 + lean * lean);
		// The width breathes along the line.
		float width = ex.z * (0.75 + 0.5 * (noised(vec3(t * 5.0, float(i) * 1.7, 0.5)).x * 0.5 + 0.5));
		float bump = exp(-(across * across) / (width * width));
		relief += ex.w * bump * (ex.w > 0.0 ? crest : floor_rough);
	}
	return relief * polar;
}

// Giant four-petal flowers on lily pads, one per cell in a `density` share of
// cells: a pad disc just above the future waterline, and petals rising from
// their tips to the flower's centre. `roundness` < 1 fattens the petals.
float flower_layer(vec3 dir, float scale, float density, float roundness) {
	vec3 helper = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(helper, dir));
	vec3 b = cross(dir, t);
	vec3 p = dir * scale + 17.0;
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float height = -1.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(x, y, z);
				vec3 roll = hash3(cell + o + vec3(0.0, 0.0, 3301.0));
				if (roll.x > density) {
					continue;
				}
				vec3 off = o + 0.5 + (hash3(cell + o + vec3(5.0, 0.0, 0.0)) - 0.5) * 0.7 - local;
				float d = length(off);
				float radius = mix(0.28, 0.45, roll.y);
				if (d > radius * 1.1) {
					continue;
				}
				float angle = atan(dot(off, b), dot(off, t)) + roll.z * 6.2831853;
				float petal = pow(abs(cos(2.0 * angle)), roundness);
				float extent = radius * (0.35 + 0.65 * petal);
				float h = 0.15;
				if (d < extent) {
					h = 0.3 + 0.7 * pow(1.0 - d / extent, 0.7) * mix(0.7, 1.0, roll.y);
				}
				height = max(height, h);
			}
		}
	}
	return height;
}

// Eroded fBm at `scale` times the planet's frequency.
float erosion_at(vec3 dir, float frequency, float scale) {
	return fbm_eroded(dir * frequency * scale + 71.0, octaves_for(frequency * scale, 10));
}

// Latitude bands bent by turbulence, plus the storm. The "height" of a giant
// is only a colour coordinate - it is drawn with no relief.
//   detail[0]: turbulence, fine-streak weight, band sharpness (<1 flat bands
//              with crisp edges, >1 thin lines), band-width wobble
//   detail[1]: wobble scale along latitude, band offset (hemisphere asymmetry)
float gas_height(vec3 dir, float frequency) {
	vec4 a = detail[0];
	vec4 b = detail[1];
	vec3 p = dir * frequency;
	vec3 warp = vec3(fbm(p + 11.0, 5), fbm(p + 23.0, 5), fbm(p + 37.0, 5));
	float turbulence = fbm(p + warp * 1.2 * recipe.x, octaves_for(frequency, 9)) * 1.6;
	float fine = ridged(p * 2.2 + warp, octaves_for(frequency * 2.2, 8));

	// Latitude bent by slow noise along it, so the bands come in uneven widths.
	float latitude = dot(dir, pole.xyz);
	float bent = latitude + noised(vec3(latitude * b.x, 3.7, 1.3)).x * a.w + b.y;
	float s = sin(bent * shape.w * 3.14159265 + turbulence * a.x);
	float h = 0.5 + 0.5 * sign(s) * pow(abs(s), a.z);
	float streak = clamp(a.y, 0.0, 0.5);
	h = h * (1.0 - streak) + fine * streak;

	vec3 offset = dir - storm_center.xyz;
	float width = storm_center.w;
	float x = dot(offset, storm_east.xyz) / width;
	float y = dot(offset, storm_north.xyz) / (width * 0.55);
	float e = x * x + y * y;
	float spot = exp(-e);
	float swirl = 0.5 + 0.5 * sin(sqrt(e) * 7.0 - atan(y, x) * 2.0 + turbulence * 2.0);
	float target = storm_east.w > 0.5 ? 0.97 : 0.02;
	return mix(h, mix(target, swirl, 0.3), spot * 0.85 * storm_north.w);
}

float raw_height(vec3 dir) {
	int kind = int(shape.x + 0.5);
	float frequency = shape.z;

	if (kind == GAS_GIANT || kind == ICE_GIANT) {
		return gas_height(dir, frequency);
	}

	vec4 a = detail[0];
	vec4 b = detail[1];
	vec4 c = detail[2];
	vec4 e = detail[3];

	// Continents: warped fBm, stretched to roughly -1..1.
	vec3 p = dir * frequency;
	vec3 warp = vec3(fbm(p * 0.9 + 3.1, 4), fbm(p * 0.9 + 17.7, 4), fbm(p * 0.9 + 29.3, 4));
	float continent = fbm(p + warp * recipe.x, octaves_for(frequency, 12)) * 1.6;

	// Mountain belts, so ranges bunch up instead of one uniform crumple.
	float belt = smoothstep(recipe.y, recipe.z, fbm(p * 0.9 + 41.0, 3) * 1.6);
	vec3 rp = dir * frequency * 2.2 + warp * 0.35 * recipe.x + 53.0;
	float ridge = ridged(rp, octaves_for(frequency * 2.2, 11));
	float peaks = ridge * ridge * (0.25 + 0.75 * belt);

	if (kind == TERRAN) {
		// a: land threshold low / high (coast steepness), lowland flattening, peak weight
		// b: erosion weight, extra erosion in mountain belts, erosion scale
		float erosion = erosion_at(dir, frequency, b.z);
		float land = smoothstep(a.x, a.y, continent);
		return continent * (1.0 - a.z * land) + land * (peaks * a.w + erosion * (b.x + b.y * belt));
	}

	if (kind == TOXIC) {
		// a: as Terran
		// b: erosion weight, erosion scale (finer than Terran's), sinkhole share
		//    of cells, sinkhole depth
		// c.x: sinkhole scale
		float erosion = erosion_at(dir, frequency, b.y);
		float land = smoothstep(a.x, a.y, continent);
		float pits = pit_layer(dir * frequency * c.x + 19.0, b.z);
		return continent * (1.0 - a.z * land) + land * (peaks * a.w + erosion * b.x) - pits * b.w;
	}

	if (kind == DESERT) {
		// a: continent weight, peak weight, crater weight, crater scale
		// b: terrace count, mesa blend, crater-free share of cells, erosion weight
		float erosion = erosion_at(dir, frequency, 3.0);
		float base = continent * a.x + smoothstep(-0.2, 0.4, continent) * peaks * a.y;
		base += crater_layer(dir * frequency * a.w + 7.0, b.z, 0.4) * a.z + erosion * b.w;
		// Mesas: flat terraces with steep steps between them.
		float steps = max(b.x, 1.0);
		float t = base * steps;
		float stepped = (floor(t) + smoothstep(0.25, 0.75, fract(t))) / steps;
		float h = mix(base, stepped, clamp(b.y, 0.0, 0.95));
		// c: canyon scale, width, depth (0 = none), wander - deep valleys cut
		//    below everything else, which PlanetTerrain floods with lava
		if (c.z > 0.0) {
			h -= channels(dir * frequency * c.x + 71.0, c.y, c.w) * c.z;
		}
		return h;
	}

	if (kind == VOLCANIC) {
		// a: continent, peak, cone and erosion weights
		// b: cone scale (higher = more, smaller volcanoes), cone radius, caldera
		//    width, caldera depth
		// Worley distance turned upside down makes cones; the dip in the very
		// middle of each is the caldera.
		float erosion = erosion_at(dir, frequency, 3.0);
		float d0 = worley(dir * frequency * b.x + 7.0).x;
		float cone = pow(max(1.0 - d0 / b.y, 0.0), 2.0);
		cone -= (1.0 - smoothstep(0.0, b.z, d0)) * b.w;
		return continent * a.x + peaks * a.y + cone * a.z + erosion * a.w;
	}

	if (kind == ICE) {
		// a: continent, peak and erosion weights, fracture scale
		// b: fracture width, fracture depth, raised-flank height, how much of the
		//    surface is fractured (-1 nearly all .. 1 nearly none)
		// c.x: how far the fractures wander
		float erosion = erosion_at(dir, frequency, 3.0);
		vec2 f = fractures(dir * frequency * a.w + 13.0, b.x, c.x);
		float fractured = smoothstep(b.w - 0.15, b.w + 0.15, fbm(p * 0.7 + 91.0, 3) * 1.6);
		return continent * a.x + peaks * a.y + erosion * a.z + (f.y * b.z - f.x) * b.y * fractured;
	}

	if (kind == BARREN) {
		// a: continent, peak and erosion weights, crater-free share of cells
		// b: big, small and tiny crater weights, rim height
		// c: riverbed scale, width, depth, maria amount
		// e: riverbed wander, maria depth, crater scale, rim spikes (0 = none)
		float erosion = erosion_at(dir, frequency, 3.0);
		vec3 cp = dir * frequency * e.z;
		float craters = crater_layer_spiked(cp * 3.5 + 7.0, a.w, b.w, e.w) * b.x
			+ crater_layer_spiked(cp * 9.0 + 19.0, a.w, b.w, e.w) * b.y
			+ crater_layer(cp * 24.0 + 31.0, a.w, b.w) * b.z
			+ crater_layer(cp * 60.0 + 43.0, a.w, b.w) * 0.015;
		float ground = continent * a.x + peaks * a.y + erosion * a.z;

		// Maria: broad, flooded basins, younger than the craters they bury.
		float basin = smoothstep(0.0, 0.35, -fbm(p * 0.6 + 97.0, 4) * 1.6) * c.w;
		float h = mix(ground + craters, ground * 0.3 - e.y, basin);

		// Dry riverbeds, cut into the plains rather than the high ground, and
		// only in the regions that once had water.
		float lowland = 1.0 - smoothstep(-0.2, 0.5, continent);
		float wet_once = smoothstep(-0.1, 0.3, fbm(p * 0.45 + 113.0, 3) * 1.6);
		h -= channels(dir * frequency * c.x + 61.0, c.y, e.x) * c.z * (0.35 + 0.65 * lowland) * wet_once;
		return h;
	}

	if (kind == FROZEN) {
		// a: continent, peak and erosion weights, crater-free share of cells
		// b: big, small and tiny crater weights, rim height
		// c: fracture scale, width, depth, how much is fractured (-1 all .. 1 none)
		// e: fracture wander, crater scale
		float erosion = erosion_at(dir, frequency, 3.0);
		vec3 cp = dir * frequency * e.y;
		float craters = crater_layer(cp * 3.5 + 7.0, a.w, b.w) * b.x
			+ crater_layer(cp * 9.0 + 19.0, a.w, b.w) * b.y
			+ crater_layer(cp * 24.0 + 31.0, a.w, b.w) * b.z;
		vec2 f = fractures(dir * frequency * c.x + 13.0, c.y, e.x);
		float fractured = smoothstep(c.w - 0.15, c.w + 0.15, fbm(p * 0.7 + 91.0, 3) * 1.6);
		return continent * a.x + peaks * a.y + erosion * a.z + craters - f.x * c.z * fractured;
	}

	if (kind == SLIME) {
		// a: marsh weight (the low, soft ground), marsh roughness, peak weight,
		//    peak scale (higher = more, smaller peaks)
		// b: share of cells with a peak, peak sharpness, crag weight on the peaks
		float erosion = erosion_at(dir, frequency, 4.0);
		float marsh = continent * a.x + erosion * a.y;
		float mounts = peak_layer(dir * frequency * a.w + 29.0, b.x, b.y);
		// Ridged crags only on the peaks themselves, so the marsh stays soft.
		return marsh + mounts * a.z + ridge * mounts * b.z;
	}

	if (kind == OCCULT) {
		// a: continent, peak and erosion weights, crater-free share of cells
		// b: crater weight, dune weight, dune scale
		// c.x: tentacle ridge height
		// Plus the eye craters and tentacle nests in sigils[].
		float erosion = erosion_at(dir, frequency, 3.0);
		float dune = 1.0 - abs(noised(dir * frequency * b.z + 83.0).x * 2.0);
		float craters = crater_layer(dir * frequency * 3.5 + 7.0, a.w, 0.3);
		return continent * a.x + peaks * a.y + erosion * a.z + craters * b.x + dune * dune * b.y
			+ occult_marks(dir, c.x);
	}

	if (kind == LOTUS) {
		// a: ocean-floor roughness, flower scale, share of cells with a flower,
		//    petal roundness. The floor sits far below the pads and flowers,
		//    and PlanetTerrain pins the sea between them (sea_fixed).
		float floor_height = -0.3 + continent * a.x;
		return max(floor_height, flower_layer(dir, a.y, a.z, a.w));
	}

	if (kind == SWIRL) {
		// a: continent, peak and erosion weights, feature ridge weight
		float erosion = erosion_at(dir, frequency, 3.0);
		return continent * a.x + peaks * a.y + erosion * a.z + feature_relief(dir, kind) * a.w;
	}

	if (kind == RINGS) {
		// a: continent, peak and erosion weights, ring ridge weight
		// b: sand-hill weight (0 = none), sand-hill scale, volcano weight
		//    (0 = none), volcano scale
		// c.x: share of cells with a volcano
		float erosion = erosion_at(dir, frequency, 3.0);
		float h = continent * a.x + peaks * a.y + erosion * a.z + feature_relief(dir, kind) * a.w;
		if (b.x > 0.0) {
			// Sand hills in patches, rounded and running in rows.
			float dune = 1.0 - abs(noised(dir * frequency * b.y + 83.0).x * 2.0);
			float sandy = smoothstep(0.0, 0.35, fbm(p * 0.5 + 131.0, 3) * 1.6);
			h += dune * dune * b.x * sandy;
		}
		if (b.z > 0.0) {
			// A few volcanoes: lone cones, each with a caldera at the top.
			float cone = peak_layer(dir * frequency * b.w + 151.0, c.x, 1.6);
			h += (cone - smoothstep(0.8, 0.95, cone) * 0.45) * b.z;
		}
		return h;
	}

	if (kind == FRACTAL) {
		// a: continent, peak and erosion weights, massif height
		float erosion = erosion_at(dir, frequency, 3.0);
		return continent * a.x + peaks * a.y + erosion * a.z + feature_relief(dir, FRACTAL) * a.w;
	}

	if (kind == MERIDIAN) {
		// a: continent, peak and erosion weights, line weight
		float erosion = erosion_at(dir, frequency, 3.0);
		return continent * a.x + peaks * a.y + erosion * a.z + meridian_relief(dir) * a.w;
	}

	if (kind == QUAKE) {
		// a: continent, peak and erosion weights, hole depth
		// b: scar scale, density, size, shift - quake_* in the planet shader,
		//    which draws the scars' rings and spokes over these holes
		float erosion = erosion_at(dir, frequency, 3.0);
		return continent * a.x + peaks * a.y + erosion * a.z - quake_holes(dir, b.x, b.y, b.z, b.w) * a.w;
	}

	if (kind == GLOOM) {
		// a: continent, peak and erosion weights. Its cracks are drawn by the
		// planet shader, not carved here.
		float erosion = erosion_at(dir, frequency, 3.0);
		return continent * a.x + peaks * a.y + erosion * a.z;
	}

	if (kind == OASIS) {
		// a: continent, dune and erosion weights, dune scale
		// b: share of cells holding a puddle, puddle depth, puddle scale
		// Dunes are stretched along the pole, so their crests run east-west
		// like a sand sea's; the continents stay low so the puddle pits are
		// the lowest ground and the liquid fills them one by one.
		float erosion = erosion_at(dir, frequency, 3.0);
		vec3 dp = dir * frequency * a.w;
		dp += pole.xyz * dot(dp, pole.xyz) * 2.0;
		float dune = 1.0 - abs(noised(dp + 83.0).x * 2.0);
		// c: river scale, width, depth (0 = no rivers), wander - long beds cut
		//    as deep as the puddles, so the muddy water runs along them too
		float puddles = pit_layer(dir * frequency * b.z + 23.0, b.x);
		float h = continent * a.x + dune * dune * a.y + erosion * a.z - puddles * b.y;
		if (c.z > 0.0) {
			h -= channels(dir * frequency * c.x + 61.0, c.y, c.w) * c.z;
		}
		return h;
	}

	if (kind == BLOOM) {
		// a: continent weight (rolling fields), erosion weight, valley scale,
		//    valley width
		// b: valley depth, valley wander
		float erosion = erosion_at(dir, frequency, 3.0);
		float h = continent * a.x + erosion * a.y;
		return h - channels(dir * frequency * a.z + 61.0, a.w, b.y) * b.x;
	}

	return continent;
}

// ---- passes ---------------------------------------------------------------

uint to_ordered(float f) {
	uint u = floatBitsToUint(f);
	return (u & 0x80000000u) != 0u ? ~u : (u | 0x80000000u);
}

float from_ordered(uint u) {
	return uintBitsToFloat((u & 0x80000000u) != 0u ? (u & 0x7FFFFFFFu) : ~u);
}

void main() {
	uint n = uint(shape.y + 0.5);
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= n || id.y >= n) {
		return;
	}

	uint index = (id.z * n + id.y) * n + id.x;
	float step_size = 2.0 / float(n - 1u);
	float u = float(id.x) * step_size - 1.0;
	float v = float(id.y) * step_size - 1.0;

	if (push.pass == 0u) {
		vec3 dir = normalize(FACE_FORWARD[id.z] + FACE_RIGHT[id.z] * u + FACE_UP[id.z] * v);
		float h = raw_height(dir);
		heights[index] = h;
		uint ordered = to_ordered(h);
		atomicMin(low, ordered);
		atomicMax(high, ordered);
		return;
	}

	float lo = from_ordered(low);
	float span = max(from_ordered(high) - lo, 1e-6);
	float h = clamp((heights[index] - lo) / span, 0.0, 1.0);
	heights[index] = h;

	// Cube texels are not equal-area - corner ones cover about a fifth of a
	// centre one - so each counts by its solid angle.
	uint bin = min(uint(h * float(HISTOGRAM_BINS)), HISTOGRAM_BINS - 1u);
	float weight = 1.0 / pow(1.0 + u * u + v * v, 1.5);
	atomicAdd(histogram[bin], uint(weight * HISTOGRAM_SCALE + 0.5));
}
