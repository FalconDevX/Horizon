shader_type canvas_item;

// Barred spiral galaxy for the galaxy map (scripts/ui/GalaxyMapWindow.gd).
// Galaxy coordinates are in units of its radius; the arms follow the same
// curve GalaxyMap.arm_angle() places systems on, so they sit in the arms.
//  - old disk and bulge: warm, smooth, falling off from the core, with a bar;
//  - arms: clumpy blue-white young stars;
//  - dust lanes on the arms' inner edge redden and dim what is behind them;
//  - H II regions: pink knots strung along the arms;
//  - point stars at three scales, each fading in once its cells are a few
//    pixels across, so zooming in keeps revealing finer stars.

uniform vec2 rect_size = vec2(1000.0, 600.0);
uniform vec2 center = vec2(500.0, 300.0); // galaxy origin, in rect pixels
uniform float px_per_unit = 300.0;
uniform float arm_count = 4.0;
uniform float arm_twist = 3.4;
uniform float exposure = 1.25;

// Integer hashes (PCG). A float hash like fract(sin(..)) is chaotic, so
// the GPU rounding the same lattice corner slightly differently in two
// neighbouring cells (fused multiply-adds) gives it two different values and
// the noise breaks into visible squares. Integers hash exactly.
uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float hash_i(ivec2 c, uint salt) {
	return float(pcg(uint(c.x) ^ pcg(uint(c.y) ^ pcg(salt)))) / 4294967295.0;
}

vec2 hash_i2(ivec2 c, uint salt) {
	return vec2(hash_i(c, salt), hash_i(c, salt + 7919u));
}

float vnoise(vec2 p) {
	vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(hash_i(i, 0u), hash_i(i + ivec2(1, 0), 0u), f.x),
		mix(hash_i(i + ivec2(0, 1), 0u), hash_i(i + ivec2(1, 1), 0u), f.x),
		f.y
	);
}

// Octaves turned against each other so the noise grid never shows.
float fbm(vec2 p, int octaves) {
	const mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		p = turn * p * 2.02 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return v;
}

// 1 on an arm's spine, falling to 0 between arms; `shift` slides the spine
// round in angle (negative = the inner, leading edge of the arm).
float arm(float theta, float r, float shift, float sharpness) {
	float d = theta - arm_twist * sqrt(max(r, 1e-4)) - shift;
	return pow(0.5 + 0.5 * cos(arm_count * d), sharpness);
}

// Colour of a star of `temperature` 0 (red dwarf) .. 1 (blue giant).
vec3 star_color(float t) {
	vec3 c = mix(vec3(1.0, 0.55, 0.35), vec3(1.0, 0.9, 0.75), smoothstep(0.0, 0.45, t));
	return mix(c, vec3(0.7, 0.82, 1.0), smoothstep(0.55, 1.0, t));
}

// One layer of point stars on a grid of `cell` galaxy units. `density` is
// the chance a cell holds a star; stars keep a fixed size in pixels.
vec3 star_layer(vec2 g, float cell, float density, uint seed, float bias) {
	float cell_px = cell * px_per_unit;
	float fade = smoothstep(2.5, 7.0, cell_px);
	if (fade <= 0.0) {
		return vec3(0.0);
	}
	vec2 fl = floor(g / cell);
	ivec2 key = ivec2(fl);
	vec2 f = g / cell - fl;
	uint salt = seed * 16u;
	if (hash_i(key, salt) > density) {
		return vec3(0.0);
	}
	vec2 at = 0.2 + 0.6 * hash_i2(key, salt + 1u);
	float d = length(f - at) * cell_px;
	float mag = pow(hash_i(key, salt + 2u), 3.0); // few bright, many faint
	float size = mix(0.55, 1.5, mag) * mix(1.0, 1.35, bias);
	float core = exp(-d * d / (size * size));
	// Diffraction spikes on the brightest.
	vec2 dv = (f - at) * cell_px;
	float spikes = 0.0;
	if (mag > 0.8) {
		float s = size * 7.0 * (mag - 0.8) * 5.0;
		spikes = (exp(-abs(dv.y) * 2.2) * exp(-abs(dv.x) / s) + exp(-abs(dv.x) * 2.2) * exp(-abs(dv.y) / s)) * 0.35;
	}
	float t = clamp(hash_i(key, salt + 3u) * 0.9 + bias * 0.35 - 0.1, 0.0, 1.0);
	return star_color(t) * (core * mix(0.35, 2.2, mag) + spikes * mag) * fade;
}

