shader_type spatial;
render_mode unshaded, cull_back;

// The photosphere of a star, on the same unit cube-sphere as the planets.
// Convection granules (animated Worley cells) over slow supergranulation,
// sunspot groups with umbra and penumbra plus scattered pores, bright faculae
// toward the limb, and limb darkening that also reddens the edge. Written in
// HDR, above 1, so the environment's glow blooms it.

uniform vec3 star_color : source_color = vec3(1.0, 0.85, 0.3);
// Overall brightness; the centre of the disc reaches roughly this. The
// tonemapper is linear, so past 1 it clips toward white: the disc is meant to
// glare, with its granules and pores only just showing through.
uniform float intensity : hint_range(0.5, 8.0) = 1.75;
// Limb darkening coefficient (linear law): 0 = flat disc, ~0.6 = the Sun.
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.5;
uniform float granule_scale = 70.0;
uniform float granule_speed = 0.25;
uniform float spot_amount : hint_range(0.0, 1.0) = 0.5;
uniform float seed_offset = 0.0;

// Orthonormal twist between octaves, so their lattices never line up.
const mat3 ROT = mat3(
	vec3(0.00, 0.80, 0.60),
	vec3(-0.80, 0.36, -0.48),
	vec3(-0.60, -0.48, 0.64)
);

varying vec3 v_dir;

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

float gradient_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float va = dot(hash3(i) * 2.0 - 1.0, f);
	float vb = dot(hash3(i + vec3(1.0, 0.0, 0.0)) * 2.0 - 1.0, f - vec3(1.0, 0.0, 0.0));
	float vc = dot(hash3(i + vec3(0.0, 1.0, 0.0)) * 2.0 - 1.0, f - vec3(0.0, 1.0, 0.0));
	float vd = dot(hash3(i + vec3(1.0, 1.0, 0.0)) * 2.0 - 1.0, f - vec3(1.0, 1.0, 0.0));
	float ve = dot(hash3(i + vec3(0.0, 0.0, 1.0)) * 2.0 - 1.0, f - vec3(0.0, 0.0, 1.0));
	float vf = dot(hash3(i + vec3(1.0, 0.0, 1.0)) * 2.0 - 1.0, f - vec3(1.0, 0.0, 1.0));
	float vg = dot(hash3(i + vec3(0.0, 1.0, 1.0)) * 2.0 - 1.0, f - vec3(0.0, 1.0, 1.0));
	float vh = dot(hash3(i + vec3(1.0, 1.0, 1.0)) * 2.0 - 1.0, f - vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y),
		mix(mix(ve, vf, u.x), mix(vg, vh, u.x), u.y),
		u.z
	);
}

// 1 while an octave spans several pixels, 0 once it would alias.
float octave_fade(float frequency, float footprint) {
	return 1.0 - smoothstep(0.25, 0.6, frequency * footprint);
}

float fbm(vec3 p, int octaves, float frequency, float footprint) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amplitude * gradient_noise(p * frequency) * octave_fade(frequency, footprint);
		p = ROT * p;
		frequency *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

