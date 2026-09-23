shader_type spatial;
render_mode unshaded, cull_back;

// Heightmap planet. The mesh is a unit cube-sphere whose object-space
// direction is the planet-space direction; the heightmap (six cube faces in a
// mipmapped texture array, baked on the GPU by PlanetTerrain.bake()) pushes
// each vertex out and picks the colour. Close up, the map is read bicubically
// and a procedural fractal carries the terrain on below its texels, faded out
// by the pixel footprint so nothing shimmers from afar. Liquid is flat:
// anything under sea_level is drawn at sea level with its own shallow-to-deep
// colour, gloss and optional glow (lava). Lit by hand from the sun, like
// planet_surface_3d.gdshader.

uniform sampler2DArray height_faces : filter_linear_mipmap, repeat_disable;
uniform float face_size = 1024.0;

// Highest ground above the sea (or above the lowest point on a dry world), as
// a fraction of the radius. Exaggerated on purpose.
uniform float relief : hint_range(0.0, 0.3) = 0.07;
// Extra steepness used only for shading, so relief that is small on the
// silhouette still reads as mountains in the light.
uniform float bump : hint_range(0.0, 30.0) = 5.0;

uniform bool has_liquid = true;
uniform float sea_level : hint_range(0.0, 1.0) = 0.5;
uniform bool is_gas = false;

// Height gradient: land_colors[i] (linear) at land_stops[i], 0 = shoreline.
uniform vec4 land_colors[6];
uniform float land_stops[6];

uniform vec3 liquid_shallow : source_color = vec3(0.1, 0.5, 0.6);
uniform vec3 liquid_deep : source_color = vec3(0.0, 0.05, 0.2);
uniform float liquid_emission : hint_range(0.0, 4.0) = 0.0;
uniform float liquid_gloss : hint_range(0.0, 1.0) = 0.8;

uniform vec3 rock_color : source_color = vec3(0.4);
uniform float slope_rock : hint_range(0.0, 1.0) = 0.5;
// Sediment bands across exposed rock; 0 = plain rock.
uniform float strata : hint_range(0.0, 1.0) = 0.0;

// Arid biome laid over the lowlands where a moisture noise runs dry, favouring
// the subtropics like real deserts do.
uniform vec3 dry_color : source_color = vec3(0.6, 0.5, 0.35);
uniform float dry_amount : hint_range(0.0, 1.0) = 0.0;

// Polar caps start at this |latitude| (sine of it, 0..1); above 1 disables.
uniform vec3 cap_color : source_color = vec3(1.0);
uniform float cap_latitude = 2.0;
// The spin axis in planet space - where the poles and the giants' bands sit.
uniform vec3 pole_axis = vec3(0.0, 1.0, 0.0);

uniform vec3 atmo_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmo_strength : hint_range(0.0, 3.0) = 0.6;
uniform float atmo_haze : hint_range(0.0, 1.0) = 0.0;

uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale = 3.5;
uniform float cloud_speed = 0.01;

// Strength of the sub-texel fractal, 1 = continuing the baked one's falloff.
uniform float detail_strength : hint_range(0.0, 3.0) = 1.0;
uniform float seed_offset = 0.0;

uniform float ambient : hint_range(0.0, 1.0) = 0.04;
// Tips the sunlight up toward the camera - see planet_surface_3d.gdshader.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);

global uniform vec3 sun_position;

const int DETAIL_OCTAVES = 5;
const int CLOUD_OCTAVES = 6;

// Orthonormal twist between octaves, so their lattices never line up.
const mat3 ROT = mat3(
	vec3(0.00, 0.80, 0.60),
	vec3(-0.80, 0.36, -0.48),
	vec3(-0.60, -0.48, 0.64)
);

varying vec3 v_dir;

// ---- heightmap ------------------------------------------------------------

