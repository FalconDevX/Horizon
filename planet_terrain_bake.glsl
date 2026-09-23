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

layout(set = 0, binding = 2, std430) restrict readonly buffer Params {
	vec4 shape;        // x kind, y face size, z frequency, w gas bands
	vec4 pole;         // xyz spin axis
	vec4 storm_center; // xyz centre, w width
	vec4 storm_east;   // xyz, w 1 = bright spot
	vec4 storm_north;
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
		float r = 1.0 - abs(noised(p).x * 1.4);
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
float crater(float d0, float radius) {
	float rim = exp(-pow((d0 - radius) / (radius * 0.22), 2.0)) * 0.4;
	if (d0 < radius) {
		float t = d0 / radius;
		return -(1.0 - t * t) * 0.8 + rim;
	}
	return rim;
}

// One crater layer: a crater around every Worley point, each cell rolling
// its own size - or that it has none. Summed over the neighbouring cells, not
// taken from the nearest one alone, so nothing jumps along the cell borders.
float crater_layer(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float sum = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(x, y, z);
				float roll = hash3(cell + offset + vec3(0.0, 0.0, 4099.0)).x;
				if (roll < 0.25) {
					continue;
				}
				vec3 r = offset + 0.5 + (hash3(cell + offset) - 0.5) * 0.9 - local;
				sum += crater(length(r), mix(0.2, 0.5, (roll - 0.25) / 0.75));
			}
		}
	}

	return sum;
}

// Latitude bands bent by turbulence, plus the storm. The "height" of a giant
// is only a colour coordinate - it is drawn with no relief.
float gas_height(vec3 dir, float frequency) {
	vec3 p = dir * frequency;
	vec3 warp = vec3(fbm(p + 11.0, 5), fbm(p + 23.0, 5), fbm(p + 37.0, 5));
	float turbulence = fbm(p + warp * 1.2, octaves_for(frequency, 9)) * 1.6;
	float fine = ridged(p * 2.2 + warp, octaves_for(frequency * 2.2, 8));

	float latitude = dot(dir, pole.xyz);
	float h = 0.5 + 0.5 * sin(latitude * shape.w * 3.14159265 + turbulence * 3.0);
	h = h * 0.82 + fine * 0.18;

	vec3 offset = dir - storm_center.xyz;
	float width = storm_center.w;
	float x = dot(offset, storm_east.xyz) / width;
	float y = dot(offset, storm_north.xyz) / (width * 0.55);
	float e = x * x + y * y;
	float spot = exp(-e);
	float swirl = 0.5 + 0.5 * sin(sqrt(e) * 7.0 - atan(y, x) * 2.0 + turbulence * 2.0);
	float target = storm_east.w > 0.5 ? 0.97 : 0.02;
	return mix(h, mix(target, swirl, 0.3), spot * 0.85);
}

float raw_height(vec3 dir) {
	int kind = int(shape.x + 0.5);
	float frequency = shape.z;

	if (kind == GAS_GIANT || kind == ICE_GIANT) {
		return gas_height(dir, frequency);
	}

	// Continents: warped fBm, stretched to roughly -1..1.
	vec3 p = dir * frequency;
	vec3 warp = vec3(fbm(p * 0.9 + 3.1, 4), fbm(p * 0.9 + 17.7, 4), fbm(p * 0.9 + 29.3, 4));
	float continent = fbm(p + warp * 0.9, octaves_for(frequency, 12)) * 1.6;

	// Mountain belts, so ranges bunch up instead of one uniform crumple.
	float belt = smoothstep(-0.1, 0.25, fbm(p * 0.9 + 41.0, 3) * 1.6);
	vec3 rp = dir * frequency * 2.2 + warp * 0.35 + 53.0;
	float ridge = ridged(rp, octaves_for(frequency * 2.2, 11));
	float peaks = ridge * ridge * (0.25 + 0.75 * belt);
	// Eroded fBm roughens the flats and gullies the slopes.
	float erosion = fbm_eroded(dir * frequency * 3.0 + 71.0, octaves_for(frequency * 3.0, 10));

	if (kind == TERRAN || kind == TOXIC) {
		float land = smoothstep(-0.05, 0.3, continent);
		return continent * (1.0 - 0.35 * land)
			+ land * (peaks * 0.8 + erosion * (0.12 + 0.25 * belt));
	}

	if (kind == DESERT) {
		float base = continent * 0.8 + smoothstep(-0.2, 0.4, continent) * peaks * 0.6;
		base += crater_layer(dir * frequency * 3.5 + 7.0) * 0.1 + erosion * 0.12;
		// Mesas: flat terraces with steep steps between them.
		float t = base * 7.0;
		float stepped = (floor(t) + smoothstep(0.25, 0.75, fract(t))) / 7.0;
		return mix(base, stepped, 0.55);
	}

	if (kind == VOLCANIC) {
		// Worley distance turned upside down makes cones; the dip in the very
		// middle of each is the caldera.
		float d0 = worley(dir * frequency * 3.5 + 7.0).x;
		float cone = pow(max(1.0 - d0 / 0.65, 0.0), 2.0);
		cone -= (1.0 - smoothstep(0.0, 0.12, d0)) * 0.35;
		return continent * 0.6 + peaks * 0.5 + cone * 0.55 + erosion * 0.12;
	}

	if (kind == ICE) {
		vec3 w = worley(dir * frequency * 3.0 + 13.0);
		float crack = 1.0 - smoothstep(0.0, 0.06, w.y - w.x);
		return continent * 0.7 + peaks * 0.3 - crack * 0.12 + erosion * 0.06;
	}

	if (kind == BARREN) {
		float big = crater_layer(dir * frequency * 3.5 + 7.0);
		float small = crater_layer(dir * frequency * 9.0 + 19.0);
		float tiny = crater_layer(dir * frequency * 24.0 + 31.0);
		float speck = crater_layer(dir * frequency * 60.0 + 43.0);
		return continent * 0.45 + peaks * 0.15 + erosion * 0.08
			+ big * 0.35 + small * 0.15 + tiny * 0.05 + speck * 0.015;
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