// Convection cells: each Worley point drifts on its own little orbit, so the
// granules churn. Returns the gap between the nearest two points - 0 on the
// dark intergranular lanes, growing toward a granule's bright middle.
float granules(vec3 p, float time) {
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float f1 = 8.0;
	float f2 = 8.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 h = hash3(cell + offset);
				vec3 wobble = 0.5 + 0.38 * sin(time * (0.6 + h.yzx) + h * 6.2832);
				vec3 r = offset + wobble - local;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}

	return sqrt(f2) - sqrt(f1);
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float footprint = max(length(fwidth(v_dir)), 1e-6);
	float time = TIME * granule_speed;

	// Granulation, faded to its average once the cells are sub-pixel.
	float granule_fade = octave_fade(granule_scale, footprint * 0.5);
	vec3 gp = d * granule_scale + fbm(d + seed_offset, 2, 20.0, footprint) * 1.5;
	float lanes = granules(gp, time);
	// Soft-edged: real intergranular lanes are dark but blurred, not etched.
	float granule = mix(0.55, smoothstep(-0.08, 0.7, lanes), granule_fade);
	float fine = granules(gp * 2.3 + 17.0, time * 1.3);
	granule = mix(granule, granule * (0.8 + 0.4 * smoothstep(0.0, 0.5, fine)),
		octave_fade(granule_scale * 2.3, footprint * 0.5));

	// Supergranulation and slow brightness drift.
	float large = fbm(d + seed_offset + vec3(0.0, time * 0.02, 0.0), 4, 6.0, footprint);

	// Sunspot groups and scattered pores, all over the disc. (No active
	// latitude belt: the game looks down the spin axis, where a belt would
	// only ever show as a ring round the limb.)
	float activity = fbm(d + seed_offset * 0.7 + vec3(time * 0.004), 5, 3.8, footprint);
	float spot_threshold = mix(0.3, 0.12, spot_amount);
	float penumbra = smoothstep(spot_threshold, spot_threshold + 0.035, activity);
	float umbra = smoothstep(spot_threshold + 0.05, spot_threshold + 0.08, activity);
	// Scattered small spots and pores.
	float pores = fbm(d + seed_offset * 1.3 + vec3(0.0, time * 0.006, 0.0), 3, 22.0, footprint);
	float small = smoothstep(0.24, 0.3, pores) * octave_fade(22.0, footprint * 2.0);
	// Foreshortened to nothing near the limb, where they would only read as
	// dirt in the bright faculae.
	vec3 V_early = normalize(INV_VIEW_MATRIX[2].xyz);
	float face_on = smoothstep(0.25, 0.55, dot(normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz), V_early));
	penumbra = max(penumbra * face_on, small * 0.8 * face_on);
	umbra *= face_on;
	umbra = max(umbra, smoothstep(0.3, 0.34, pores) * octave_fade(22.0, footprint * 2.0) * face_on);
	// Faculae: bright plage around active regions, patchy, showing mostly
	// toward the limb where the disc around them has darkened.
	float plage = fbm(d + seed_offset * 2.1, 3, 9.0, footprint);
	float faculae = max(
		smoothstep(spot_threshold - 0.12, spot_threshold - 0.02, activity) * (1.0 - penumbra),
		smoothstep(0.08, 0.3, plage) * 0.8
	);
	// Mottling: warm red-orange patches drifting over the surface.
	float mottle = fbm(d + seed_offset * 0.4 + vec3(time * 0.003), 4, 3.5, footprint);

	// ---- limb ----
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 nw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);
	float mu = clamp(dot(nw, V), 0.0, 1.0);
	float limb = 1.0 - limb_darkening * (1.0 - pow(mu, 0.8));

	// Hotter centre whitens, cooler limb reddens.
	vec3 hot = mix(star_color * vec3(1.0, 0.86, 0.62), vec3(1.0), 0.1);
	vec3 cool = star_color * vec3(1.0, 0.55, 0.28);
	vec3 col = mix(cool, hot, pow(mu, 0.45));

	float brightness = intensity * limb;
	brightness *= 0.82 + 0.3 * granule;
	brightness *= 1.0 + large * 0.35;
	brightness *= 1.0 + faculae * 0.4 * pow(1.0 - mu, 1.5);
	brightness *= mix(1.0, 0.6, penumbra);
	brightness *= mix(1.0, 0.4, umbra);

	col = mix(col, star_color * vec3(1.0, 0.5, 0.22), smoothstep(-0.05, 0.25, mottle) * 0.45);
	col = mix(col, vec3(1.0, 0.93, 0.75), faculae * pow(1.0 - mu, 1.2) * 0.35);

	// Spots are cooler, so redder as well as darker.
	col = mix(col, star_color * vec3(1.0, 0.55, 0.3), penumbra * 0.7);

	ALBEDO = col * brightness;
}