void fragment() {
	vec2 local = UV * rect_size;
	vec2 g = (local - center) / px_per_unit;
	float r = length(g);
	float theta = atan(g.y, g.x);

	// Ragged arms: warp the angle a little with large-scale noise.
	float warp = fbm(g * 2.6 + 3.0, 4) - 0.5;
	float th = theta + warp * 0.55;

	float env = smoothstep(0.05, 0.22, r) * (1.0 - smoothstep(0.78, 1.08, r));
	float disk = exp(-r / 0.26) * (1.0 - smoothstep(0.9, 1.25, r));
	float arm_broad = arm(th, r, 0.0, 1.6);
	float arm_tight = arm(th, r, 0.0, 6.0);

	// Old stars: the smooth warm disk, a little brighter in the arms.
	vec3 col = vec3(1.0, 0.8, 0.58) * disk * (0.35 + 0.5 * arm_broad) * 0.9;

	// Bulge and bar.
	float bar_angle = 0.45;
	vec2 gb = mat2(vec2(cos(bar_angle), sin(bar_angle)), vec2(-sin(bar_angle), cos(bar_angle))) * g;
	float bar = exp(-pow(gb.x / 0.2, 2.0) - pow(gb.y / 0.055, 2.0));
	float bulge = exp(-pow(r / 0.1, 2.0)) * 1.6 + exp(-r / 0.045) * 1.4 + bar * 0.55;
	col += vec3(1.0, 0.82, 0.55) * bulge;

	// Young stars: clumpy blue-white along the arm spines.
	// More octaves as the view zooms in, so there is detail at every scale.
	int extra = int(clamp(log2(px_per_unit / 350.0) + 0.5, 0.0, 4.0));
	float clumps = fbm(g * 11.0, 6 + extra);
	float young = arm_tight * env * smoothstep(0.3, 0.8, clumps);
	col += vec3(0.62, 0.78, 1.0) * young * 1.5;
	// Faint blue haze round the arms.
	col += vec3(0.35, 0.5, 0.9) * arm_broad * env * 0.18;

	// H II regions: pink knots on the arms.
	vec2 hc = g / 0.028;
	ivec2 hid = ivec2(floor(hc));
	float hii = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 cid = hid + ivec2(x, y);
			vec2 cg = (vec2(cid) + 0.5) * 0.028;
			float cr = length(cg);
			// Decided at the cell's centre, so every pixel agrees on it
			// and no knot gets cut in half.
			float cell_warp = fbm(cg * 2.6 + 3.0, 4) - 0.5;
			float on = arm(atan(cg.y, cg.x) + cell_warp * 0.55, cr, 0.0, 8.0);
			on *= smoothstep(0.12, 0.3, cr) * (1.0 - smoothstep(0.75, 0.95, cr));
			if (hash_i(cid, 900u) < on * 0.75) {
				vec2 p = vec2(cid) + hash_i2(cid, 901u);
				float rad = mix(0.07, 0.22, hash_i(cid, 902u));
				float d = length(hc - p) / rad;
				// Soft glow with a brighter knot in the middle.
				hii += (exp(-d * d) * 0.7 + exp(-d * d * 6.0) * 0.8) * mix(0.5, 1.3, hash_i(cid, 903u));
			}
		}
	}
	col += vec3(1.0, 0.36, 0.58) * hii * 0.8 * env;

	// Dust lanes: dark filaments on the leading edge of each arm, reddening.
	float lane = arm(th, r, -0.16, 9.0);
	float dust_noise = fbm(g * 16.0 + 40.0, 6 + extra);
	float dust = lane * smoothstep(0.35, 0.72, dust_noise) * env * 1.8;
	dust += smoothstep(0.62, 0.85, fbm(g * 30.0 + 9.0, 5 + extra)) * disk * 1.2 * env;
	col *= exp(-dust * vec3(0.9, 1.25, 1.7));

	// Luminosity decides how crowded the resolved stars are.
	float lum = clamp(disk * 1.5 + young * 1.2 + bulge * 0.4, 0.0, 1.0) * exp(-dust * 0.7);
	col += star_layer(g, 0.045, 0.12 + 0.5 * lum, 1u, arm_tight);
	col += star_layer(g, 0.014, 0.05 + 0.6 * lum, 2u, arm_tight);
	col += star_layer(g, 0.0045, 0.02 + 0.6 * lum, 3u, arm_tight) * 0.8;
	col += star_layer(g, 0.0014, 0.01 + 0.55 * lum, 4u, arm_tight) * 0.6;

	// Deep background: a faint cold wash and a few distant galaxies' glow.
	float bg = fbm(g * 1.3 - 20.0, 4);
	col += vec3(0.02, 0.025, 0.06) * smoothstep(0.3, 0.8, bg);

	col = vec3(1.0) - exp(-col * exposure);
	COLOR = vec4(col, 1.0);
}