// Mirror of PlanetTerrain.face_uv(): which face, and (u, v) on it.
vec3 face_uv(vec3 d) {
	vec3 a = abs(d);
	vec3 f;
	vec3 r;
	vec3 u;
	float face;

	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { face = 0.0; f = vec3(1.0, 0.0, 0.0); r = vec3(0.0, 0.0, -1.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 1.0; f = vec3(-1.0, 0.0, 0.0); r = vec3(0.0, 0.0, 1.0); u = vec3(0.0, 1.0, 0.0); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { face = 2.0; f = vec3(0.0, 1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0); }
		else { face = 3.0; f = vec3(0.0, -1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0); }
	} else {
		if (d.z > 0.0) { face = 4.0; f = vec3(0.0, 0.0, 1.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 5.0; f = vec3(0.0, 0.0, -1.0); r = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
	}

	float forward = dot(d, f);
	return vec3(dot(d, r) / forward, dot(d, u) / forward, face);
}

// Texel centres sit on the cube edges: u = -1 is the middle of the first one.
vec3 face_texcoord(vec3 d) {
	vec3 fuv = face_uv(d);
	vec2 uv = (fuv.xy * 0.5 + 0.5) * ((face_size - 1.0) / face_size) + 0.5 / face_size;
	return vec3(uv, fuv.z);
}

float height_lod(vec3 d, float lod) {
	return textureLod(height_faces, face_texcoord(d), lod).r;
}

// Cubic B-spline in four bilinear taps: smooth slopes, no bilinear creases.
float height_bicubic(vec3 d) {
	vec3 tc = face_texcoord(d);
	vec2 p = tc.xy * face_size - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;

	vec2 w0 = (-f3 + 3.0 * f2 - 3.0 * f + 1.0) / 6.0;
	vec2 w1 = (3.0 * f3 - 6.0 * f2 + 4.0) / 6.0;
	vec2 w2 = (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 t0 = (i - 0.5 + w1 / g0) / face_size;
	vec2 t1 = (i + 1.5 + w3 / g1) / face_size;

	float s00 = textureLod(height_faces, vec3(t0.x, t0.y, tc.z), 0.0).r;
	float s10 = textureLod(height_faces, vec3(t1.x, t0.y, tc.z), 0.0).r;
	float s01 = textureLod(height_faces, vec3(t0.x, t1.y, tc.z), 0.0).r;
	float s11 = textureLod(height_faces, vec3(t1.x, t1.y, tc.z), 0.0).r;

	return g0.y * (g0.x * s00 + g1.x * s10) + g1.y * (g0.x * s01 + g1.x * s11);
}

// Bicubic up close, plain mipmapped once a texel is smaller than a pixel.
// The B-spline would read past a face's edge (clamped), so over the last few
// texels it hands over to bilinear, which the two faces share exactly.
float height_filtered(vec3 d, float lod) {
	if (lod >= 1.0) {
		return height_lod(d, lod);
	}
	vec3 fuv = face_uv(d);
	float to_edge = (1.0 - max(abs(fuv.x), abs(fuv.y))) * face_size * 0.5;
	float cubic = smoothstep(1.0, 3.0, to_edge);
	float bilinear = height_lod(d, 0.0);
	return cubic > 0.0 ? mix(bilinear, height_bicubic(d), cubic) : bilinear;
}

float ground(float h) {
	return has_liquid ? max(h - sea_level, 0.0) : h;
}

// ---- procedural noise (shading only; gameplay never sees it) ---------------

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

// The terrain below heightmap resolution: eroded fBm (octaves damped where
// the ones before are steep) with its gradient in planet space. xyz is the
// gradient, w the height.
vec4 detail(vec3 d, float frequency, float footprint) {
	float sum = 0.0;
	vec3 gradient = vec3(0.0);
	vec3 slope = vec3(0.0);
	float amplitude = 0.5;
	mat3 m = mat3(1.0);

	for (int i = 0; i < DETAIL_OCTAVES; i++) {
		float fade = octave_fade(frequency, footprint);
		if (fade <= 0.0) {
			break;
		}
		vec4 n = noised(m * d * frequency + seed_offset);
		// Back from the octave's twisted frame into planet space.
		vec3 g = transpose(m) * n.yzw * frequency;
		slope += n.yzw;
		float damp = 1.0 / (1.0 + dot(slope, slope) * 0.6);
		sum += amplitude * n.x * damp * fade;
		gradient += amplitude * g * damp * fade;
		m = ROT * m;
		frequency *= 2.03;
		amplitude *= 0.5;
	}

	return vec4(gradient, sum);
}

// Cheap value noise for colour grain.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y
		),
		mix(
			mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y
		),
		f.z
	);
}

vec3 land_gradient(float x) {
	vec3 c = land_colors[0].rgb;
	for (int i = 1; i < 6; i++) {
		c = mix(c, land_colors[i].rgb, smoothstep(land_stops[i - 1], land_stops[i], x));
	}
	return c;
}

vec3 rotate_about(vec3 v, vec3 axis, float angle) {
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}

// Cloud density around -0.5..0.5, domain-warped so it swirls.
float clouds_at(vec3 cd, int octaves, float footprint) {
	vec3 p = cd + seed_offset * 0.37;
	vec3 warp = vec3(
		noised(p * cloud_scale * 0.5).x,
		noised(p * cloud_scale * 0.5 + 5.2).x,
		noised(p * cloud_scale * 0.5 + 9.7).x
	);
	p += warp * (0.6 / cloud_scale);
	float c = fbm(p, octaves, cloud_scale, footprint);
	// Stretched along latitude, so it streaks like weather bands.
	float latitude = dot(cd, pole_axis);
	c += fbm(vec3(cd.x, latitude * 3.0, cd.z) + 3.0, 2, cloud_scale * 0.5, footprint) * 0.35;
	return c;
}

float cloud_cover(float c) {
	float threshold = 0.2 - 0.4 * cloud_coverage;
	return smoothstep(threshold, threshold + 0.14, c);
}

// ---------------------------------------------------------------------------

void vertex() {
	vec3 dir = normalize(VERTEX);
	// Full resolution: only there do two faces agree on their shared edge, so
	// any blurrier level would open cracks along the seams.
	VERTEX = dir * (1.0 + relief * ground(height_lod(dir, 0.0)));
	v_dir = dir;
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec3 helper = abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(helper, d));
	vec3 b = cross(d, t);

	// One pixel's width on the unit sphere, and in heightmap texels.
	float footprint = max(length(fwidth(v_dir)), 1e-6);
	float texel = 2.0 / face_size;
	float lod = log2(max(footprint / texel, 1.0));
	float eps = max(texel, footprint);

	float h = height_filtered(d, lod);
	float h_t1 = height_filtered(normalize(d + t * eps), lod);
	float h_t0 = height_filtered(normalize(d - t * eps), lod);
	float h_b1 = height_filtered(normalize(d + b * eps), lod);
	float h_b0 = height_filtered(normalize(d - b * eps), lod);

	float grain = 0.5 + fbm(d + seed_offset, 3, 45.0, footprint);
	float latitude = dot(d, pole_axis);

	// Planet-space sun, for cloud shadows.
	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	vec3 L_planet = normalize(transpose(mat3(MODEL_MATRIX)) * L);

	vec3 col;
	vec3 n = d;
	float gloss = 0.0;
	float glow = 0.0;
	bool liquid = false;
	float ground_h = 0.0;

	if (is_gas) {
		// Bands dragged sideways by stretched turbulence: eddies along the
		// band edges, far finer than the map itself.
		float drag = fbm(vec3(d.x * 3.0, latitude * 14.0, d.z * 3.0) + seed_offset, 4, 2.0, footprint * 6.0);
		float gh = height_filtered(normalize(rotate_about(d, pole_axis, drag * 0.06)), lod);
		float streak = fbm(vec3(d.x * 5.0, latitude * 60.0, d.z * 5.0) + seed_offset, 4, 1.5, footprint * 20.0);
		col = land_gradient(clamp(gh + streak * 0.12, 0.0, 1.0));
	} else {
		float detail_frequency = face_size * 0.25;
		vec4 fine = detail(d, detail_frequency, footprint);
		// Match the baked fractal's falloff, a little rougher on high ground.
		float land_guess = has_liquid ? (h - sea_level) / max(1.0 - sea_level, 1e-3) : h;
		float rough = mix(0.5, 1.6, smoothstep(0.05, 0.6, land_guess));
		float amplitude = detail_strength * 1.2 / detail_frequency * rough;
		float h_fine = h + fine.w * amplitude;

		liquid = has_liquid && h_fine < sea_level;
		ground_h = ground(h_fine);

		// Normal of the displaced surface: macro slope from the map, fine
		// slope from the fractal, both exaggerated by `bump`.
		float k = relief * bump;
		vec3 macro = (t * (ground(h_t1) - ground(h_t0)) + b * (ground(h_b1) - ground(h_b0))) / (2.0 * eps);
		vec3 micro = fine.xyz * amplitude * (liquid ? 0.0 : 1.0);
		micro -= d * dot(micro, d);
		vec3 n_macro = normalize(d - k * macro);
		n = normalize(n_macro * dot(n_macro, d) - k * 0.6 * micro + (n_macro - d * dot(n_macro, d)));
		// Rock follows the big slopes; the fine ones only fray its edges, or
		// every bump would flip between rock and grass and read as spots.
		float slope = 1.0 - dot(n_macro, d) + (1.0 - dot(n, n_macro)) * 0.25;

		// Second difference a few texels wide, off a blurrier mip so it finds
		// valleys and crests rather than every texel's grain: > 0 in hollows.
		float cavity_eps = max(texel * 6.0, footprint * 2.0);
		float cavity_lod = log2(cavity_eps / texel) - 1.0;
		float h_c = height_lod(d, cavity_lod);
		float curvature = height_lod(normalize(d + t * cavity_eps), cavity_lod)
			+ height_lod(normalize(d - t * cavity_eps), cavity_lod)
			+ height_lod(normalize(d + b * cavity_eps), cavity_lod)
			+ height_lod(normalize(d - b * cavity_eps), cavity_lod) - 4.0 * h_c;
		float cavity = clamp(curvature * 60.0, -1.0, 1.0);

		if (liquid) {
			float depth = clamp((sea_level - h_fine) / max(sea_level, 1e-3), 0.0, 1.0);
			col = mix(liquid_shallow, liquid_deep, smoothstep(0.0, 0.45, depth));
			gloss = liquid_gloss;

			if (liquid_emission > 0.0) {
				// Lava: a cooling crust drifting over the glow.
				float crust = smoothstep(-0.05, 0.15,
					fbm(d + vec3(0.0, TIME * 0.002, 0.0), 4, 60.0, footprint));
				col = mix(col, rock_color * 0.5, crust * 0.85);
				glow = liquid_emission * (1.0 - crust * 0.9) * mix(1.0, 0.55, depth);
				gloss *= 1.0 - crust;
			} else {
				// Surf where the sea is shallowest.
				float surf = (1.0 - smoothstep(0.0, 0.012, depth))
					* smoothstep(0.35, 0.75, value_noise(d * 700.0 + TIME * 0.6));
				col = mix(col, vec3(0.9), surf * 0.55);
				col = mix(col, liquid_shallow * 1.3, (1.0 - smoothstep(0.0, 0.03, depth)) * 0.4);
			}

			// Swell - two octaves of moving waves, gone once sub-pixel.
			vec3 wave = vec3(0.0);
			for (int i = 0; i < 2; i++) {
				float f = 180.0 * pow(2.7, float(i));
				vec4 w = noised(d * f + vec3(TIME * 0.15, -TIME * 0.11, TIME * 0.07) * float(i + 1));
				wave += w.yzw * octave_fade(f, footprint) * (0.03 / float(i + 1));
			}
			wave -= d * dot(wave, d);
			n = normalize(d + wave);
		} else {
			float land = has_liquid ? (h_fine - sea_level) / max(1.0 - sea_level, 1e-3) : h_fine;
			land = clamp(land + (grain - 0.5) * 0.03, 0.0, 1.0);
			col = land_gradient(land);

			// Dry biome over the lowlands, most likely around the subtropics.
			float subtropic = exp(-pow((abs(latitude) - 0.42) / 0.16, 2.0));
			float moisture = fbm(d + seed_offset * 0.13, 4, 2.2, footprint);
			float dryness = smoothstep(-0.05, 0.2, moisture + subtropic * 0.2 - 0.05);
			float lowland = 1.0 - smoothstep(0.35, 0.65, land);
			vec3 dry = dry_color * (0.85 + 0.3 * value_noise(d * 9.0 + 7.0));
			col = mix(col, dry, dryness * dry_amount * lowland);

			// Exposed rock on the steep parts, banded into strata.
			vec3 rock = rock_color * (0.8 + 0.4 * grain);
			if (strata > 0.0) {
				float warp = fbm(d, 2, 30.0, footprint) * 2.0;
				float band = 0.5 + 0.5 * sin((h_fine * 90.0 + warp) * 6.2832);
				band += (value_noise(vec3(h_fine * 400.0, 0.0, 0.0)) - 0.5) * 0.6;
				rock *= mix(1.0, 0.7 + 0.55 * band, strata);
			}
			col = mix(col, rock, smoothstep(0.08, 0.35, slope) * slope_rock);
			col *= 0.92 + 0.16 * grain;

			// Hollows darker, crests a touch brighter.
			col *= 1.0 - 0.3 * max(cavity, 0.0);
			col *= 1.0 + 0.15 * max(-cavity, 0.0);
		}
	}

	if (cap_latitude <= 1.0 && !is_gas) {
		float edge = abs(latitude) + fbm(d, 4, 7.0, footprint) * 0.2;
		// Ice reaches further toward the equator on high ground.
		edge += liquid ? 0.0 : ground_h * 0.25;
		float cap = smoothstep(cap_latitude, cap_latitude + 0.025, edge);
		col = mix(col, cap_color * (0.92 + 0.08 * grain), cap);
		gloss = mix(gloss, 0.25, cap);
		glow *= 1.0 - cap;
		n = normalize(mix(n, d, cap * 0.5));
	}

	// ---- lighting (world space) ----
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 nw = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 sw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);

	float sphere_light = dot(sw, L);
	// Terrain slopes cannot light up the night side past the terminator.
	float day = smoothstep(-0.12, 0.2, sphere_light);
	// A little wrap, as scattered light would give: shadowed slopes on the day
	// side go dim, not pitch black.
	float diffuse = clamp(dot(nw, L) * 0.85 + 0.15, 0.0, 1.0) * day;
	float sky_fill = atmo_strength * 0.06 * day * (0.5 + 0.5 * dot(nw, sw));

	// Cloud shadows, cast along the light across the ground below.
	float shadow = 1.0;
	float cover = 0.0;
	if (cloud_coverage > 0.0) {
		vec3 cd = rotate_about(d, pole_axis, TIME * cloud_speed);
		cover = cloud_cover(clouds_at(cd, CLOUD_OCTAVES, footprint));
		vec3 shadow_dir = normalize(cd + L_planet * 0.012);
		shadow = 1.0 - 0.55 * cloud_cover(clouds_at(shadow_dir, 3, footprint));
	}

	vec3 lit = col * (ambient + (1.0 - ambient) * diffuse * shadow * sun_color + atmo_color * sky_fill);

	if (gloss > 0.0) {
		vec3 halfway = normalize(L + V);
		float spec = pow(max(dot(nw, halfway), 0.0), mix(16.0, 220.0, gloss));
		lit += sun_color * spec * gloss * day * shadow * mix(0.6, 2.5, gloss);
		// The sky mirrored in the sea, strongest at grazing angles.
		float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(nw, V), 0.0), 5.0);
		lit = mix(lit, atmo_color * 0.6 * day, fresnel * gloss * 0.6);
	}

	lit += col * glow;

	if (cloud_coverage > 0.0) {
		vec3 cloud_lit = cloud_color * (ambient + (1.0 - ambient) * max(sphere_light, 0.0) * day * sun_color);
		lit = mix(lit, cloud_lit, cover * 0.95);
	}

	float facing = clamp(dot(sw, V), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	float atmo_light = smoothstep(-0.25, 0.6, sphere_light);
	lit = mix(lit, atmo_color * (0.1 + 0.9 * atmo_light), atmo_haze * (0.5 + 0.5 * rim));
	lit += atmo_color * rim * atmo_strength * atmo_light;

	ALBEDO = lit;
}
